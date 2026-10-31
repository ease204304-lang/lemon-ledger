/// 单笔排行页 (v1.2 P0)
///
/// 显示某月所有某类型的流水, 按金额 / 按时间 排序
library ranking_page;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../theme/tokens.dart';
import '../widgets/category_icon.dart';

class RankingPage extends StatefulWidget {
  final int year;
  final int month;
  final TxType type;
  const RankingPage({
    super.key, required this.year, required this.month, required this.type,
  });

  @override
  State<RankingPage> createState() => _RankingPageState();
}

enum _RankMode { amount, time }

class _RankingPageState extends State<RankingPage> {
  _RankMode _mode = _RankMode.amount;
  late Future<_RankData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RankData> _load() async {
    final repo = TxRepository.instance;
    final cats = {for (final c in await CategoryRepository.instance.all()) c.id: c};
    final list = await repo.monthTxs(widget.year, widget.month, widget.type);
    int total = 0;
    for (final t in list) {
      total += t.amountCents;
    }
    if (_mode == _RankMode.amount) {
      list.sort((a, b) => b.amountCents.compareTo(a.amountCents));
    } else {
      list.sort((a, b) {
        final c = b.epochDay.compareTo(a.epochDay);
        if (c != 0) return c;
        return b.createdAt.millisecondsSinceEpoch.compareTo(a.createdAt.millisecondsSinceEpoch);
      });
    }
    return _RankData(txs: list, total: total, cats: cats);
  }

  void _setMode(_RankMode m) {
    setState(() {
      _mode = m;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type == TxType.income;
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      appBar: AppBar(
        backgroundColor: L.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: L.textPrimary),
        ),
        title: Text('${widget.year}年${widget.month}月',
            style: const TextStyle(
                color: L.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<_RankData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: L.surface,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isIncome ? '本月总收入' : '本月总支出',
                      style: const TextStyle(
                          color: L.textTertiary, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(_fmt(data.total),
                        style: const TextStyle(
                            color: L.textPrimary,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5)),
                  ],
                ),
              ),
              // 单笔排行 + tabs
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(L.pageH, 12, L.pageH, 16),
                  decoration: BoxDecoration(
                    color: L.surface,
                    borderRadius: BorderRadius.circular(L.cardR),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Row(
                          children: [
                            Text(
                              isIncome ? '单笔收入排行' : '单笔支出排行',
                              style: const TextStyle(
                                  color: L.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            _ModeChip(label: '按金额', selected: _mode == _RankMode.amount, onTap: () => _setMode(_RankMode.amount)),
                            const SizedBox(width: 6),
                            _ModeChip(label: '按时间', selected: _mode == _RankMode.time, onTap: () => _setMode(_RankMode.time)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: data.txs.isEmpty
                            ? const Center(child: Text('本月暂无流水', style: TextStyle(color: L.textTertiary)))
                            : ListView.separated(
                                itemCount: data.txs.length,
                                separatorBuilder: (_, _) => const Divider(
                                    height: 1, thickness: 0.5,
                                    color: L.dividerLight, indent: 60, endIndent: 16),
                                itemBuilder: (context, i) {
                                  final t = data.txs[i];
                                  final cat = data.cats[t.categoryId];
                                  final pct = data.total == 0 ? 0.0 : (t.amountCents * 100.0 / data.total);
                                  final dt = DateTime.fromMillisecondsSinceEpoch(t.epochDay * 86400000);
                                  return ListTile(
                                    leading: CategoryIcon(iconKey: cat?.iconKey ?? 'else', size: 36),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            cat?.name ?? '未分类',
                                            style: const TextStyle(
                                                color: L.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                        Text(
                                          isIncome
                                              ? '+${(t.amountCents / 100).toStringAsFixed(2)}'
                                              : '-${(t.amountCents / 100).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              color: L.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              '${pct.toStringAsFixed(1)}%',
                                              style: const TextStyle(
                                                  color: L.textTertiary, fontSize: 12),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Container(
                                                height: 4,
                                                decoration: BoxDecoration(
                                                  color: L.dividerLight,
                                                  borderRadius: BorderRadius.circular(2),
                                                ),
                                                child: FractionallySizedBox(
                                                  widthFactor: (pct / 100).clamp(0.0, 1.0),
                                                  alignment: Alignment.centerLeft,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: L.brandYellow,
                                                      borderRadius: BorderRadius.circular(2),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          DateFormat('yyyy/MM/dd').format(dt),
                                          style: const TextStyle(
                                              color: L.textTertiary, fontSize: 12),
                                        ),
                                        if (t.note.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            t.note,
                                            style: const TextStyle(
                                                color: L.textTertiary, fontSize: 12),
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RankData {
  final List<Tx> txs;
  final int total;
  final Map<String, Category> cats;
  _RankData({required this.txs, required this.total, required this.cats});
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? L.brandYellowTrack : L.surfaceNote,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? L.textPrimary : L.textTertiary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}

String _fmt(int cents) {
  if (cents == 0) return '0';
  final s = (cents / 100).toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${buf.toString()}.${parts[1]}';
}

int _dateToEpochDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
        86400000;
