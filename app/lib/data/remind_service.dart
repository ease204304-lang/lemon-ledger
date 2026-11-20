/// 记账提醒服务 (v1.13.0)
///
/// 对标同类 APP 的「记账提醒」 (鲨鱼记账: 自定义每日提醒时间):
///   - 每日固定时间提醒 (默认 22:00)
///   - 打开 App 时检查「今天是否还没记账」→ 提示
///   - 用 Android NotificationChannel + 本地通知 (Android 13+ 需运行时权限)
///
/// 实现策略:
///   - 设置存 remind 表 (enabled / minute / last_fired_epoch_day)
///   - Android 侧用 AlarmManager 每日唤醒 → 发通知 (通过 MethodChannel)
///   - 降级方案: App 启动/回到前台时检查当天是否有流水, 无则弹提醒
library;

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';

/// 提醒配置
class RemindConfig {
  final bool enabled;
  final int minute; // 0..1439 (从 00:00 起算的分钟数)

  const RemindConfig({required this.enabled, required this.minute});

  static const RemindConfig off = RemindConfig(enabled: false, minute: 1320);

  int get hour => minute ~/ 60;
  int get minuteOfHour => minute % 60;

  /// "22:00"
  String get timeText =>
      '${hour.toString().padLeft(2, '0')}:${minuteOfHour.toString().padLeft(2, '0')}';

  /// 显示用文案
  String get desc => enabled ? '每天 $timeText 提醒记账' : '未开启';
}

class RemindService {
  static final RemindService instance = RemindService._();
  RemindService._();

  static const MethodChannel _channel = MethodChannel('lemon_ledger/remind');

  Future<RemindConfig> config() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('remind', limit: 1);
    if (rows.isEmpty) return RemindConfig.off;
    final r = rows.first;
    return RemindConfig(
      enabled: (r['enabled'] as int? ?? 0) == 1,
      minute: (r['minute'] as int?) ?? 1320,
    );
  }

  /// 开启/关闭并设置时间 (minute = hour*60 + minute)
  Future<void> setConfig({required bool enabled, required int minute}) async {
    final db = await AppDatabase.instance.db;
    await db.insert(
      'remind',
      {
        'id': 1,
        'enabled': enabled ? 1 : 0,
        'minute': minute.clamp(0, 1439),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // 通知 Android 侧调度/取消每日闹钟
    try {
      await _channel.invokeMethod<void>('scheduleReminder', {
        'enabled': enabled,
        'minute': minute.clamp(0, 1439),
      });
    } on PlatformException {
      // Android 侧未实现时静默降级 (App 内检查仍生效)
    } on MissingPluginException {
      // 同上
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final c = await config();
    await setConfig(enabled: enabled, minute: c.minute);
  }

  /// 记录今天已触发 (防重复)
  Future<void> markFired(int epochDay) async {
    final db = await AppDatabase.instance.db;
    await db.rawUpdate(
        'UPDATE remind SET last_fired_epoch_day = ? WHERE id = 1', [epochDay]);
  }

  Future<int> lastFiredEpochDay() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('remind',
        columns: ['last_fired_epoch_day'], limit: 1);
    if (rows.isEmpty) return 0;
    return rows.first['last_fired_epoch_day'] as int? ?? 0;
  }

  /// 今天是否已记过账 (任何一笔流水都算)
  Future<bool> hasTxToday() async {
    final db = await AppDatabase.instance.db;
    final today = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM tx WHERE epoch_day = ?', [today]);
    return ((rows.first['c'] as int?) ?? 0) > 0;
  }

  /// 是否应该现在提醒 (开启 + 今天没记账 + 已过设定时间 + 今天未提醒过)
  Future<bool> shouldRemindNow() async {
    final c = await config();
    if (!c.enabled) return false;
    final now = DateTime.now();
    final today = now.millisecondsSinceEpoch ~/ 86400000;
    if (await lastFiredEpochDay() == today) return false;
    if (now.hour * 60 + now.minute < c.minute) return false;
    if (await hasTxToday()) return false;
    return true;
  }

  /// 请求通知权限 (Android 13+ POST_NOTIFICATIONS)
  Future<bool> requestPermission() async {
    try {
      final ok = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
