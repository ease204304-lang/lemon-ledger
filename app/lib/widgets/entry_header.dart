/// 记账页顶部条 (× 关闭 / 标题 / 语音 / 删除)
library;

import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class EntryHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onDelete;
  final VoidCallback? onMic;
  const EntryHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.onDelete,
    this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.surface,
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: L.textPrimary),
          ),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: L.textPrimary)),
          ),
          if (onMic != null)
            IconButton(
              onPressed: onMic,
              icon: const Icon(Icons.mic_none, color: L.textPrimary),
              tooltip: '语音记账',
            ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: L.warnRed),
              tooltip: '删除',
            )
          else if (onMic == null)
            const SizedBox(width: 48), // 占位
        ],
      ),
    );
  }
}
