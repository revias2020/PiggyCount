import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/statistics_repository.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../../utils/report_period.dart';
import 'report_section_card.dart';

/// 支出/收入趋势：紧凑面积折线；气泡/虚线常驻；零值断线（ADR-033）。
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
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = _defaultIndex(widget.points);
  }

  @override
  void didUpdateWidget(covariant ReportTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) {
      _selected = _defaultIndex(widget.points);
    }
  }

  /// 有数据的最后一天；全无数据则钉末桶。
  int _defaultIndex(List<SeriesPoint> points) {
    if (points.isEmpty) return 0;
    for (var i = points.length - 1; i >= 0; i--) {
      if (points[i].value > 0) return i;
    }
    return points.length - 1;
  }

  List<List<FlSpot>> _segments(List<SeriesPoint> points) {
    final segments = <List<FlSpot>>[];
    var current = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      if (points[i].value > 0) {
        current.add(FlSpot(i.toDouble(), points[i].value));
      } else if (current.isNotEmpty) {
        segments.add(current);
        current = [];
      }
    }
    if (current.isNotEmpty) segments.add(current);
    return segments;
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
    final kind =
        widget.moneyType == ReportMoneyType.expense ? '支出' : '收入';

    final segments = _segments(points);
    final lineBars = <LineChartBarData>[
      for (final seg in segments)
        LineChartBarData(
          spots: seg.length == 1
              ? [seg.first, FlSpot(seg.first.x + 0.001, seg.first.y)]
              : seg,
          isCurved: true,
          curveSmoothness: 0.2,
          color: PigTokens.primary,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, _) => spot.x.round() == _selected,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
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
    ];

    // 无正值时画一条透明轨，方便轴与触控占位。
    if (lineBars.isEmpty) {
      lineBars.add(
        LineChartBarData(
          spots: [
            const FlSpot(0, 0),
            FlSpot(maxX, 0),
          ],
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    ShowingTooltipIndicators? stickyTooltip;
    for (var bi = 0; bi < lineBars.length; bi++) {
      final bar = lineBars[bi];
      for (final spot in bar.spots) {
        if (spot.x.round() == _selected) {
          stickyTooltip = ShowingTooltipIndicators([
            LineBarSpot(bar, bi, spot),
          ]);
          break;
        }
      }
      if (stickyTooltip != null) break;
    }

    return ReportSectionCard(
      title: widget.title,
      child: Padding(
        padding: const EdgeInsets.only(top: 30),
        child: SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: 0,
              maxY: chartMax,
              showingTooltipIndicators:
                  stickyTooltip == null ? const [] : [stickyTooltip],
              lineTouchData: LineTouchData(
                handleBuiltInTouches: false,
                getTouchedSpotIndicator: (bar, spotIndexes) {
                  return spotIndexes.map((i) {
                    return TouchedSpotIndicatorData(
                      FlLine(
                        color: PigTokens.primary.withValues(alpha: 0.55),
                        strokeWidth: 1.5,
                        dashArray: const [4, 3],
                      ),
                      FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: PigTokens.primary,
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        ),
                      ),
                    );
                  }).toList();
                },
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions) return;
                  final spots = response?.lineBarSpots;
                  if (spots == null || spots.isEmpty) return;
                  final x = spots.first.x.round().clamp(0, points.length - 1);
                  if (points[x].value <= 0) return;
                  setState(() => _selected = x);
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => PigTokens.primary,
                  tooltipBorderRadius: BorderRadius.circular(6),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  getTooltipItems: (spots) {
                    return spots.map((s) {
                      final i = s.x.toInt().clamp(0, points.length - 1);
                      final p = points[i];
                      return LineTooltipItem(
                        '${p.label} $kind\n¥${formatMoney(p.value)}',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              extraLinesData: ExtraLinesData(
                verticalLines: [
                  VerticalLine(
                    x: _selected.toDouble(),
                    color: PigTokens.primary.withValues(alpha: 0.55),
                    strokeWidth: 1.5,
                    dashArray: [4, 3],
                  ),
                ],
              ),
              gridData: FlGridData(
                show: true,
                drawHorizontalLine: false,
                drawVerticalLine: true,
                verticalInterval: labelStep.toDouble(),
                getDrawingVerticalLine: (_) => const FlLine(
                  color: Color(0xFFE5E7EB),
                  strokeWidth: 1,
                ),
                checkToShowVerticalLine: (v) {
                  final i = v.round();
                  if (i < 0 || i >= points.length) return false;
                  return i % labelStep == 0 || i == points.length - 1;
                },
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
              lineBarsData: lineBars,
            ),
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
