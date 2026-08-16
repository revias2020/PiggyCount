import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 年月网格选择底部弹层；返回选中月的 1 号，取消返回 null。
Future<DateTime?> showYearMonthGridSheet(
  BuildContext context, {
  required DateTime initialMonth,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PigTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PigTokens.radiusSheet),
      ),
    ),
    builder: (_) => _YearMonthGridSheet(initialMonth: initialMonth),
  );
}

class _YearMonthGridSheet extends StatefulWidget {
  const _YearMonthGridSheet({required this.initialMonth});

  final DateTime initialMonth;

  @override
  State<_YearMonthGridSheet> createState() => _YearMonthGridSheetState();
}

class _YearMonthGridSheetState extends State<_YearMonthGridSheet> {
  late int _year;
  late int _month;

  static const _yearsBack = 8;
  static const _yearsForward = 2;

  @override
  void initState() {
    super.initState();
    _year = widget.initialMonth.year;
    _month = widget.initialMonth.month;
  }

  List<int> get _years {
    final now = DateTime.now().year;
    return [
      for (var y = now - _yearsBack; y <= now + _yearsForward; y++) y,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: PigTokens.spaceLg,
        right: PigTokens.spaceLg,
        top: PigTokens.spaceMd,
        bottom: MediaQuery.paddingOf(context).bottom + PigTokens.spaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: PigTokens.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: PigTokens.spaceLg),
          const Text(
            '选择月份',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: PigTokens.textPrimary,
            ),
          ),
          const SizedBox(height: PigTokens.spaceMd),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _years.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: PigTokens.spaceSm),
              itemBuilder: (context, index) {
                final y = _years[index];
                final selected = y == _year;
                return ChoiceChip(
                  label: Text('$y'),
                  selected: selected,
                  onSelected: (_) => setState(() => _year = y),
                  selectedColor: PigTokens.primarySoft,
                  labelStyle: TextStyle(
                    color: selected ? PigTokens.primary : PigTokens.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  side: BorderSide(
                    color: selected ? PigTokens.primary : PigTokens.surfaceInput,
                  ),
                  backgroundColor: PigTokens.surfaceInput,
                  showCheckmark: false,
                );
              },
            ),
          ),
          const SizedBox(height: PigTokens.spaceLg),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 12,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: PigTokens.spaceSm,
              crossAxisSpacing: PigTokens.spaceSm,
              childAspectRatio: 1.6,
            ),
            itemBuilder: (context, index) {
              final m = index + 1;
              final selected = m == _month;
              return Material(
                color: selected ? PigTokens.primary : PigTokens.surfaceInput,
                borderRadius: BorderRadius.circular(PigTokens.radiusCard),
                child: InkWell(
                  borderRadius: BorderRadius.circular(PigTokens.radiusCard),
                  onTap: () => setState(() => _month = m),
                  child: Center(
                    child: Text(
                      '$m月',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? PigTokens.textOnPrimary
                            : PigTokens.textPrimary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: PigTokens.spaceXl),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, DateTime(_year, _month)),
            style: FilledButton.styleFrom(
              backgroundColor: PigTokens.primary,
              foregroundColor: PigTokens.textOnPrimary,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PigTokens.radiusCard),
              ),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
