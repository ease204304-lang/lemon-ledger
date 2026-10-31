/// 搜索页 (v1.1)
///
/// 按备注/分类名 模糊匹配, 列出全部命中的流水
library search_page;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../theme/tokens.dart';
import '../widgets/category_icon.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  String _keyword = '';
  List<Tx> _results = const [];
  bool _loading = false;
  Map<String, Category> _cats = {};

  @override
  void initState() {
    super.initState();
    _loadCats();
    _search('');
  }

  Future<void> _loadCats() async {
    final cats = await CategoryRepository.instance.all();
    if (mounted) setState(() => _cats = {for (final c in cats) c.id: c});
  }

  Future<void> _search(String k) async {
    setState(() {
      _keyword = k;
      _loading = true;
    });
    final txs = await TxRepository.instance.search(k);
    if (!mounted) return;
    setState(() {
      _results = txs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      appBar: AppBar(
        backgroundColor: L.surface,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: L.textPrimary),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索备注或分类',
            border: InputBorder.none,
            suffixIcon: _keyword.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _controller.clear();
                      _search('');
                    },
                    icon: const Icon(Icons.cancel, size: 18, color: L.textTertiary),
                  ),
          ),
          style: const TextStyle(fontSize: 16, color: L.textPrimary),
          onChanged: (v) {
            if (v.isEmpty) _search('');
          },
          onSubmitted: _search,
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: Text('搜索',
                  style: TextStyle(color: L.textTertiary, fontSize: 14)),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_keyword.isEmpty) {
      return _emptyHint('输入备注或分类名称', Icons.search);
    }
    if (_results.isEmpty) {
      return _emptyHint('没有匹配的记录', Icons.sentiment_dissatisfied);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(L.pageH, 8, L.pageH, 16),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final t = _results[i];
        final cat = _cats[t.categoryId];
        final dt = DateTime.fromMillisecondsSinceEpoch(t.epochDay * 86400000);
        return InkWell(
          borderRadius: BorderRadius.circular(L.cardR),
          onTap: () => Navigator.of(context).pop<Tx>(t),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            decoration: BoxDecoration(
              color: L.surface,
              borderRadius: BorderRadius.circular(L.cardR),
            ),
            child: Row(
              children: [
                CategoryIcon(iconKey: cat?.iconKey ?? 'else'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.note.isNotEmpty ? t.note : (cat?.name ?? '未分类'),
                        style: const TextStyle(
                            fontSize: 15, color: L.textPrimary, fontWeight: FontWeight.w500),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${DateFormat('MM-dd').format(dt)} · ${cat?.name ?? ''}',
                        style: const TextStyle(fontSize: 12, color: L.textTertiary),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${t.type == TxType.income ? '+' : '-'}${(t.amountCents / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: L.textPrimary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyHint(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: L.textDisabled),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: L.textTertiary, fontSize: 14)),
        ],
      ),
    );
  }
}
