/// 数据恢复 (导入) UI (v1.5 新增)
///
/// 流程:
/// 1. 用户点"数据恢复" → 显示模式选择对话框
/// 2. 选"合并"或"覆盖" → 二次确认 (必须输"确认")
/// 3. 调用 [BackupService.importJson] → 失败 snackbar, 成功 snackbar
///
/// 文件路径来源:
/// - Android: 用 MethodChannel 调 ACTION_OPEN_DOCUMENT 选文件
/// - 桌面/开发: 走 fallback (让用户输路径, 不友好, 后续做)
library import_data_dialog;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../services/backup.dart';
import '../theme/tokens.dart';

/// MethodChannel: 让原生 Android 帮我们打开文件选择器
const _channel = MethodChannel('lemon_ledger/files');

class ImportDataDialog {
  /// 显示"数据恢复"对话框
  /// 返回 true = 用户成功导入, false = 用户取消
  static Future<bool> show(BuildContext context) async {
    // 1. 先选文件
    final path = await _pickFile(context);
    if (path == null) return false;

    // 2. 先快速 peek 文件
    final file = File(path);
    final peekErr = await BackupService.instance.peekJsonFile(file);
    if (peekErr != null) {
      _showError(context, peekErr);
      return false;
    }

    // 3. 选模式 (合并 vs 覆盖)
    if (!context.mounted) return false;
    final mode = await _showModeDialog(context);
    if (mode == null) return false;

    // 4. 二次确认 (输"确认"才解锁)
    if (!context.mounted) return false;
    final confirmed = await _showConfirmDialog(context, file.path, mode);
    if (!confirmed) return false;

    // 5. 执行导入
    if (!context.mounted) return false;
    try {
      final result = await BackupService.instance.importJson(file, mode: mode);
      if (!context.mounted) return false;
      _showSuccess(context, result);
      // 提示用户重启 app 让 UI 重新加载
      return true;
    } on ImportError catch (e) {
      if (!context.mounted) return false;
      _showError(context, e.kind);
      return false;
    } catch (e) {
      if (!context.mounted) return false;
      _showRawError(context, '导入失败: $e');
      return false;
    }
  }

  // ---- 文件选择 ----

  /// 用 MethodChannel 调 Android SAF 选文件
  /// 返回文件绝对路径, 用户取消则 null
  static Future<String?> _pickFile(BuildContext context) async {
    if (!Platform.isAndroid) {
      // 桌面/开发: 暂时用 snackbar 提示
      _toast(context, '桌面平台暂不支持文件选择, 请用 adb push 文件');
      return null;
    }
    try {
      final result = await _channel.invokeMethod<String>('pickJsonFile');
      if (result == null || result.isEmpty) return null;
      return result;
    } on PlatformException catch (e) {
      _showRawError(context, '选择文件失败: ${e.message ?? e.code}');
      return null;
    } catch (e) {
      _showRawError(context, '选择文件失败: $e');
      return null;
    }
  }

  // ---- 模式选择 ----

  static Future<ImportMode?> _showModeDialog(BuildContext context) async {
    return showDialog<ImportMode>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('选择恢复模式'),
        children: [
          _modeOption(
            icon: Icons.merge_outlined,
            iconColor: L.textPrimary,
            title: '合并 (推荐)',
            subtitle: '保留当前数据, 把备份中新的加进来, 同 ID 用备份覆盖',
            subtitleColor: L.textTertiary,
            onTap: () => Navigator.pop(c, ImportMode.merge),
          ),
          const SizedBox(height: 4),
          _modeOption(
            icon: Icons.delete_sweep_outlined,
            iconColor: L.warnRed,
            title: '完全覆盖',
            subtitle: '清空当前所有流水和分类, 只保留备份数据',
            subtitleColor: L.warnRed,
            onTap: () => Navigator.pop(c, ImportMode.replace),
          ),
        ],
      ),
    );
  }

  // ---- 二次确认 ----

  static Future<bool> _showConfirmDialog(
    BuildContext context,
    String filePath,
    ImportMode mode,
  ) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) {
          final input = controller.text;
          final isMatch = input == '确认';
          final isReplace = mode == ImportMode.replace;
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isReplace ? Icons.warning_amber : Icons.info_outline,
                  color: isReplace ? L.warnRed : L.textPrimary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(isReplace ? '危险操作' : '确认恢复'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fileInfo(filePath),
                const SizedBox(height: 12),
                Text(
                  isReplace
                      ? '完全覆盖将清空当前数据库中所有流水和预算, 无法恢复! 请先导出当前数据备份。'
                      : '合并将保留当前所有数据, 把备份里新数据合并进来, 同 ID 用备份的覆盖。',
                  style: const TextStyle(fontSize: 13, color: L.textBody),
                ),
                const SizedBox(height: 16),
                const Text(
                  '请输入 "确认" 两个字符以解锁按钮:',
                  style: TextStyle(fontSize: 12, color: L.textTertiary),
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
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: isMatch ? () => Navigator.pop(c, true) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: isReplace ? L.warnRed : L.brandYellow,
                  foregroundColor: L.textPrimary,
                ),
                child: const Text('确认执行'),
              ),
            ],
          );
        },
      ),
    );
    return ok ?? false;
  }

  // ---- 反馈 ----

  static void _showSuccess(BuildContext context, ImportResult result) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✓ 恢复成功\n$result'),
      duration: const Duration(seconds: 4),
      backgroundColor: L.okGreen,
    ));
  }

  static void _showError(BuildContext context, ImportErrorKind kind) {
    final msg = BackupService.errorMessage(kind);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✗ $msg'),
      duration: const Duration(seconds: 4),
      backgroundColor: L.warnRed,
    ));
  }

  static void _showRawError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✗ $msg'),
      duration: const Duration(seconds: 4),
      backgroundColor: L.warnRed,
    ));
  }

  static void _toast(BuildContext c, String s) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));
  }

  static Widget _fileInfo(String path) {
    // 截取文件名
    final fileName = path.split('/').last;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: L.surfaceNote,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 16, color: L.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: L.textBody),
            ),
          ),
        ],
      ),
    );
  }
}

/// SimpleDialog 模式选择项 (SimpleDialogOption 只接受 child, 自己包)
class _modeOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final VoidCallback onTap;
  const _modeOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: L.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(
                    fontSize: 12, color: subtitleColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
