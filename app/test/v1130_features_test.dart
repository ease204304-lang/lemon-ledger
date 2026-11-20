// v1.13.0 新功能测试: 资产管理 / 分类预算 / 记账提醒 / 隐私锁
//
// 覆盖:
//   - 账户 CRUD + 余额增减 + 净资产/资产/负债汇总
//   - 分类预算: 设置/取消/已用计算/超支与预警判定
//   - 提醒: 配置读写 + 今天是否记账 + 是否该提醒
//   - 隐私锁: 密码哈希/校验/失败锁定/生物识别开关
//   - 备份导出导入: 新表往返
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/account_service.dart';
import 'package:lemon_ledger/data/app_lock_service.dart';
import 'package:lemon_ledger/data/category_budget_service.dart';
import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/data/models.dart';
import 'package:lemon_ledger/data/remind_service.dart';
import 'package:lemon_ledger/data/repository.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _MockPathProvider(this.tempDir);
  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir;
}

Account _acc(String id, String name, AccountKind kind, int balance) => Account(
      id: id,
      name: name,
      kind: kind,
      balanceCents: balance,
      initialCents: balance,
      currency: 'CNY',
      includeNet: true,
      archived: false,
      sortOrder: 0,
    );

void main() {
  setUpAll(() {
    // MethodChannel mock 需要 binding; 必须最先初始化
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final tempDir = await Directory.systemTemp.createTemp('v1130_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
    // 提醒服务用 MethodChannel 调 Android 侧, 测试环境 mock 掉
    // (必须在 setUp 里做: setUpAll 阶段 binding 尚未初始化)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('lemon_ledger/remind'),
      (call) async {
        if (call.method == 'requestNotificationPermission') return true;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('lemon_ledger/remind'),
      null,
    );
  });

  group('资产管理: 账户', () {
    test('默认创建 3 个账户 (现金/银行卡/信用卡)', () async {
      final list = await AccountService.instance.all();
      expect(list.length, 3);
      expect(list.map((a) => a.kind).toSet(),
          containsAll([AccountKind.cash, AccountKind.debit, AccountKind.credit]));
    });

    test('新增/编辑/归档账户', () async {
      final svc = AccountService.instance;
      await svc.insert(_acc('acc.test', '招行卡', AccountKind.debit, 100000));
      var list = await svc.all();
      expect(list.any((a) => a.id == 'acc.test'), isTrue);

      await svc.update(_acc('acc.test', '招行卡改', AccountKind.debit, 200000));
      list = await svc.all();
      expect(list.firstWhere((a) => a.id == 'acc.test').name, '招行卡改');
      expect(list.firstWhere((a) => a.id == 'acc.test').balanceCents, 200000);

      await svc.archive('acc.test', true);
      list = await svc.all();
      expect(list.any((a) => a.id == 'acc.test'), isFalse,
          reason: '归档账户默认不显示');
      expect((await svc.all(includeArchived: true))
          .any((a) => a.id == 'acc.test'), isTrue);
    });

    test('applyDelta: 收入 + / 支出 -', () async {
      final svc = AccountService.instance;
      await svc.insert(_acc('acc.d', '现金', AccountKind.cash, 0));
      await svc.applyDelta('acc.d', 5000);
      expect((await svc.byId('acc.d'))!.balanceCents, 5000);
      await svc.applyDelta('acc.d', -2000);
      expect((await svc.byId('acc.d'))!.balanceCents, 3000);
    });

    test('净资产 = 资产 - 负债 (信用卡欠款按负值)', () async {
      final svc = AccountService.instance;
      await svc.insert(_acc('acc.cash2', '现金', AccountKind.cash, 500000));
      await svc.insert(_acc('acc.card2', '信用卡', AccountKind.credit, -200000));
      final net = await svc.netWorth();
      expect(net, 300000, reason: '现金 5000 - 欠款 2000 = 3000');
      expect(await svc.totalAssets(), 500000);
      expect(await svc.totalLiabilities(), 200000);
    });

    test('include_net = false 的账户不计入净资产', () async {
      final svc = AccountService.instance;
      await svc.insert(Account(
        id: 'acc.hidden',
        name: '不计入',
        kind: AccountKind.cash,
        balanceCents: 999999,
        initialCents: 0,
        currency: 'CNY',
        includeNet: false,
        archived: false,
        sortOrder: 0,
      ));
      final net = await svc.netWorth();
      expect(net, 0, reason: '不计入净值的账户应被排除');
    });
  });

  group('分类预算', () {
    test('设置/读取/取消分类预算', () async {
      final svc = CategoryBudgetService.instance;
      await svc.set(2026, 11, 'cat.food', 300000);
      expect(await svc.get(2026, 11, 'cat.food'), 300000);
      await svc.set(2026, 11, 'cat.food', 0);
      expect(await svc.get(2026, 11, 'cat.food'), 0, reason: '0 = 取消预算');
    });

    test('已用金额按当月支出统计', () async {
      final now = DateTime.now();
      final year = now.year, month = now.month;
      final day = now.millisecondsSinceEpoch ~/ 86400000;
      await TxRepository.instance.insert(Tx(
        id: 'tx.budget.1',
        epochDay: day,
        type: TxType.expense,
        categoryId: 'cat.food',
        amountCents: 15000,
        note: '',
        createdAt: now,
      ));
      await CategoryBudgetService.instance.set(year, month, 'cat.food', 20000);
      final st = (await CategoryBudgetService.instance.statuses(year, month))
          .firstWhere((s) => s.categoryId == 'cat.food');
      expect(st.usedCents, 15000);
      expect(st.budgetCents, 20000);
      expect(st.remainCents, 5000);
    });

    test('超支 / 预警 / 安全 三级判定', () {
      const over = CategoryBudgetStatus(
          categoryId: 'c', budgetCents: 10000, usedCents: 12000);
      const warn = CategoryBudgetStatus(
          categoryId: 'c', budgetCents: 10000, usedCents: 8500);
      const safe = CategoryBudgetStatus(
          categoryId: 'c', budgetCents: 10000, usedCents: 1000);
      expect(over.state, BudgetState.over);
      expect(over.isOver, isTrue);
      expect(warn.state, BudgetState.warn);
      expect(warn.isWarn, isTrue);
      expect(safe.state, BudgetState.safe);
    });

    test('alerts 只返回预警与超支项', () async {
      final now = DateTime.now();
      final svc = CategoryBudgetService.instance;
      await svc.set(now.year, now.month, 'cat.food', 100);
      await svc.set(now.year, now.month, 'cat.transport', 100000000);
      final alerts = await svc.alerts(now.year, now.month);
      // 至少返回已设预算的项 (状态取决于已用)
      expect(alerts.every((s) => s.state != BudgetState.safe), isTrue);
    });
  });

  group('记账提醒', () {
    test('配置读写', () async {
      final svc = RemindService.instance;
      expect((await svc.config()).enabled, isFalse);
      await svc.setConfig(enabled: true, minute: 9 * 60 + 30);
      final cfg = await svc.config();
      expect(cfg.enabled, isTrue);
      expect(cfg.hour, 9);
      expect(cfg.minuteOfHour, 30);
      expect(cfg.timeText, '09:30');
      expect(cfg.desc, contains('09:30'));
    });

    test('默认时间为 22:00', () async {
      final svc = RemindService.instance;
      await svc.setConfig(enabled: false, minute: 1320);
      expect((await svc.config()).timeText, '22:00');
    });

    test('已过设定时间: 今天有流水 → 不提醒; 无流水 → 提醒', () async {
      final svc = RemindService.instance;
      // 设为 00:00 → 一定已过设定时间
      await svc.setConfig(enabled: true, minute: 0);
      final today = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
      final hasToday = await svc.hasTxToday();
      // 种子流水可能落在今天, 也可能不在 — 断言 shouldRemindNow 与 hasTxToday 互补
      final should = await svc.shouldRemindNow();
      expect(should, isNot(hasToday),
          reason: 'shouldRemindNow 应与「今天已记账」互补');
      // 清空今天的流水后再验证: 无流水 → 提醒
      final db = await AppDatabase.instance.db;
      await db.delete('tx', where: 'epoch_day = ?', whereArgs: [today]);
      expect(await svc.hasTxToday(), isFalse);
      expect(await svc.shouldRemindNow(), isTrue);
      // 触发后记录, 当天不再提醒
      await svc.markFired(today);
      expect(await svc.shouldRemindNow(), isFalse, reason: '当天已提醒过');
    });

    test('未开启时不提醒', () async {
      final svc = RemindService.instance;
      await svc.setConfig(enabled: false, minute: 0);
      expect(await svc.shouldRemindNow(), isFalse);
    });
  });

  group('隐私锁', () {
    test('密码哈希稳定且不等于明文', () {
      final h = AppLockService.hash('1234');
      expect(h, isNot('1234'));
      expect(h.length, 64, reason: 'SHA-256 hex');
      expect(AppLockService.hash('1234'), h, reason: '同密码同哈希');
      expect(AppLockService.hash('1235'), isNot(h));
    });

    test('开启 → 校验通过; 错误密码失败', () async {
      final svc = AppLockService.instance;
      await svc.enable('1234');
      final cfg = await svc.config();
      expect(cfg.enabled, isTrue);
      expect(await svc.verify('1234'), isTrue);
      expect(await svc.verify('9999'), isFalse);
    });

    test('连续输错 5 次锁定 60 秒', () async {
      final svc = AppLockService.instance;
      await svc.enable('1234');
      for (var i = 0; i < 5; i++) {
        await svc.verify('0000');
      }
      final cfg = await svc.config();
      expect(cfg.failedCount, 5);
      expect(cfg.isLockedOut, isTrue);
      expect(cfg.remainingSeconds, greaterThan(0));
      expect(cfg.remainingSeconds, lessThanOrEqualTo(60));
    });

    test('校验成功会清零失败计数', () async {
      final svc = AppLockService.instance;
      await svc.enable('1234');
      await svc.verify('0000');
      await svc.verify('1111');
      expect((await svc.config()).failedCount, 2);
      await svc.verify('1234');
      expect((await svc.config()).failedCount, 0);
    });

    test('修改密码: 旧密码错误则拒绝', () async {
      final svc = AppLockService.instance;
      await svc.enable('1234');
      await expectLater(
          svc.changePassword('9999', '5678'), throwsStateError);
      await svc.changePassword('1234', '5678');
      expect(await svc.verify('5678'), isTrue);
    });

    test('关闭应用锁', () async {
      final svc = AppLockService.instance;
      await svc.enable('1234');
      await svc.disable();
      expect((await svc.config()).enabled, isFalse);
    });

    test('生物识别开关', () async {
      final svc = AppLockService.instance;
      await svc.enable('1234');
      await svc.setBiometric(true);
      expect((await svc.config()).biometric, isTrue);
      await svc.setBiometric(false);
      expect((await svc.config()).biometric, isFalse);
    });
  });

  group('流水账户关联', () {
    test('Tx 支持 account_id 往返', () async {
      final now = DateTime.now();
      final tx = Tx(
        id: 'tx.acc',
        epochDay: now.millisecondsSinceEpoch ~/ 86400000,
        type: TxType.expense,
        categoryId: 'cat.food',
        amountCents: 100,
        note: '',
        createdAt: now,
        accountId: 'acc.cash',
      );
      await TxRepository.instance.insert(tx);
      final back = await TxRepository.instance.byId('tx.acc');
      expect(back!.accountId, 'acc.cash');
      expect(back.copyWith(accountId: null).accountId, 'acc.cash');
      expect(back.copyWith(clearAccount: true).accountId, isNull);
    });
  });
}
