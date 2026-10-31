/// 快速记一笔 bottom sheet (v1.2 P1)
///
/// 类别网格 + 金额输入 + 备注 + 保存
/// 长按 + 按钮 0.5s 弹起
library quick_entry_sheet;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../theme/tokens.dart';
import '../widgets/category_icon.dart';

class QuickEntrySheet extends StatefulWidget {
  const QuickEntrySheet({super.key});

  @override
  State<QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends State<QuickEntrySheet> {
  TxType _type = TxType.expense;
  Category? _selected;
  String _amount = '0';
  String _note = '';
  List<Category> _cats = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await CategoryRepository.instance.byType(_type);
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _selected = null;
      _loading = false;
    });
  }

  void _setType(TxType t) async {
    setState(() {
      _type = t;
      _loading = true;
    });
    final cats = await CategoryRepository.instance.byType(t);
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _selected = null;
    });
  }

  void _tapKey(String k) {
    setState(() {
      if (k == 'del') {
        _amount = _amount.length <= 1 ? '0' : _amount.substring(0, _amount.length - 1);
        if (_amount.isEmpty) _amount = '0';
        return;
      }
      if (k == '.') {
        if (!_amount.contains('.')) _amount = _amount + '.';
        return;
      }
      if (_amount == '0') {
        _amount = k;
      } else if (_amount.contains('.')) {
        final idx = _amount.indexOf('.');
        if (_amount.length - idx - 1 < 2) _amount = _amount + k;
      } else {
        _amount = _amount + k;
      }
    });
  }

  Future<void> _save() async {
    if (_selected == null) {
      _toast('请选择分类');
      return;
    }
    final cents = (double.tryParse(_amount) ?? 0) * 100 ~/ 1;
    if (cents <= 0) {
      _toast('请输入金额');
      return;
    }
    final now = DateTime.now();
    final epochDay = DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
        86400000;
    await TxRepository.instance.insert(Tx(
      id: const Uuid().v4(),
      epochDay: epochDay,
      type: _type,
      categoryId: _selected!.id,
      amountCents: cents,
      note: _note,
      createdAt: now,
    ));
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _toast(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: L.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部条 + 关闭
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, color: L.textPrimary),
                    visualDensity: VisualDensity.compact,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _save,
                    child: const Text('保存',
                        style: TextStyle(color: L.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ],
              ),
              // 类型切换
              Row(
                children: [
                  _Tab(label: '支出', selected: _type == TxType.expense, onTap: () => _setType(TxType.expense)),
                  const SizedBox(width: 16),
                  _Tab(label: '收入', selected: _type == TxType.income, onTap: () => _setType(TxType.income)),
                  const Spacer(),
                  Text('¥ $_amount',
                      style: const TextStyle(
                          color: L.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              // 类别网格
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SizedBox(
                  height: 220,
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: _cats.length,
                    itemBuilder: (context, i) {
                      final c = _cats[i];
                      final sel = c.id == _selected?.id;
                      return InkWell(
                        onTap: () => setState(() => _selected = c),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(alignment: Alignment.center, children: [
                              CategoryIcon(iconKey: c.iconKey, size: 36),
                              if (sel) Positioned(
                                right: 0, bottom: 0,
                                child: Container(
                                  width: 12, height: 12,
                                  decoration: const BoxDecoration(color: L.brandYellow, shape: BoxShape.circle),
                                  child: const Icon(Icons.check, size: 9, color: L.textPrimary),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Text(c.name, style: TextStyle(
                                fontSize: 11,
                                color: sel ? L.textPrimary : L.textBody,
                                fontWeight: sel ? FontWeight.w600 : FontWeight.w400),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              // 备注
              TextField(
                onChanged: (v) => _note = v,
                decoration: InputDecoration(
                  hintText: '备注 (可选)',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: L.dividerLight),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              // 数字键盘 (简化版)
              Column(
                children: [
                  for (final row in const [
                    ['1','2','3'],
                    ['4','5','6'],
                    ['7','8','9'],
                    ['.','0','del'],
                  ])
                    Row(children: [
                      for (final k in row) Expanded(
                        child: InkWell(
                          onTap: () => _tapKey(k),
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(color: L.dividerLight, width: 0.5),
                            ),
                            child: k == 'del'
                                ? const Icon(Icons.backspace_outlined, color: L.textPrimary)
                                : Text(k, style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w500, color: L.textPrimary)),
                          ),
                        ),
                      ),
                    ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(label, style: TextStyle(
        color: selected ? L.textPrimary : L.textTertiary,
        fontSize: 16,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
      )),
    );
  }
}

/// 打开快速记一笔 sheet 的辅助方法
Future<bool> showQuickEntrySheet(BuildContext context) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const QuickEntrySheet(),
  );
  return ok == true;
}
