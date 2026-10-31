/// 备注短行 (v1.6.0 U1)
/// 极简: 单行输入 + 标签创建 + 右侧 +
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class EntryShortNote extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onAddTag;
  const EntryShortNote({
    super.key,
    required this.controller,
    required this.onAddTag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.surface,
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          const Icon(Icons.notes, size: 14, color: L.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '备注 (输入后点 + 可保存为标签)',
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                hintStyle: TextStyle(fontSize: 12, color: L.textTertiary),
              ),
              style: const TextStyle(fontSize: 13, color: L.textPrimary),
              maxLines: 1,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onAddTag,
            icon: const Icon(Icons.add_circle_outline,
                size: 20, color: L.textSecondary),
          ),
        ],
      ),
    );
  }
}
