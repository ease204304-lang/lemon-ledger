/// 通用段控件（周/月/年）
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class Segment<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T current;
  final ValueChanged<T> onChanged;
  const Segment({
    super.key,
    required this.values,
    required this.labels,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: L.surfaceNote,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(values.length, (i) {
          final selected = values[i] == current;
          return GestureDetector(
            onTap: () => onChanged(values[i]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? L.segmentSelected : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? L.surface : L.textTertiary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
