/// 记账页备注栏: 输入框 + "+" 保存为标签按钮
library;

import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class EntryNoteBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onAddTag;
  const EntryNoteBar({
    super.key,
    required this.controller,
    required this.onAddTag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.surface,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.edit_note, color: L.textTertiary, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '备注 (输入后点 + 可保存为标签)',
                isDense: true,
                border: InputBorder.none,
                hintStyle: TextStyle(color: L.textTertiary, fontSize: 14),
              ),
              style: const TextStyle(color: L.textPrimary, fontSize: 14),
            ),
          ),
          IconButton(
            onPressed: onAddTag,
            icon: const Icon(Icons.add_circle_outline, color: L.brandYellow),
            tooltip: '保存为标签',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
