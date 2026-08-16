import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/statistics_repository.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import 'report_section_card.dart';

/// 近若干周期横向柱状对比；当前周期用主色高亮。
class ReportCompareChart extends StatelessWidget {
  const ReportCompareChart({
    super.key,
    required this.title,
    required this.points,
    required this.highlightStart,
  });

  final String title;
  final List<SeriesPoint> points;

  /// 与 [SeriesPoint.bucketStart] 对齐时高亮。
  final DateTime highlightStart;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    final maxY =
        points.map((e) => e.value).fold<double>(0, (a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 100.0 : maxY * 1.2;

    return ReportSectionCard(
      title: title,
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            maxY: chartMax,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xEE1F2937),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final p = points[group.x.toInt()];
                  return BarTooltipItem(
                    '${p.label}\n¥${formatMoney(p.value)}',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= points.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        points[i].label,
                        style: const TextStyle(
                          fontSize: 10,
                          color: PigTokens.textTertiary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: [
              for (var i = 0; i < points.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: points[i].value <= 0 ? 0.01 : points[i].value,
                      width: 22,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                      color: _isHighlight(points[i].bucketStart)
                          ? PigTokens.primary
                          : PigTokens.primary.withValues(alpha: 0.35),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isHighlight(DateTime bucket) {
    return bucket.year == highlightStart.year &&
        bucket.month == highlightStart.month &&
        bucket.day == highlightStart.day;
  }
}
