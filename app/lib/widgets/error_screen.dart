/// 自定义错误页 (E1 改进项)
/// 当 widget build 抛异常时, Flutter 会调 ErrorWidget.builder
/// 默认是 debug 红屏, release 是黑屏. 我们替换成友好错误页:
///
///  - 顶部 ⚠️ + "出错了"
///  - 错误描述 (Flutter 传入的 detail.message)
///  - 折叠的 stacktrace 详情 (debug + release 都显示, 高级用户排查)
///  - "重试" 按钮 (重建 RootShell)
///  - "反馈" 按钮 (打开 About 弹关于页)
///
/// 同时在 main() 里加了 ErrorWidget.builder 全局设置
/// crash 详情另外异步写入 log 文件 (不阻塞 UI)
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme/tokens.dart';

class AppErrorScreen extends StatelessWidget {
  final FlutterErrorDetails details;
  const AppErrorScreen({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    // 异步写日志 (不 await, 不阻塞 UI)
    _writeCrashLog(details);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: L.surfaceSubtle,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: L.warnRed),
                const SizedBox(height: 16),
                const Text('出错了',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: L.textPrimary)),
                const SizedBox(height: 8),
                Text(_summary(details),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14, color: L.textSecondary)),
                const SizedBox(height: 24),
                // 折叠的 stacktrace 详情
                _DetailsBox(details: details),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        // 触发 root rebuild
                        (context as Element).markNeedsBuild();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _summary(FlutterErrorDetails d) {
    final ex = d.exception;
    final msg = ex.toString();
    if (msg.length > 200) return '${msg.substring(0, 200)}…';
    return msg;
  }

  Future<void> _writeCrashLog(FlutterErrorDetails d) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File(p.join(dir.path, 'crash_$ts.txt'));
      final buf = StringBuffer();
      buf.writeln('=== 小猪记账 crash report ===');
      buf.writeln('Time: ${DateTime.now()}');
      buf.writeln('--- exception ---');
      buf.writeln(d.exception);
      buf.writeln('--- stack ---');
      buf.writeln(d.stack);
      buf.writeln('--- library ---');
      buf.writeln(d.library);
      if (d.context != null) {
        buf.writeln('--- context ---');
        buf.writeln(d.context);
      }
      await file.writeAsString(buf.toString());
    } catch (e) {
      // 写日志失败不能抛
      debugPrint('crash log write failed: $e');
    }
  }
}

class _DetailsBox extends StatefulWidget {
  final FlutterErrorDetails details;
  const _DetailsBox({required this.details});

  @override
  State<_DetailsBox> createState() => _DetailsBoxState();
}

class _DetailsBoxState extends State<_DetailsBox> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: L.dividerLight, width: 0.5),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.code, size: 14, color: L.textTertiary),
                  const SizedBox(width: 6),
                  const Text('查看详情',
                      style: TextStyle(
                          fontSize: 12, color: L.textTertiary)),
                  const Spacer(),
                  Icon(_expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 16,
                      color: L.textTertiary),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                widget.details.exception.toString() +
                    '\n' +
                    (widget.details.stack?.toString() ?? '(no stack)'),
                style: const TextStyle(
                  fontSize: 11,
                  color: L.textTertiary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 注册到 FlutterError.onError, 防止 zone 外异常被吞掉
void installGlobalErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // 在 release 模式也打印到 logcat (debug 默认行为)
    debugPrint('Flutter error: ${details.exception}');
  };

  // platform 异步异常 (如 Future.error 没被 catch)
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Platform error: $error\n$stack');
    return true;
  };
}
