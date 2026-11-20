/// 应用锁页面 (v1.13.0 隐私锁)
///
/// 两种模式:
///   - 解锁模式: App 启动时拦截, 输入密码或生物识别通过才放行
///   - 设置模式: 在「我的」里开启/关闭、修改密码、开关生物识别
library;

import 'package:flutter/material.dart';

import '../data/app_lock_service.dart';
import '../theme/tokens.dart';

class AppLockPage extends StatefulWidget {
  /// true = 解锁模式 (拦截); false = 设置模式
  final bool unlockMode;
  final VoidCallback? onUnlocked;

  const AppLockPage({super.key, this.unlockMode = false, this.onUnlocked});

  @override
  State<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends State<AppLockPage> {
  final _ctrl = TextEditingController();
  String _input = '';
  String? _error;
  bool _loading = true;
  bool _biometricAvailable = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final svc = AppLockService.instance;
    final cfg = await svc.config();
    final canBio = await svc.canUseBiometric();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _biometricAvailable = canBio;
    });
    // 解锁模式 + 开了生物识别 → 尝试直接弹系统验证
    if (widget.unlockMode && cfg.biometric && canBio) {
      _tryBiometric();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final ok = await AppLockService.instance.authenticateBiometric();
    if (ok && mounted) {
      _pass();
    } else if (mounted) {
      setState(() => _error = '生物识别未通过, 请输入密码');
    }
  }

  void _pass() {
    if (widget.unlockMode) {
      widget.onUnlocked?.call();
      Navigator.of(context).maybePop(true);
    }
  }

  Future<void> _submit() async {
    if (_input.length < 4) {
      setState(() => _error = '请输入 4 位密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AppLockService.instance.verify(_input);
    if (!mounted) return;
    String? error;
    if (!ok) {
      final cfg = await AppLockService.instance.config();
      error = cfg.isLockedOut
          ? '密码错误, 已锁定 ${cfg.remainingSeconds} 秒'
          : '密码错误';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (!ok) _input = '';
    });
    if (ok) _pass();
  }

  void _press(String d) {
    if (_input.length >= 4) return;
    setState(() {
      _input += d;
      _error = null;
    });
  }

  void _backspace() {
    if (_input.isEmpty) return;
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: L.surfaceSubtle,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.unlockMode) {
      return _buildUnlock();
    }
    return _buildSettings();
  }

  // ── 解锁模式 ──────────────────────────────────────────────────────────
  Widget _buildUnlock() {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const Icon(Icons.lock_outline, size: 48, color: L.brandYellow),
            const SizedBox(height: 14),
            const Text('小猪记账',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: L.textPrimary)),
            const SizedBox(height: 6),
            const Text('输入密码解锁',
                style: TextStyle(fontSize: 13, color: L.textSecondary)),
            const SizedBox(height: 28),
            // 密码点
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _input.length ? L.brandYellow : Colors.transparent,
                      border: Border.all(
                        color: i < _input.length
                            ? L.brandYellow
                            : L.dividerLight,
                        width: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 20,
              child: _error == null
                  ? null
                  : Text(_error!,
                      style: const TextStyle(fontSize: 12, color: L.warnRed)),
            ),
            const Spacer(),
            _keypad(),
            const SizedBox(height: 24),
            if (_biometricAvailable)
              TextButton.icon(
                onPressed: _tryBiometric,
                icon: const Icon(Icons.fingerprint, size: 22),
                label: const Text('使用生物识别'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _keypad() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          for (final row in keys)
            Row(
              children: [
                for (final k in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: InkWell(
                        onTap: () => _press(k),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: L.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(k,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  color: L.textPrimary)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: InkWell(
                    onTap: () => _press('0'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: L.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('0',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: L.textPrimary)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: InkWell(
                    onTap: _backspace,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: L.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.backspace_outlined, size: 22),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: L.brandYellow),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('解锁'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 设置模式 ──────────────────────────────────────────────────────────
  Widget _buildSettings() {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      appBar: AppBar(title: const Text('隐私锁')),
      body: SafeArea(
        child: FutureBuilder<AppLockConfig>(
          future: AppLockService.instance.config(),
          builder: (context, snap) {
            final cfg = snap.data ?? AppLockConfig.off;
            return ListView(
              padding: const EdgeInsets.fromLTRB(L.pageH, 12, L.pageH, 24),
              children: [
                _card([
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开启应用锁',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: const Text('打开 App 时需要密码才能进入',
                        style: TextStyle(fontSize: 12, color: L.textTertiary)),
                    value: cfg.enabled,
                    onChanged: (v) => _toggleEnable(v),
                  ),
                ]),
                const SizedBox(height: 12),
                if (cfg.enabled) ...[
                  _card([
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.password_outlined),
                      title: const Text('修改密码'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changePassword,
                    ),
                    if (_biometricAvailable)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('生物识别解锁'),
                        subtitle: const Text('支持指纹/人脸时可用',
                            style: TextStyle(
                                fontSize: 12, color: L.textTertiary)),
                        value: cfg.biometric,
                        onChanged: (v) async {
                          await AppLockService.instance.setBiometric(v);
                          setState(() {});
                        },
                      ),
                  ]),
                ],
                const SizedBox(height: 12),
                const Text(
                  '说明: 密码仅以哈希形式存储在本机, 不上传任何服务器。\n'
                  '连续输错 5 次将锁定 60 秒。',
                  style: TextStyle(fontSize: 12, color: L.textTertiary),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Column(children: children),
    );
  }

  Future<void> _toggleEnable(bool on) async {
    final svc = AppLockService.instance;
    if (on) {
      final pwd = await _askPassword('设置密码', '设置 4 位数字密码');
      if (pwd == null) return;
      await svc.enable(pwd);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已开启应用锁')));
    } else {
      final pwd = await _askPassword('验证密码', '请输入当前密码以关闭应用锁');
      if (pwd == null) return;
      final ok = await svc.verify(pwd);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('密码错误')));
        return;
      }
      await svc.disable();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已关闭应用锁')));
    }
    setState(() {});
  }

  Future<void> _changePassword() async {
    final oldPwd = await _askPassword('当前密码', '请输入当前密码');
    if (oldPwd == null) return;
    final ok = await AppLockService.instance.verify(oldPwd);
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前密码不正确')));
      return;
    }
    final newPwd = await _askPassword('新密码', '设置新的 4 位数字密码');
    if (newPwd == null) return;
    await AppLockService.instance.changePassword(oldPwd, newPwd);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('密码已修改')));
  }

  /// 弹出密码输入对话框, 返回密码 (取消返回 null)
  Future<String?> _askPassword(String title, String hint) async {
    final ctrl = TextEditingController();
    final pwd = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: L.brandYellow),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (pwd == null || pwd.length < 4) return null;
    return pwd;
  }
}
