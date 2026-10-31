/// 标签管理页 (v1.7.0 U1.9)
/// 用户点开单一类别 → 看到该类别下方的标签 (按使用频次排序)
/// 可点击标签进入详情, 或长按删除, 或 + 添加
library;

import 'package:flutter/material.dart';

import '../data/tag_service.dart';
import '../theme/tokens.dart';

class TagManagerPage extends StatefulWidget {
  /// 可选: 如果指定 categoryName, 则显示"该分类的标签"; 否则显示全部
  final String? categoryName;
  final String? categoryId;

  const TagManagerPage({super.key, this.categoryName, this.categoryId});

  @override
  State<TagManagerPage> createState() => _TagManagerPageState();
}

class _TagManagerPageState extends State<TagManagerPage> {
  List<Tag> _tags = const [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final query = _searchCtrl.text.trim();
    List<Tag> ts;
    try {
      if (query.isEmpty) {
        if (widget.categoryId != null) {
          ts = await TagService.instance
              .byCategory(widget.categoryId!, limit: 50);
        } else {
          ts = await TagService.instance.recent(50);
        }
      } else {
        ts = await TagService.instance.search(query, limit: 50);
      }
    } catch (_) {
      // DB 已关闭 (测试 tearDown 竞态) — 保持空列表即可
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _tags = ts;
      _loading = false;
    });
  }

  Future<void> _addNew() async {
    final name = await showDialog<String>(
      context: context,
      builder: (c) {
        final ctl = TextEditingController();
        return AlertDialog(
          title: const Text('新建标签'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入标签名 (如 周黑鸭, 奶茶, 通勤...)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, ctl.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    await TagService.instance.addOrBump(name);
    await _load();
  }

  Future<void> _deleteTag(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定删除 "$name" 吗?\n(只删除标签本身, 已记的流水不受影响)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TagService.instance.remove(name);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      appBar: AppBar(
        title: Text(widget.categoryName == null
            ? '所有标签'
            : '${widget.categoryName} · 标签'),
        actions: [
          IconButton(
            onPressed: _addNew,
            icon: const Icon(Icons.add),
            tooltip: '新建标签',
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索标签 (按使用频次排序)',
                isDense: true,
                filled: true,
                fillColor: L.surface,
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _load();
                        },
                      ),
              ),
              onSubmitted: (_) => _load(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // 标签云 (Wrap)
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tags.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            '暂无标签\n记一笔时输入备注, 自动创建标签',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: L.textTertiary),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final t in _tags)
                              _TagChip(
                                name: t.name,
                                useCount: t.useCount,
                                onLongPress: () => _deleteTag(t.name),
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// 单个标签 chip (按 use_count 显示不同大小 = 使用频次)
class _TagChip extends StatelessWidget {
  final String name;
  final int useCount;
  final VoidCallback onLongPress;
  const _TagChip({
    required this.name,
    required this.useCount,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // 使用频次决定大小 (1-2 小, 3-5 中, 6+ 大)
    final isHot = useCount >= 5;
    final isMid = useCount >= 3;
    final color = isHot
        ? L.brandYellow
        : (isMid ? L.brandYellowTrack : L.surface);
    final textColor = isHot ? L.textPrimary : L.textBody;
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('标签 "$name" 已用过 $useCount 次')),
        );
      },
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: L.brandYellow.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                color: textColor,
                fontWeight: isHot ? FontWeight.w700 : FontWeight.w500,
                fontSize: isHot ? 15 : (isMid ? 14 : 13),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$useCount',
              style: TextStyle(
                color: textColor.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
