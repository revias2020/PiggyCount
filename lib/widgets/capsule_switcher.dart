import 'package:flutter/material.dart';

import '../styles/tokens.dart';

/// 胶囊选项。
class CapsuleOption<T> {
  const CapsuleOption({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

/// 精简胶囊切换条（气质对齐 BeeCount，选中用品牌主色）。
class CapsuleSwitcher<T> extends StatelessWidget {
  const CapsuleSwitcher({
    super.key,
    required this.selectedValue,
    required this.options,
    required this.onChanged,
    this.height = 40,
  });

  final T selectedValue;
  final List<CapsuleOption<T>> options;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);

    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: PigTokens.surfaceSecondary,
        borderRadius: radius,
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _segment(options[i])),
          ],
        ],
      ),
    );
  }

  Widget _segment(CapsuleOption<T> option) {
    final selected = selectedValue == option.value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(option.value),
        borderRadius: BorderRadius.circular((height - 6) / 2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: height - 6,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? PigTokens.primary : Colors.transparent,
            borderRadius: BorderRadius.circular((height - 6) / 2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? PigTokens.textOnPrimary : PigTokens.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
