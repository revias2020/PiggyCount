import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/statistics_repository.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../../utils/report_period.dart';
import 'report_section_card.dart';

/// 支出/收入趋势：面积折线图 + 触点 tooltip。
class ReportTrendChart extends StatefulWidget {
  const ReportTrendChart({
    super.key,
    required this.title,
    required this.points,
    required this.moneyType,
  });

  final String title;
  final List<SeriesPoint> points;
  final ReportMoneyType moneyType;

  @override
  State<ReportTrendChart> createState() => _ReportTrendChartState();
}

class _ReportTrendChartState extends State<ReportTrendChart> {
  int? _touched;

  @override
  void didUpdateWidget(covariant ReportTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) {
      _touched = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) return const SizedBox.shrink();

    final maxY =
        points.map((e) => e.value).fold<double>(0, (a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 100.0 : maxY * 1.15;

    final labelStep = points.length > 14
        ? (points.length / 7).ceil()
        : (points.length > 8 ? 2 : 1);

    final maxX = points.length <= 1 ? 1.0 : (points.length - 1).toDouble();

    return ReportSectionCard(
      title: widget.title,
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: maxX,
            minY: 0,
            maxY: chartMax,
            lineTouchData: LineTouchData(
              handleBuiltInTouches: true,
              touchCallback: (event, response) {
                if (!event.isInterestedForInteractions ||
                    response?.lineBarSpots == null ||
                    response!.lineBarSpots!.isEmpty) {
                  setState(() => _touched = null);
                  return;
                }
                setState(
                  () => _touched = response.lineBarSpots!.first.x.toInt(),
                );
              },
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => const Color(0xEE1F2937),
                tooltipBorderRadius: BorderRadius.circular(8),
                getTooltipItems: (spots) {
                  return spots.map((s) {
                    final i = s.x.toInt().clamp(0, points.length - 1);
                    final p = points[i];
                    final kind = widget.moneyType == ReportMoneyType.expense
                        ? '支出'
                        : '收入';
                    return LineTooltipItem(
                      '${p.label} $kind ¥${formatMoney(p.value)}',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: chartMax / 4,
              getDrawingHorizontalLine: (_) => const FlLine(
                color: PigTokens.scaffoldBackground,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: chartMax / 4,
                  getTitlesWidget: (v, _) {
                    if (v <= 0 || v >= chartMax) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      _compactYen(v),
                      style: const TextStyle(
                        fontSize: 10,
                        color: PigTokens.textTertiary,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= points.length) {
                      return const SizedBox.shrink();
                    }
                    if (i % labelStep != 0 && i != points.length - 1) {
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
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < points.length; i++)
                    FlSpot(i.toDouble(), points[i].value),
                ],
                isCurved: true,
                curveSmoothness: 0.2,
                color: PigTokens.primary,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  checkToShowDot: (spot, _) =>
                      _touched != null && spot.x.toInt() == _touched,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                    radius: 4,
                    color: PigTokens.primary,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      PigTokens.primary.withValues(alpha: 0.28),
                      PigTokens.primary.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _compactYen(double v) {
    if (v >= 10000) return '¥${(v / 10000).toStringAsFixed(1)}万';
    if (v >= 1000) return '¥${(v / 1000).toStringAsFixed(1)}k';
    return '¥${v.toStringAsFixed(0)}';
  }
}
