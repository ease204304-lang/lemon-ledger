/// 分类预算页 (v1.13.0)
///
/// 对标同类 APP 的「分类预算」:
///   - 按月设置各分类支出上限
///   - 实时显示已用/剩余 + 进度条
///   - 超支 (红) / 预警 80% (橙) 两级提示
library;

import 'package:flutter/material.dart';

import '../data/category_budget_service.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme/tokens.dart';

class CategoryBudgetPage extends StatefulWidget {
  final int year;
  final int month;

  const CategoryBudgetPage({
    super.key,
    required this.year,
    required this.month,
  });

  @override
  State<CategoryBudgetPage> createState() => _CategoryBudgetPageState();
}

class _CategoryBudgetPageState extends State<CategoryBudgetPage> {
  List<CategoryBudgetStatus> _statuses = const [];
  List<Category> _expenseCats = const[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = CategoryBudgetService.instance;
    final st = await svc.statuses(widget.year, widget.month);
    final cats = await CategoryRepository.instance.byType(TxType.expense);
    if (!mounted) return;
    setState(() {
      _statuses = st;
      _expenseCats = cats.where((c) => !c.archived).toList();
      _loading = false;
    });
  }

  Future<void> _edit(Category cat) async {
    final current = await CategoryBudgetService.instance
        .get(widget.year, widget.month, cat.id);
    final ctrl = TextEditingController(
        text: current > 0 ? (current / 100).toStringAsFixed(0) : '');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${cat.name} 预算'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '月度上限 (元)',
            hintText: '留空或 0 = 不限制',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: L.brandYellow),
            onPressed: () => Navigator.pop(
                ctx, ((double.tryParse(ctrl.text.trim()) ?? 0) * 100).round()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (v == null) return;
    await CategoryBudgetService.instance
        .set(widget.year, widget.month, cat.id, v);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      appBar: AppBar(title: Text('${widget.year} 年 ${widget.month} 月 分类预算')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(L.pageH, 12, L.pageH, 24),
                children: [
                  if (_statuses.isNotEmpty) ...[
                    _summary(),
                    const SizedBox(height: 14),
                  ],
                  const Text('点分类设置预算',
                      style: TextStyle(fontSize: 12, color: L.textTertiary)),
                  const SizedBox(height: 8),
                  for (final c in _expenseCats) _catTile(c),
                ],
              ),
      ),
    );
  }

  Widget _summary() {
    var budget = 0, used = 0;
    var over = 0, warn = 0;
    for (final s in _statuses) {
      budget += s.budgetCents;
      used += s.usedCents;
      if (s.state == BudgetState.over) over++;
      if (s.state == BudgetState.warn) warn++;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('分类预算合计',
                    style: TextStyle(fontSize: 12, color: L.textSecondary)),
                const SizedBox(height: 4),
                Text('${_yuan(used)} / ${_yuan(budget)}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (over > 0)
            _chip('$over 超支', L.warnRed),
          if (warn > 0) ...[
            const SizedBox(width: 6),
            _chip('$warn 预警', const Color(0xFFFF8A4A)),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _catTile(Category c) {
    final st = _statuses.where((s) => s.categoryId == c.id).toList();
    final s = st.isEmpty ? null : st.first;
    final hasBudget = s != null && s.budgetCents > 0;
    final color = switch (s?.state ?? BudgetState.none) {
      BudgetState.over => L.warnRed,
      BudgetState.warn => const Color(0xFFFF8A4A),
      _ => L.textPrimary,
    };
    return InkWell(
      onTap: () => _edit(c),
      borderRadius: BorderRadius.circular(L.cardR),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: L.surface,
          borderRadius: BorderRadius.circular(L.cardR),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(c.name,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color)),
                const Spacer(),
                if (hasBudget)
                  Text(
                    '${_yuan(s!.usedCents)} / ${_yuan(s.budgetCents)}',
                    style: TextStyle(fontSize: 13, color: color),
                  )
                else
                  const Text('未设置',
                      style: TextStyle(fontSize: 12, color: L.textTertiary)),
              ],
            ),
            if (hasBudget) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: s!.ratio.clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: L.surfaceSubtle,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              if (s.isOver) ...[
                const SizedBox(height: 4),
                Text('已超支 ${_yuan(-s.remainCents)}',
                    style: const TextStyle(fontSize: 11, color: L.warnRed)),
              ] else if (s.isWarn) ...[
                const SizedBox(height: 4),
                Text('已用 ${(s.ratio * 100).toStringAsFixed(0)}%, 注意控制',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFFF8A4A))),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _yuan(int cents) {
    final v = (cents / 100).abs();
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final buf = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    return '¥${buf.toString()}.${parts[1]}';
  }
}
