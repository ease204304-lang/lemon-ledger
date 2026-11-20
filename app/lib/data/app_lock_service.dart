/// 隐私锁服务 (v1.13.0)
///
/// 对标同类 APP 的「隐私密码 / Face ID 解锁」 (鲨鱼/iCost 会员功能):
///   - 4 位数字密码 (哈希存储, 不存明文)
///   - 生物识别开关 (Android: BiometricPrompt)
///   - 连续输错锁定 (防暴力破解)
///
/// 安全说明:
///   - 密码用 SHA-256 + 固定盐存储; 本地单机应用, 防的是「随手翻看」
///   - 失败 5 次锁定 60 秒
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';

class AppLockConfig {
  final bool enabled;
  final bool biometric;
  final int failedCount;
  final int lockedUntil; // epoch ms

  const AppLockConfig({
    required this.enabled,
    required this.biometric,
    required this.failedCount,
    required this.lockedUntil,
  });

  static const AppLockConfig off =
      AppLockConfig(enabled: false, biometric: false, failedCount: 0, lockedUntil: 0);

  bool get isLockedOut =>
      lockedUntil > DateTime.now().millisecondsSinceEpoch;

  int get remainingSeconds {
    if (!isLockedOut) return 0;
    return ((lockedUntil - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
  }
}

class AppLockService {
  static final AppLockService instance = AppLockService._();
  AppLockService._();

  static const MethodChannel _channel = MethodChannel('lemon_ledger/biometric');

  /// 最大失败次数
  static const int maxFailed = 5;
  /// 锁定时长 (秒)
  static const int lockSeconds = 60;

  /// 固定盐 (本地单机应用, 用于避免同密码哈希相同)
  static const String _salt = 'lemon_ledger_v1';

  Future<AppLockConfig> config() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('app_lock', limit: 1);
    if (rows.isEmpty) return AppLockConfig.off;
    final r = rows.first;
    return AppLockConfig(
      enabled: (r['enabled'] as int? ?? 0) == 1,
      biometric: (r['biometric'] as int? ?? 0) == 1,
      failedCount: (r['failed_count'] as int?) ?? 0,
      lockedUntil: (r['locked_until'] as int?) ?? 0,
    );
  }

  /// 密码哈希 (SHA-256)
  static String hash(String password) =>
      sha256.convert(utf8.encode('$_salt:$password')).toString();

  /// 开启应用锁 (设置密码)
  Future<void> enable(String password) async {
    final db = await AppDatabase.instance.db;
    await db.insert(
      'app_lock',
      {
        'id': 1,
        'enabled': 1,
        'password_hash': hash(password),
        'biometric': 0,
        'failed_count': 0,
        'locked_until': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 关闭应用锁
  Future<void> disable() async {
    final db = await AppDatabase.instance.db;
    await db.insert(
      'app_lock',
      {
        'id': 1,
        'enabled': 0,
        'password_hash': null,
        'biometric': 0,
        'failed_count': 0,
        'locked_until': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 修改密码
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final ok = await verify(oldPassword);
    if (!ok) throw StateError('原密码不正确');
    final db = await AppDatabase.instance.db;
    await db.update('app_lock', {'password_hash': hash(newPassword)},
        where: 'id = 1');
  }

  /// 校验密码 (失败计数 + 锁定)
  Future<bool> verify(String password) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('app_lock', limit: 1);
    if (rows.isEmpty) return true; // 未启用
    final r = rows.first;
    final stored = r['password_hash'] as String?;
    if (stored == null) return true;
    if (hash(password) == stored) {
      await db.update('app_lock', {'failed_count': 0, 'locked_until': 0},
          where: 'id = 1');
      return true;
    }
    // 失败: 计数 +1, 达上限则锁定
    final failed = ((r['failed_count'] as int?) ?? 0) + 1;
    final lockedUntil = failed >= maxFailed
        ? DateTime.now()
            .add(Duration(seconds: lockSeconds))
            .millisecondsSinceEpoch
        : (r['locked_until'] as int?) ?? 0;
    await db.update('app_lock', {'failed_count': failed, 'locked_until': lockedUntil},
        where: 'id = 1');
    return false;
  }

  /// 生物识别开关
  Future<void> setBiometric(bool on) async {
    final db = await AppDatabase.instance.db;
    await db.update('app_lock', {'biometric': on ? 1 : 0}, where: 'id = 1');
  }

  /// 调起系统生物识别验证
  Future<bool> authenticateBiometric() async {
    try {
      final ok = await _channel.invokeMethod<bool>('authenticate');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 设备是否支持生物识别
  Future<bool> canUseBiometric() async {
    try {
      final ok = await _channel.invokeMethod<bool>('canAuthenticate');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 生成随机密码建议 (用户可用)
  static String randomPassword([int len = 4]) {
    final r = Random();
    return List.generate(len, (_) => r.nextInt(10)).join();
  }
}
