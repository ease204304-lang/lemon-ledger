// 数据同步层测试 (v1.12.0)
//
// 用 http/testing MockClient 模拟服务端, 验证 StatsSyncService.sync 全流程:
//   - 账本按名字查找/创建, book_id 持久化
//   - 分类按 (名称, 类型) 对齐, 缺失创建
//   - 标签按名称对齐
//   - 流水带 client_ref 幂等键上传; 重复响应 deduplicated 计数
//   - 服务端不可达 → ok:false
import 'dart:convert';

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/data/models.dart';
import 'package:lemon_ledger/data/repository.dart';
import 'package:lemon_ledger/services/stats_api.dart';
import 'package:lemon_ledger/services/stats_sync.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _MockPathProvider(this.tempDir);
  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir;
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppDatabase.instance.close();
    final tempDir = await Directory.systemTemp.createTemp('sync_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  test('完整同步流程: 账本/分类/标签/流水 + client_ref 幂等', () async {
    // ── 本地造数据 (用种子外的自定义分类, 避免与默认 22 类冲突) ──
    final cat = Category(
        id: 'cat.mycustom', name: '合同检查', iconKey: 'other',
        type: TxType.expense, sortOrder: 99);
    await CategoryRepository.instance.insert(cat);
    final now = DateTime.now();
    final t1 = Tx(
        id: 'local-tx-001', epochDay: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 86400000,
        type: TxType.expense, categoryId: cat.id,
        amountCents: 3850, note: '午餐 咖啡', createdAt: now);
    final t2 = Tx(
        id: 'local-tx-002', epochDay: now.millisecondsSinceEpoch ~/ 86400000,
        type: TxType.income, categoryId: cat.id,
        amountCents: 100000, note: '', createdAt: now);
    await TxRepository.instance.insert(t1);
    await TxRepository.instance.insert(t2);
    // t1 的标签关联 (备注整体作为一个标签)
    final db = await AppDatabase.instance.db;
    await db.insert('tx_tag', {'tx_id': t1.id, 'tag_name': '午餐 咖啡'});

    // ── Mock 服务端 ──
    final posted = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path == '/openapi.json') return _json({'openapi': '3.0.0'});
      if (path == '/api/books' && req.method == 'GET') {
        return _json({
          'data': {'items': [], 'total': 0}
        });
      }
      if (path == '/api/books' && req.method == 'POST') {
        return _json({
          'data': {'id': 'book_srv', 'name': '我的账本'},
          'meta': {'snapshot_version': 1}
        });
      }
      if (path == '/api/categories' && req.method == 'GET') {
        return _json({
          'data': {'items': [], 'total': 0}
        });
      }
      if (path == '/api/categories' && req.method == 'POST') {
        return _json({
          'data': {'id': 'cat_srv_1', 'name': '餐饮'},
          'meta': {'snapshot_version': 1}
        });
      }
      if (path == '/api/tags' && req.method == 'GET') {
        return _json({
          'data': {'items': [], 'total': 0}
        });
      }
      if (path == '/api/tags' && req.method == 'POST') {
        return _json({
          'data': {'id': 'tag_srv_1', 'name': '午餐 咖啡'},
          'meta': {'snapshot_version': 1}
        });
      }
      if (path == '/api/transactions' && req.method == 'POST') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        posted.add(body);
        // 第一笔正常插入, 第二笔模拟已存在 (dedup)
        final dup = body['client_ref'] == 'local-tx-002';
        return _json({
          'data': {
            'id': dup ? 'tx_srv_old' : 'tx_srv_new',
            'deduplicated': dup,
          },
          'meta': {'snapshot_version': 5}
        });
      }
      return _json({'error': {'code': 'NOT_FOUND', 'message': path}}, 404);
    });

    final result = await StatsSyncService.instance.sync(client: StatsApiClient(baseUrl: 'http://test', httpClient: client));

    // ── 断言结果 ──
    expect(result.ok, isTrue);
    // 本地库含种子流水 (18 笔) + 本用例插入的 2 笔
    final localCount = (await TxRepository.instance.all())
        .where((t) => t.type != TxType.transfer)
        .length;
    expect(result.totalTx, localCount);
    expect(localCount, greaterThanOrEqualTo(2));
    // 本用例的两笔: 一笔新上传, 一笔服务端判定重复
    // (种子流水也会被全量上传, 所以 uploaded 数量 >= 1)
    expect(result.uploaded, greaterThanOrEqualTo(1));
    expect(result.deduplicated, 1,
        reason: '只有 client_ref=local-tx-002 被服务端判为已存在');
    expect(result.failed, 0);
    expect(result.bookId, 'book_srv');

    // 流水请求体契约 (本用例的两笔)
    final mine = posted.where((p) =>
        p['client_ref'] == 'local-tx-001' || p['client_ref'] == 'local-tx-002');
    expect(mine.length, 2);
    final first = posted.firstWhere((p) => p['client_ref'] == 'local-tx-001');
    expect(first['book_id'], 'book_srv');
    expect(first['type'], 'expense');
    expect(first['amount'], '38.50');
    expect(first['category_id'], 'cat_srv_1');
    expect(first['primary_tag_id'], 'tag_srv_1');

    // book_id / 映射持久化
    expect(await StatsSyncService.instance.getBookId(), 'book_srv');
    expect((await StatsSyncService.instance.getLastSyncAt()), isNotNull);
  });

  test('服务端不可达 → ok:false 且信息友好', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/openapi.json') {
        throw http.ClientException('connection refused');
      }
      return _json({}, 500);
    });
    final r = await StatsSyncService.instance
        .sync(client: StatsApiClient(baseUrl: 'http://test', httpClient: client));
    expect(r.ok, isFalse);
    expect(r.error, contains('无法连接'));
  });

  test('重复同步: 已有账本按名字复用, 不再创建', () async {
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path == '/openapi.json') return _json({});
      if (path == '/api/books' && req.method == 'GET') {
        return _json({
          'data': {
            'items': [
              {'id': 'book_existing', 'name': '我的账本'}
            ]
          }
        });
      }
      if (path == '/api/books' && req.method == 'POST') {
        return _json({'data': {'id': 'book_created'}});
      }
      // 维度接口: 空列表 (本地默认分类会逐个创建)
      if (path == '/api/categories' && req.method == 'GET') {
        return _json({'data': {'items': [], 'total': 0}});
      }
      if (path == '/api/categories' && req.method == 'POST') {
        return _json({'data': {'id': 'cat_new', 'name': 'x'}});
      }
      if (path == '/api/tags' && req.method == 'GET') {
        return _json({'data': {'items': [], 'total': 0}});
      }
      if (path == '/api/tags' && req.method == 'POST') {
        return _json({'data': {'id': 'tag_new', 'name': 'x'}});
      }
      if (path == '/api/transactions' && req.method == 'POST') {
        return _json({'data': {'id': 'tx_new'}});
      }
      return _json({'error': {'code': 'X', 'message': path}}, 404);
    });
    // ping 后账本阶段返回已有 → sync 应停在流水前的某一步 (本地无流水)
    final r = await StatsSyncService.instance
        .sync(client: StatsApiClient(baseUrl: 'http://test', httpClient: client));
    expect(r.bookId, 'book_existing');
    expect(await StatsSyncService.instance.getBookId(), 'book_existing');
  });
}
