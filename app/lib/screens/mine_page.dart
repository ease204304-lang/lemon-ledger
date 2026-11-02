/// 我的页 — 设置、备份、导出、预算、主题、字号 (v1.2)
/// S1 改造: 改成 ConsumerWidget, 通过 themeProvider 改主题/字号, 不再需要 appState prop
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/budget_service.dart';
import '../data/database.dart';
import '../data/settings_service.dart';
import '../providers/theme_provider.dart';
import '../services/backup.dart';
import '../theme/tokens.dart';
import '../widgets/top_tab_bar.dart';
import 'import_data_dialog.dart';
import 'quick_entry_sheet.dart';


class MinePage extends ConsumerWidget {
  final ValueChanged<int> onNavigate;
  const MinePage({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      appBar: AppBar(title: const Text('我的')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(L.pageH, 8, L.pageH, 16),
          children: [
            // 顶部用户
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: L.surface,
                borderRadius: BorderRadius.circular(L.cardR),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: const BoxDecoration(
                      color: L.brandYellow,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.person, color: L.textPrimary, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('小猪记账', style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: L.textPrimary)),
                        SizedBox(height: 2),
                        Text('v1.10.0', style: TextStyle(
                            fontSize: 12, color: L.textTertiary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 预算
            _Section(items: [
              _Item('预算', '设置月度预算', Icons.flag_outlined, () {
                _setBudget(context);
              }),
            ]),
            const SizedBox(height: 12),
            // 个性化
            _Section(items: [
              _Item('主题', '浅色 / 深色 / 跟随系统', Icons.dark_mode_outlined, () {
                _setTheme(context, ref);
              }),
              _Item('字号', '小 / 中 / 大', Icons.text_fields_outlined, () {
                _setFontScale(context, ref);
              }),
            ]),
            const SizedBox(height: 12),
            // 数据
            _Section(items: [
              _Item('分类管理', '管理支出 / 收入分类', Icons.category_outlined, () {
                _toast(context, '该功能将在后续版本提供');
              }),
              _Item('数据备份', '本地 JSON 备份', Icons.cloud_download_outlined, () async {
                await BackupService.instance.exportJson();
                if (context.mounted) _toast(context, '已导出到下载目录');
              }),
              _Item('数据恢复', '从 JSON 备份恢复 (v1.5)', Icons.restore_outlined, () async {
                await ImportDataDialog.show(context);
              }),
              _Item('导出 CSV', '导出流水为 CSV', Icons.file_copy_outlined, () async {
                await BackupService.instance.exportCsv();
                if (context.mounted) _toast(context, '已导出 CSV');
              }),
              _Item('导出 Excel', '导出流水为 xlsx', Icons.table_view_outlined, () async {
                await BackupService.instance.exportXlsx();
                if (context.mounted) _toast(context, '已导出 xlsx');
              }),
            ]),
            const SizedBox(height: 12),
            // 后续版本
            _Section(items: [
              _Item('云同步', '开启云端同步 (v1.3)', Icons.cloud_sync_outlined, () {
                _toast(context, '云同步将在后续版本提供');
              }),
            ]),
            const SizedBox(height: 12),
            _Section(items: [
              _Item('关于', '小猪记账 v1.10.0', Icons.info_outline, () {
                showAboutDialog(context: context, applicationName: '小猪记账',
                    applicationVersion: '1.5.0', applicationIcon: const Icon(Icons.savings));
              }),
              _Item('重置数据', '清空全部流水与分类', Icons.restart_alt, () async {
                final controller = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (c) => AlertDialog(
                    title: Row(
                      children: [
                        const Icon(Icons.warning_amber,
                            color: L.warnRed, size: 20),
                        const SizedBox(width: 8),
                        const Text('危险操作'),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '将清空全部流水、预算与自定义分类，恢复初始种子数据。该操作不可撤销。',
                          style: TextStyle(fontSize: 13, color: L.textBody),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '建议先到上方"数据备份"导出 JSON, 再执行重置。',
                          style: TextStyle(
                              fontSize: 12, color: L.textTertiary),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '请输入 "确认" 两个字以解锁按钮:',
                          style: TextStyle(
                              fontSize: 12, color: L.textTertiary),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: '输入: 确认',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('取消'),
                      ),
                      // 响应式: 监听 controller, 输入 "确认" 才解锁
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (_, v, __) {
                          final match = v.text == '确认';
                          return FilledButton(
                            onPressed: match ? () => Navigator.pop(c, true) : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: L.warnRed,
                              foregroundColor: L.textPrimary,
                            ),
                            child: const Text('执行重置'),
                          );
                        },
                      ),
                    ],
                  ),
                );
                controller.dispose();
                if (ok == true) {
                  await AppDatabase.instance.resetForDebug();
                  if (context.mounted) {
                    _toast(context, '已重置，请重启应用');
                    // 1s 后强制退出 (用户开 app 重新 seed)
                    await Future.delayed(const Duration(seconds: 1));
                    if (context.mounted) {
                      // 不重启进程, 强制回到 HomePage 让 UI 重新加载
                      // Repository.instance 持有的 DB 已删, 重新打开会 re-seed
                      // 但 _HomePageState._future 已 cached, 需要 setState 触发
                      // 简单做法: pop 到 root (回到根), 用户切 tab 时会重建
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    }
                  }
                }
              }),
            ]),
          ],
        ),
      ),
      bottomNavigationBar: TopTabBar(
        currentIndex: 4,
        onTap: onNavigate,
        onAddLongPress: () => showQuickEntrySheet(context),
      ),
    );
  }

  void _toast(BuildContext context, String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _setBudget(BuildContext context) async {
    final now = DateTime.now();
    final cur = await BudgetService.instance.get(now.year, now.month);
    final controller = TextEditingController(
      text: cur == 0 ? '' : (cur / 100).toStringAsFixed(2),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${now.year}年${now.month}月 预算'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '输入月预算金额 (元)',
                prefixText: '¥ ',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          if (cur > 0)
            TextButton(
              onPressed: () => Navigator.pop(c, null),
              child: const Text('清除', style: TextStyle(color: L.warnRed)),
            ),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == null) {
      // 清除预算
      await BudgetService.instance.remove(now.year, now.month);
      if (context.mounted) _toast(context, '已清除月预算');
      return;
    }
    if (ok == true) {
      final v = double.tryParse(controller.text.trim());
      if (v == null || v <= 0) {
        if (context.mounted) _toast(context, '金额无效');
        return;
      }
      await BudgetService.instance.set(now.year, now.month, (v * 100).round());
      if (context.mounted) _toast(context, '已设置月预算 ¥${v.toStringAsFixed(2)}');
    }
  }

  Future<void> _setTheme(BuildContext context, WidgetRef ref) async {
    final cur = await SettingsService.instance.getTheme();
    if (!context.mounted) return;
    final ok = await showDialog<AppTheme>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('选择主题'),
        children: [
          for (final t in AppTheme.values)
            RadioListTile<AppTheme>(
              title: Text(_themeLabel(t)),
              value: t,
              groupValue: cur,
              onChanged: (v) => Navigator.pop(c, v),
            ),
        ],
      ),
    );
    if (ok != null) {
      // S1: 通过 themeProvider 改, 所有 ref.watch(themeProvider) 屏自动重建
      await ref.read(themeProvider.notifier).setTheme(ok);
      if (context.mounted) _toast(context, '已切换: ${_themeLabel(ok)}');
    }
  }

  Future<void> _setFontScale(BuildContext context, WidgetRef ref) async {
    final cur = await SettingsService.instance.getFontScale();
    if (!context.mounted) return;
    final ok = await showDialog<FontScale>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('选择字号'),
        children: [
          for (final f in FontScale.values)
            RadioListTile<FontScale>(
              title: Text(_fontLabel(f)),
              value: f,
              groupValue: cur,
              onChanged: (v) => Navigator.pop(c, v),
            ),
        ],
      ),
    );
    if (ok != null) {
      await ref.read(themeProvider.notifier).setFontScale(ok);
      if (context.mounted) _toast(context, '已切换: ${_fontLabel(ok)}');
    }
  }
}

String _themeLabel(AppTheme t) => switch (t) {
      AppTheme.light  => '浅色',
      AppTheme.dark   => '深色',
      AppTheme.system => '跟随系统',
    };

String _fontLabel(FontScale f) => switch (f) {
      FontScale.small  => '小',
      FontScale.medium => '中',
      FontScale.large  => '大',
    };

class _Section extends StatelessWidget {
  final List<_Item> items;
  const _Section({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            InkWell(
              onTap: items[i].onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Icon(items[i].icon, color: L.textPrimary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].title, style: const TextStyle(
                              fontSize: 15, color: L.textPrimary, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(items[i].subtitle, style: const TextStyle(
                              fontSize: 12, color: L.textTertiary)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: L.textTertiary, size: 20),
                  ],
                ),
              ),
            ),
            if (i != items.length - 1) const Divider(
                height: 1, thickness: 0.5, color: L.dividerLight, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _Item {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  _Item(this.title, this.subtitle, this.icon, this.onTap);
}
