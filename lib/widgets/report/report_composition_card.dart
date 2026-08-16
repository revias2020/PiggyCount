import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/statistics_repository.dart';
import '../../styles/tokens.dart';
import '../../utils/category_icons.dart';
import '../../utils/money_format.dart';
import '../../utils/report_period.dart';
import 'report_section_card.dart';

/// 构成图调色板（蓝系为主，区分扇区）。
const _kPieColors = <Color>[
  Color(0xFF2F6BFF),
  Color(0xFF5B8FF9),
  Color(0xFF6DC8EC),
  Color(0xFF5AD8A6),
  Color(0xFFF6BD16),
  Color(0xFFFF9845),
  Color(0xFFE86452),
  Color(0xFF945FB9),
  Color(0xFFFF99C3),
  Color(0xFF1E9493),
];

/// 分类/标签构成：环形图 + 列表；维度切换主分类 / 子分类 / 标签。
class ReportCompositionCard extends StatefulWidget {
  const ReportCompositionCard({
    super.key,
    required this.title,
    required this.slices,
    required this.total,
    required this.dim,
    required this.onDimChanged,
    required this.moneyType,
  });

  final String title;
  final List<CompositionSlice> slices;
  final double total;
  final CompositionDim dim;
  final ValueChanged<CompositionDim> onDimChanged;
  final ReportMoneyType moneyType;

  @override
  State<ReportCompositionCard> createState() => _ReportCompositionCardState();
}

class _ReportCompositionCardState extends State<ReportCompositionCard> {
  int _touched = -1;
  bool _expanded = false;

  static const _previewCount = 6;

  @override
  void didUpdateWidget(covariant ReportCompositionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slices != widget.slices) {
      _touched = -1;
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final slices = widget.slices.where((s) => s.total > 0).toList();
    final visible =
        _expanded ? slices : slices.take(_previewCount).toList();

    return ReportSectionCard(
      title: widget.title,
      trailing: _DimSwitcher(
        dim: widget.dim,
        onChanged: widget.onDimChanged,
      ),
      child: slices.isEmpty || widget.total <= 0
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂无构成数据',
                  style: TextStyle(color: PigTokens.textTertiary),
                ),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 52,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              if (!event.isInterestedForInteractions ||
                                  response?.touchedSection == null) {
                                setState(() => _touched = -1);
                                return;
                              }
                              setState(() {
                                _touched = response!
                                    .touchedSection!.touchedSectionIndex;
                              });
                            },
                          ),
                          sections: [
                            for (var i = 0; i < slices.length; i++)
                              PieChartSectionData(
                                color: _kPieColors[i % _kPieColors.length],
                                value: slices[i].total,
                                title: '',
                                radius: _touched == i ? 58 : 48,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatMoney(
                              _touched >= 0 && _touched < slices.length
                                  ? slices[_touched].total
                                  : widget.total,
                            ),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _touched >= 0 && _touched < slices.length
                                ? slices[_touched].name
                                : '元',
                            style: const TextStyle(
                              fontSize: 12,
                              color: PigTokens.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PigTokens.spaceSm),
                for (var i = 0; i < visible.length; i++)
                  _SliceRow(
                    slice: visible[i],
                    color: _kPieColors[i % _kPieColors.length],
                    total: widget.total,
                    asExpense: widget.moneyType == ReportMoneyType.expense,
                    showIcon: widget.dim != CompositionDim.tag,
                  ),
                if (slices.length > _previewCount)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? '收起' : '查看更多'),
                  ),
              ],
            ),
    );
  }
}

class _DimSwitcher extends StatelessWidget {
  const _DimSwitcher({required this.dim, required this.onChanged});

  final CompositionDim dim;
  final ValueChanged<CompositionDim> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, CompositionDim value) {
      final selected = dim == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: PigTokens.spaceSm,
            vertical: PigTokens.spaceXs,
          ),
          decoration: BoxDecoration(
            color: selected ? PigTokens.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(PigTokens.spaceSm - 2),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? PigTokens.primary : PigTokens.textSecondary,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('主分类', CompositionDim.mainCategory),
        chip('子分类', CompositionDim.subCategory),
        chip('标签', CompositionDim.tag),
      ],
    );
  }
}

class _SliceRow extends StatelessWidget {
  const _SliceRow({
    required this.slice,
    required this.color,
    required this.total,
    required this.asExpense,
    required this.showIcon,
  });

  final CompositionSlice slice;
  final Color color;
  final double total;
  final bool asExpense;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0.0 : slice.total / total * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PigTokens.spaceSm),
      child: Row(
        children: [
          if (showIcon)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                categoryIconData(slice.icon),
                size: 20,
                color: color,
              ),
            )
          else
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slice.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 11,
                    color: PigTokens.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatSignedMoney(slice.total, asExpense: asExpense),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
