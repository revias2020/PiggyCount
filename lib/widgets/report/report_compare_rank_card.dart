import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/statistics_repository.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../../utils/report_period.dart';
import 'report_rank_tile.dart';
import 'report_section_card.dart';

/// 对比柱 + 单笔排行 Top10 +「全部排行 >」（ADR-033）。
class ReportCompareRankCard extends StatelessWidget {
  const ReportCompareRankCard({
    super.key,
    required this.compareTitle,
    required this.rankTitle,
    required this.comparePoints,
    required this.highlightStart,
    required this.rankItems,
    required this.moneyType,
    required this.onRankTap,
    required this.onViewAll,
  });

  final String compareTitle;
  final String rankTitle;
  final List<SeriesPoint> comparePoints;
  final DateTime highlightStart;
  final List<RankedTransaction> rankItems;
  final ReportMoneyType moneyType;
  final ValueChanged<RankedTransaction> onRankTap;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final showCompare = comparePoints.isNotEmpty;

    return ReportSectionCard(
      title: showCompare ? compareTitle : rankTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showCompare) ...[
            _CompareBars(
              points: comparePoints,
              highlightStart: highlightStart,
            ),
            const SizedBox(height: PigTokens.spaceMd),
            const Divider(height: 1),
            const SizedBox(height: PigTokens.spaceMd),
            Text(
              rankTitle,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: PigTokens.spaceSm),
          ],
          if (rankItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '暂无排行数据',
                  style: TextStyle(color: PigTokens.textTertiary),
                ),
              ),
            )
          else ...[
            for (final item in rankItems)
              ReportRankTile.fromRanked(
                item: item,
                moneyType: moneyType,
                onTap: () => onRankTap(item),
              ),
            Center(
              child: TextButton(
                onPressed: onViewAll,
                child: const Text('全部排行'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompareBars extends StatelessWidget {
  const _CompareBars({
    required this.points,
    required this.highlightStart,
  });

  final List<SeriesPoint> points;
  final DateTime highlightStart;

  bool _isHighlight(DateTime bucket) {
    return bucket.year == highlightStart.year &&
        bucket.month == highlightStart.month &&
        bucket.day == highlightStart.day;
  }

  String _barLabel(double v, {required bool highlight}) {
    if (v <= 0) return '0.00';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
    return formatMoney(v);
  }

  @override
  Widget build(BuildContext context) {
    final maxY =
        points.map((e) => e.value).fold<double>(0, (a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 100.0 : maxY * 1.35;

    return SizedBox(
      height: 168,
      child: BarChart(
        BarChartData(
          maxY: chartMax,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            topTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) {
                    return const SizedBox.shrink();
                  }
                  final p = points[i];
                  final hi = _isHighlight(p.bucketStart);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _barLabel(p.value, highlight: hi),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: hi ? FontWeight.w700 : FontWeight.w500,
                        color: hi
                            ? PigTokens.primary
                            : PigTokens.textTertiary,
                      ),
                    ),
                  );
                },
              ),
            ),
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
                  final p = points[i];
                  final hi = _isHighlight(p.bucketStart);
                  final text = hi && RegExp(r'^\d+月$').hasMatch(p.label)
                      ? '本月'
                      : p.label;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: hi ? FontWeight.w700 : FontWeight.w500,
                        color: hi
                            ? PigTokens.textPrimary
                            : PigTokens.textTertiary,
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
                showingTooltipIndicators: const [],
              ),
          ],
        ),
      ),
    );
  }
}
