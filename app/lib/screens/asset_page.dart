/// 资产管理页 (v1.13.0)
///
/// 对标同类 APP 的「资产管理」模块 (iCost / 钱迹 / 鲨鱼):
///   - 净资产总览 (资产 - 负债)
///   - 账户列表 (现金/储蓄卡/信用卡/存款/理财) + 余额管理
///   - 新增/编辑/归档账户
library;

import 'package:flutter/material.dart';

import '../data/account_service.dart';
import '../data/models.dart';
import '../theme/tokens.dart';

class AssetPage extends StatefulWidget {
  final VoidCallback? onChanged; // 账户变动后回调 (供上层刷新)

  const AssetPage({super.key, this.onChanged});

  @override
  State<AssetPage> createState() => _AssetPageState();
}

class _AssetPageState extends State<AssetPage> {
  List<Account> _accounts = const [];
  int _netWorth = 0;
  int _assets = 0;
  int _liabilities = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = AccountService.instance;
    final list = await svc.all();
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _netWorth = svc.netWorthSync(list);
      _assets = svc.totalAssetsSync(list);
      _liabilities = svc.totalLiabilitiesSync(list);
      _loading = false;
    });
  }

  Future<void> _openEditor([Account? acc]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AccountEditor(account: acc),
    );
    if (saved == true) {
      await _load();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(L.pageH, 12, L.pageH, 24),
      children: [
        _summaryCard(),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text('我的账户',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: L.textPrimary)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加账户'),
            ),
          ],
        ),
        if (_accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text('还没有账户, 点击「添加账户」开始管理资产',
                  style: TextStyle(fontSize: 13, color: L.textTertiary)),
            ),
          )
        else
          for (final a in _accounts) _accountTile(a),
      ],
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('净资产', style: TextStyle(fontSize: 13, color: L.textSecondary)),
          const SizedBox(height: 4),
          Text(
            _fmtYuan(_netWorth),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: _netWorth < 0 ? L.warnRed : L.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniStat('总资产', _fmtYuan(_assets), L.okGreen),
              ),
              Container(width: 1, height: 28, color: L.dividerLight),
              Expanded(
                child: _miniStat('总负债', _fmtYuan(_liabilities), L.warnRed),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: L.textTertiary)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _accountTile(Account a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _openEditor(a),
        borderRadius: BorderRadius.circular(L.cardR),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: L.surface,
            borderRadius: BorderRadius.circular(L.cardR),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: a.kind.isLiability
                      ? L.warnRed.withValues(alpha: 0.12)
                      : L.brandYellowTrack,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(_iconOf(a.kind),
                    size: 20,
                    color: a.kind.isLiability ? L.warnRed : L.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(a.name,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: L.textPrimary)),
                        const SizedBox(width: 6),
                        Text(a.kind.zh,
                            style: const TextStyle(
                                fontSize: 11, color: L.textTertiary)),
                        if (a.archived)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Text('已归档',
                                style: TextStyle(
                                    fontSize: 10, color: L.textTertiary)),
                          ),
                      ],
                    ),
                    if (a.deltaCents != 0)
                      Text(
                        '较初始 ${a.deltaCents > 0 ? '+' : ''}${_fmtYuan(a.deltaCents)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: a.deltaCents > 0 ? L.okGreen : L.warnRed),
                      ),
                  ],
                ),
              ),
              Text(
                _fmtYuan(a.balanceCents),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: a.balanceCents < 0 ? L.warnRed : L.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconOf(AccountKind k) => switch (k) {
        AccountKind.cash => Icons.payments_outlined,
        AccountKind.debit => Icons.account_balance_outlined,
        AccountKind.credit => Icons.credit_card_outlined,
        AccountKind.saving => Icons.savings_outlined,
        AccountKind.invest => Icons.trending_up_outlined,
      };

  static String _fmtYuan(int cents) {
    final v = cents / 100;
    final neg = v < 0;
    final abs = v.abs();
    final s = abs.toStringAsFixed(2);
    final parts = s.split('.');
    final buf = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    return '${neg ? '-' : ''}¥${buf.toString()}.${parts[1]}';
  }
}

/// 账户新增/编辑弹窗
class _AccountEditor extends StatefulWidget {
  final Account? account;

  const _AccountEditor({this.account});

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balanceCtrl;
  late AccountKind _kind;
  late bool _includeNet;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _nameCtrl = TextEditingController(text: a?.name ?? '');
    _balanceCtrl = TextEditingController(
        text: a == null ? '' : (a.balanceCents / 100).toStringAsFixed(2));
    _kind = a?.kind ?? AccountKind.cash;
    _includeNet = a?.includeNet ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final cents = ((double.tryParse(_balanceCtrl.text.trim()) ?? 0) * 100).round();
    final svc = AccountService.instance;
    final existing = widget.account;
    if (existing == null) {
      await svc.insert(Account(
        id: AccountService.newId(name),
        name: name,
        kind: _kind,
        balanceCents: cents,
        initialCents: cents,
        currency: 'CNY',
        includeNet: _includeNet,
        archived: false,
        sortOrder: DateTime.now().millisecondsSinceEpoch % 100000,
      ));
    } else {
      await svc.update(Account(
        id: existing.id,
        name: name,
        kind: _kind,
        balanceCents: cents,
        initialCents: existing.initialCents,
        currency: existing.currency,
        includeNet: _includeNet,
        archived: existing.archived,
        sortOrder: existing.sortOrder,
      ));
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _archive() async {
    final a = widget.account;
    if (a == null) return;
    await AccountService.instance.archive(a.id, !a.archived);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.account != null;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: L.pageH,
          right: L.pageH,
          top: 12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: L.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(editing ? '编辑账户' : '添加账户',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '账户名称',
                hintText: '如 招行卡 / 现金 / 支付宝',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _balanceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: '当前余额 (元)',
                hintText: '信用卡欠款填负数',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            const Text('账户类型',
                style: TextStyle(fontSize: 13, color: L.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final k in AccountKind.values)
                  ChoiceChip(
                    label: Text(k.zh),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('计入净资产',
                  style: TextStyle(fontSize: 14, color: L.textPrimary)),
              subtitle: const Text('关闭后该账户不参与净资产汇总',
                  style: TextStyle(fontSize: 11, color: L.textTertiary)),
              value: _includeNet,
              onChanged: (v) => setState(() => _includeNet = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (editing)
                  TextButton(
                    onPressed: _archive,
                    child: Text(widget.account!.archived ? '取消归档' : '归档'),
                  ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: L.brandYellow),
                  onPressed: _save,
                  child: Text(editing ? '保存' : '添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
