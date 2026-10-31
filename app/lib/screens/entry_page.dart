/// 记账页 (v1.9.0 重设计: 分类 2/3 + 键盘 1/3 + 金额显示屏)
///
/// 新布局 (v1.9.0 调整):
///   1. 顶部条 (× 关闭 / 标题 / 语音 / 删除) — 简化, 高度缩小
///   2. 类型 chips + 日期 (一行, 无金额预览)
///   3. 常用分类 (Expanded flex 2, 占约 2/3 剩余空间, 5×N 网格可滚动)
///   4. 标签行 (增强显示: 更大字号 + 彩色 chip 背景)
///   5. 备注 (1 行)
///   6. 数字键盘 4×4 (固定高度 1/3, 顶部含大字金额显示屏)
///      金额显示屏 = 圆形/大字显示当前输入 (U2 实时求值)
///   7. = 按钮 触发实时求值 + 自动保存 + 跳回首页
library;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../data/tag_service.dart';
import '../services/nlu_service.dart';
import '../services/voice_service.dart';
import '../theme/tokens.dart';
import '../utils/calculator.dart';
import '../widgets/date_picker_dialog.dart';
import '../widgets/entry_keypad.dart';
import '../widgets/entry_short_note.dart';
import '../widgets/entry_split_categories.dart';
import 'tag_manager_page.dart';
import '../theme/tokens.dart' show L;

class EntryPage extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  final String? editTxId;
  const EntryPage({super.key, required this.onNavigate, this.editTxId});

  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  TxType _type = TxType.expense;
  Category? _selected;
  String _amount = '0';
  String _note = '';
  DateTime _date = DateTime.now();
  List<Tag> _tags = const [];
  final _noteCtrl = TextEditingController();
  bool _showAllCategories = false; // 常用 ↔ 全部

  @override
  void initState() {
    super.initState();
    if (widget.editTxId != null) {
      _loadForEdit(widget.editTxId!);
    } else {
      _loadTags();
    }
    _noteCtrl.addListener(() {
      if (_noteCtrl.text != _note) {
        setState(() => _note = _noteCtrl.text);
      }
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    // v1.7.0: 选分类时, 显示该分类的标签 (按 use_count 排序)
    // 没选分类时, 显示全局最近标签
    try {
      if (_selected != null) {
        final ts = await TagService.instance.byCategory(_selected!.id, limit: 8);
        if (!mounted) return;
        setState(() => _tags = ts);
      } else {
        final ts = await TagService.instance.recent(5);
        if (!mounted) return;
        setState(() => _tags = ts);
      }
    } catch (_) {
      // v1.7.0: 测试 tearDown 时 DB 已关, 静默忽略
    }
  }

  Future<void> _loadForEdit(String id) async {
    final tx = await TxRepository.instance.byId(id);
    if (tx == null) return;
    setState(() {
      _type = tx.type;
      _amount = toYuanString(tx.amountCents);
      _note = tx.note;
      _noteCtrl.text = tx.note;
      _noteCtrl.selection = TextSelection.collapsed(offset: tx.note.length);
      _date = DateTime.fromMillisecondsSinceEpoch(tx.epochDay * 86400000);
    });
    final cat = await CategoryRepository.instance.byId(tx.categoryId);
    if (cat != null) setState(() => _selected = cat);
    _loadTags();
  }

  /// = 按钮 触发: 实时求值 (U2) + 写库 (改动3 合并保存) + 跳回首页
  Future<void> _onEqualsAndSave() async {
    // 1. 求值
    final cents = evalCents(_amount);
    if (cents == 0) {
      _toast('请输入金额');
      return;
    }
    if (_selected == null) {
      _toast('请选择分类');
      return;
    }
    setState(() => _amount = toYuanString(cents));

    // 2. 写库
    final epochDay = DateTime.utc(_date.year, _date.month, _date.day)
        .millisecondsSinceEpoch ~/
        86400000;
    final repo = TxRepository.instance;
    if (widget.editTxId != null) {
      final cur = await repo.byId(widget.editTxId!);
      if (cur == null) return;
      final updated = cur.copyWith(
        epochDay: epochDay,
        type: _type,
        categoryId: _selected!.id,
        amountCents: cents,
        note: _note,
      );
      await repo.update(updated);
      // v1.8.0: 编辑后同步标签关联
      await TagService.instance.syncForTx(updated);
    } else {
      final tx = Tx(
        id: const Uuid().v4(),
        epochDay: epochDay,
        type: _type,
        categoryId: _selected!.id,
        amountCents: cents,
        note: _note,
        createdAt: DateTime.now(),
      );
      await repo.insert(tx);
      // v1.8.0: 保存后同步标签关联 (备注整体 bump + 命中标签建 tx_tag)
      if (_note.trim().isNotEmpty) {
        await TagService.instance.syncForTx(tx);
      }
    }
    if (!mounted) return;
    widget.onNavigate(0); // 跳回首页 (改动 3: = = 保存 + 跳走)
  }

  Future<void> _pickDate() async {
    // v1.8.1: 用自定义日期对话框 (双击某天 = 确定)
    final d = await showAppDatePicker(
      context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  /// (旧版: 打开全部分类选择, U1.5 已改为左右分栏, 此方法不再使用)
  Future<void> _openAllCategories(BuildContext context) async {
    // 保留 stub 以防外层调用, 不实际操作
    return;
  }

  /* (旧实现, 已废弃, 保留作参考)
    final all = await CategoryRepository.instance.byType(_type);
    if (!mounted) return;
    final selected = await showModalBottomSheet<Category>(
      context: context,
      builder: (c) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cat in all)
                  ActionChip(
                    label: Text(cat.name),
                    onPressed: () => Navigator.pop(c, cat),
                    backgroundColor:
                        _selected?.id == cat.id ? L.brandYellow : L.surface,
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) setState(() => _selected = selected);
  }
  */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      body: SafeArea(
        child: Column(
          children: [
            // 1. 顶部条 (极简, 只保留 × + 标题)
            _MiniHeader(
              title: widget.editTxId == null ? '记一笔' : '编辑',
              onClose: () => widget.onNavigate(0),
            ),
            // 2. 类型 chips + 日期 (1 行, v1.9.0: 金额移到键盘顶部)
            _TypeAndDateRow(
              type: _type,
              date: _date,
              onType: (t) => setState(() => _type = t),
              onPickDate: _pickDate,
            ),
            // 3. 模块一: 分类区 (v1.9.0: Expanded flex 2, 占约 2/3 剩余空间)
            //    5×N 网格可滚动, 包含 14 网格 + 4 常用
            Expanded(
              flex: 2,
              child: _Module1CategoriesAndNote(
                type: _type,
                selected: _selected,
                onSelect: (c) {
                  setState(() => _selected = c);
                  _loadTags(); // v1.7.0: 选分类后刷新标签
                },
              ),
            ),
            // 3.5 标签行 (v1.9.0: 增强显示 — 更大字号 + 彩色 chip 背景)
            _TagRow(
              tags: _tags,
              onTap: (name) {
                // 点标签: 追加到备注 (空格衔接; _note 由 controller listener 同步)
                final cur = _noteCtrl.text.trim();
                _noteCtrl.text = cur.isEmpty ? name : '$cur $name';
              },
            ),
            // 4. 备注 (1 行, 30px)
            EntryShortNote(
              controller: _noteCtrl,
              onAddTag: () async {
                final t = _note.trim();
                if (t.isEmpty) {
                  _toast('请先在备注里输入标签名');
                  return;
                }
                await TagService.instance.addOrBump(t);
                _toast('已添加标签: $t');
                _loadTags();
              },
            ),
            // 5. 模块二: 数字键盘 4×4 (v1.9.0: 固定高度 ~1/3 屏, 顶部含大字金额显示屏)
            //    金额显示屏替代原来 _TypeAndDateRow 里的金额预览
            //    用 Expanded(flex: 1) 让键盘占剩余约 1/3
            Expanded(
              flex: 1,
              child: EntryKeypad(
                amount: _amount,
                onChange: (s) {
                  // U2: 实时求值预览
                  setState(() {
                    _amount = s;
                  });
                },
                onDelete: () => setState(() {
                  if (_amount.length <= 1) {
                    _amount = '0';
                  } else {
                    _amount = _amount.substring(0, _amount.length - 1);
                    if (_amount.isEmpty) _amount = '0';
                  }
                }),
                onEqualsAndSave: _onEqualsAndSave,
                onLongPressMic: widget.editTxId == null ? _onMic : null,
                showSaveButton: widget.editTxId != null,
                onSave: widget.editTxId != null ? _onEqualsAndSave : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onMic() async {
    String text;
    try {
      final ok = await VoiceService.ensurePermission();
      if (!ok) {
        _toast('需要麦克风权限');
        return;
      }
      final avail = await VoiceService.isAvailable();
      if (!avail) {
        _toast('当前设备不支持语音识别');
        return;
      }
      _toast('🎤 录音中...');
      text = await VoiceService.listen(locale: 'zh-CN');
    } catch (e) {
      _toast('识别失败');
      return;
    }
    if (text.isEmpty) {
      _toast('没听清');
      return;
    }
    final parsed = await NluService.parse(text);
    if (parsed.amount != null) {
      setState(() => _amount = toYuanString((parsed.amount! * 100).round()));
    }
    if (parsed.date != null) {
      setState(() => _date = parsed.date!);
    }
    if (parsed.categoryId != null) {
      final cat = await CategoryRepository.instance.byId(parsed.categoryId!);
      if (cat != null && mounted) {
        setState(() {
          _selected = cat;
          _type = cat.type;
        });
      }
    }
    if (parsed.note != null) {
      setState(() {
        _note = parsed.note!;
        _noteCtrl.text = _note;
        _noteCtrl.selection = TextSelection.collapsed(offset: _note.length);
      });
    } else if (parsed.rawText != null) {
      setState(() {
        _note = parsed.rawText!;
        _noteCtrl.text = _note;
        _noteCtrl.selection = TextSelection.collapsed(offset: _note.length);
      });
    }
  }

  void _toast(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }
}

/// 极简顶部: 只 × + 标题
class _MiniHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  const _MiniHeader({required this.title, required this.onClose});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.surface,
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close, color: L.textPrimary),
          ),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: L.textPrimary)),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// 日期 (左 chip) + 类型 chips (v1.9.0: 金额移到键盘顶部, 此行不再显示金额)
class _TypeAndDateRow extends StatelessWidget {
  final TxType type;
  final DateTime date;
  final ValueChanged<TxType> onType;
  final VoidCallback onPickDate;
  const _TypeAndDateRow({
    required this.type,
    required this.date,
    required this.onType,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.surface,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          // 支出/收入 chips
          _TypeChip(
              label: '支出',
              selected: type == TxType.expense,
              onTap: () => onType(TxType.expense)),
          const SizedBox(width: 16),
          _TypeChip(
              label: '收入',
              selected: type == TxType.income,
              onTap: () => onType(TxType.income)),
          const Spacer(),
          // 日期 chip
          InkWell(
            onTap: onPickDate,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: L.dividerLight),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 12, color: L.textSecondary),
                  const SizedBox(width: 4),
                  Text(_fmtDate(date),
                      style: const TextStyle(
                          fontSize: 12, color: L.textPrimary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 单个 type chip (支出 / 收入)
class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? L.textPrimary : L.textTertiary,
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 6),
            Container(
              width: 14,
              height: 2,
              color: L.brandYellow,
            ),
          ],
        ],
      ),
    );
  }
}

/// 标签行 (v1.9.0: 增强显示 — 更高 + 彩色 chip 背景 + 更大字号)
/// v1.7.0: 按 use_count 排序, 末尾加"全部"入口
class _TagRow extends StatelessWidget {
  final List<Tag> tags;
  final ValueChanged<String> onTap;
  const _TagRow({required this.tags, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.surface,
      height: 40, // v1.9.0: 32 → 40 增高
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      // v1.9.0: 用 SingleChildScrollView 替代 ListView (构建所有子项, 避免
      //         "全部" 入口在测试/小屏下因 lazy build 不出现在 widget tree)
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
          for (final t in tags) ...[
            Container(
              margin: const EdgeInsets.only(right: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onTap(t.name),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      // v1.9.0: 彩色 chip 背景 (品牌黄浅底)
                      color: L.brandYellowTrack,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: L.brandYellow.withValues(alpha: 0.3),
                          width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_offer,
                            size: 13, color: L.brandYellow),
                        const SizedBox(width: 4),
                        Text(t.name,
                            style: const TextStyle(
                                fontSize: 13, // v1.9.0: 12 → 13 增大
                                fontWeight: FontWeight.w600,
                                color: L.textPrimary)),
                        if (t.useCount >= 3) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: L.brandYellow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('×${t.useCount}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: L.textPrimary)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          // 末尾 "全部标签" 入口 (v1.7.0 U1.9)
          Container(
            margin: const EdgeInsets.only(right: 6),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TagManagerPage(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: L.dividerLight, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('全部',
                          style: TextStyle(
                              fontSize: 13,
                              color: L.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Icon(Icons.chevron_right, size: 16, color: L.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// 模块一: 选择类型 (v1.6.3 重新分配比例 ≤ 1/5 屏)
/// 高度 234px (1080×2340 ÷ 5 = 468 ÷ 2 ≈ 234), 内含 14 网格 + 4 常用
/// 标签 (1 行) + 备注 (1 行) 独立放在模块一外
class _Module1CategoriesAndNote extends StatelessWidget {
  final TxType type;
  final Category? selected;
  final ValueChanged<Category> onSelect;
  const _Module1CategoriesAndNote({
    required this.type,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.surface,
      child: EntrySplitCategories(
        type: type,
        selected: selected,
        onSelect: onSelect,
      ),
    );
  }
}
