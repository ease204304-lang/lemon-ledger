/// 语音服务 (v1.3 MVP)
///
/// 用 Android 系统 SpeechRecognizer 实现语音 → 文字
/// 通过 MethodChannel 调原生 Android 代码
///
/// 隐私: 录音不落盘, 解析完即丢
library;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceService {
  static const _channel = MethodChannel('lemon_ledger/voice');

  /// 检查权限
  static Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// 检查系统是否支持 STT
  static Future<bool> isAvailable() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 开始听写, 返回识别的文字
  /// (调用方需要在结果返回前保持 onPressed, 这里简化为一次性调用)
  static Future<String> listen({String locale = 'zh-CN'}) async {
    final ok = await ensurePermission();
    if (!ok) {
      throw VoicePermissionDeniedException();
    }
    try {
      final text = await _channel.invokeMethod<String>('listen', {
        'locale': locale,
      });
      return text ?? '';
    } on PlatformException catch (e) {
      if (e.code == 'NO_MATCH') return '';
      if (e.code == 'TIMEOUT') return '';
      rethrow;
    }
  }
}

class VoicePermissionDeniedException implements Exception {
  @override
  String toString() => '麦克风权限被拒绝';
}
