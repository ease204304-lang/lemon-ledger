/// 统计服务设置页 (v1.12.0)
///
/// 入口: 我的 → 统计服务 / 图表页顶部入口。
/// 功能:
///   - 服务端地址配置 + 连接测试
///   - 一键同步本地账本到服务端 (幂等, 可重复)
///   - 打开「统计报表」(StatsPage: 收入/支出/结余 三视图 + 趋势 + 分类/标签)
library;

import 'package:flutter/material.dart';

import '../services/stats_api.dart';
import '../services/stats_sync.dart';
import '../theme/tokens.dart';
import 'stats_page.dart';

class StatsSettingsPage extends StatefulWidget {
  const StatsSettingsPage({super.key});

  @override
  State<StatsSettingsPage> createState() => _StatsSettingsPageState();
}

class _StatsSettingsPageState extends State<StatsSettingsPage> {
  late final TextEditingController _urlCtrl;
  bool _testing = false;
  bool? _urlOk;
  String? _urlMsg;

  bool _syncing = false;
  int _syncDone = 0;
  int _syncTotal = 0;
  SyncResult? _lastResult;

  DateTime? _lastSyncAt;
  String? _bookId;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _loadState();
  }

  Future<void> _loadState() async {
    final url = await StatsSyncService.instance.getUrl();
    if (!mounted) return;
    _urlCtrl.text = url;
    setState(() {
      _lastSyncAt = null;
      _bookId = null;
    });
    final t = await StatsSyncService.instance.getLastSyncAt();
    final b = await StatsSyncService.instance.getBookId();
    if (!mounted) return;
    setState(() {
      _lastSyncAt = t;
      _bookId = b;
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    setState(() {
      _testing = true;
      _urlOk = null;
      _urlMsg = null;
    });
    // 地址为空时回退到默认值 (Uri.parse('') 会抛异常)
    final raw = _urlCtrl.text.trim();
    final url = raw.isEmpty ? StatsApiClient.endpoint : raw;
    try {
      await StatsSyncService.instance.setUrl(url);
      final ok = await StatsApiClient(baseUrl: url).ping();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _urlOk = ok;
        _urlMsg = ok
            ? '连接成功'
            : '连接失败: 请确认服务已启动、地址正确 (手机需与电脑同一网络)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _urlOk = false;
        _urlMsg = '连接失败: $e';
      });
    }
  }

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _syncDone = 0;
      _syncTotal = 0;
      _lastResult = null;
    });
    final r = await StatsSyncService.instance.sync(
      onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _syncDone = done;
            _syncTotal = total;
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastResult = r;
      _bookId = r.bookId ?? _bookId;
    });
    final t = await StatsSyncService.instance.getLastSyncAt();
    if (mounted) setState(() => _lastSyncAt = t);
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置绑定'),
        content: const Text('清除已绑定的服务端账本与维度映射。\n'
            '下次同步会按账本名重新查找/创建, 流水按幂等键去重, 不会重复。\n\n确定继续?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('重置')),
        ],
      ),
    );
    if (confirmed != true) return;
    await StatsSyncService.instance.reset();
    if (mounted) {
      setState(() {
        _lastSyncAt = null;
        _bookId = null;
        _lastResult = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已重置绑定')));
    }
  }

  void _openStats() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StatsPage(onNavigate: null)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      appBar: AppBar(title: const Text('统计服务')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(L.pageH, 8, L.pageH, 24),
          children: [
            _card('服务端', [
              SizedBox(
                height: 44,
                child: TextField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '服务端地址',
                    hintText: 'http://192.168.x.x:8000',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.tonal(
                    onPressed: _testing ? null : _saveAndTest,
                    child: _testing
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('保存并测试'),
                  ),
                  const SizedBox(width: 8),
                  if (_urlOk != null)
                    Icon(_urlOk! ? Icons.check_circle : Icons.cancel,
                        size: 18,
                        color: _urlOk! ? L.okGreen : Colors.redAccent),
                  if (_urlMsg != null)
                    Expanded(
                      child: Text(_urlMsg!,
                          style: const TextStyle(
                              fontSize: 11, color: L.textTertiary)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '提示: 手机与电脑连同一 Wi-Fi, 填电脑局域网 IP (ipconfig 查看)。'
                '模拟器填 http://10.0.2.2:8000',
                style: TextStyle(fontSize: 11, color: L.textTertiary),
              ),
            ]),
            const SizedBox(height: 12),
            _card('数据同步', [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('账本: ${_bookId != null ? "已绑定" : "未绑定"}',
                            style: const TextStyle(
                                fontSize: 13, color: L.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          _lastSyncAt == null
                              ? '上次同步: 从未'
                              : '上次同步: ${_fmtTime(_lastSyncAt!)}',
                          style: const TextStyle(
                              fontSize: 12, color: L.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: _syncing ? null : _sync,
                    style: FilledButton.styleFrom(backgroundColor: L.brandYellow),
                    child: _syncing
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('立即同步'),
                  ),
                ],
              ),
              if (_syncing && _syncTotal > 0) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                    value: _syncDone / _syncTotal,
                    backgroundColor: L.surfaceSubtle),
                const SizedBox(height: 4),
                Text('$_syncDone / $_syncTotal',
                    style: const TextStyle(
                        fontSize: 11, color: L.textTertiary)),
              ],
              if (_lastResult != null) ...[
                const SizedBox(height: 10),
                _resultView(_lastResult!),
              ],
            ]),
            const SizedBox(height: 12),
            _card('统计报表', [
              const Text('收入 / 支出 / 结余三视图, 趋势 + 分类榜 + 标签分析 + 同期对比。',
                  style: TextStyle(fontSize: 12, color: L.textSecondary)),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _openStats,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insights_outlined, size: 18),
                    const SizedBox(width: 6),
                    const Text('打开统计报表'),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextButton(onPressed: _reset, child: const Text('重置服务端绑定')),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: L.textPrimary)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _resultView(SyncResult r) {
    final color = r.ok ? L.okGreen : Colors.redAccent;
    final lines = <String>[
      if (r.ok) '同步完成' else '同步失败',
      '本地流水 $totalTxText 笔',
      '新上传 ${r.uploaded} · 已存在 ${r.deduplicated}${r.failed > 0 ? " · 失败 ${r.failed}" : ""}',
      if (r.error != null) r.error!,
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: L.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Text(l,
                style: TextStyle(
                    fontSize: 12,
                    color: l == r.error && !r.ok ? color : L.textSecondary)),
        ],
      ),
    );
  }

  String get totalTxText => '${_lastResult?.totalTx ?? 0}';

  static String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
