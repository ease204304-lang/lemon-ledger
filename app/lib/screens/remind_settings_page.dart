/// 记账提醒设置页 (v1.13.0)
///
/// 对标鲨鱼记账的「自定义每日提醒时间」:
///   - 开关 + 时间选择 (默认 22:00)
///   - 申请通知权限 (Android 13+)
library;

import 'package:flutter/material.dart';

import '../data/remind_service.dart';
import '../theme/tokens.dart';

class RemindSettingsPage extends StatefulWidget {
  const RemindSettingsPage({super.key});

  @override
  State<RemindSettingsPage> createState() => _RemindSettingsPageState();
}

class _RemindSettingsPageState extends State<RemindSettingsPage> {
  RemindConfig _cfg = const RemindConfig(enabled: false, minute: 1320);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await RemindService.instance.config();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _loading = false;
    });
  }

  Future<void> _toggle(bool on) async {
    if (on) {
      final ok = await RemindService.instance.requestPermission();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未获得通知权限, 将在 App 打开时提示')),
        );
      }
    }
    await RemindService.instance.setConfig(enabled: on, minute: _cfg.minute);
    await _load();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _cfg.hour, minute: _cfg.minuteOfHour),
      helpText: '选择提醒时间',
    );
    if (picked == null) return;
    await RemindService.instance.setConfig(
      enabled: _cfg.enabled,
      minute: picked.hour * 60 + picked.minute,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      appBar: AppBar(title: const Text('记账提醒')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(L.pageH, 12, L.pageH, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: L.surface,
                      borderRadius: BorderRadius.circular(L.cardR),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('每日提醒记账',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                          subtitle: Text(_cfg.desc,
                              style: const TextStyle(
                                  fontSize: 12, color: L.textTertiary)),
                          value: _cfg.enabled,
                          onChanged: _toggle,
                        ),
                        if (_cfg.enabled)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.schedule_outlined),
                            title: const Text('提醒时间'),
                            trailing: Text(_cfg.timeText,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            onTap: _pickTime,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '开启后, 每天到设定时间若当天还没有记账, 会发送通知提醒。\n'
                    '若系统通知权限被拒绝, 则在打开 App 时提示。',
                    style: TextStyle(fontSize: 12, color: L.textTertiary),
                  ),
                ],
              ),
      ),
    );
  }
}
