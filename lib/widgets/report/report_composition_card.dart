import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/statistics_repository.dart';
import '../../styles/tokens.dart';
import '../../utils/category_icons.dart';
import '../../utils/money_format.dart';
import '../../utils/report_period.dart';
import '../../utils/report_route_observer.dart';
import '../../utils/tag_colors.dart';
import '../category_icon_view.dart';
import 'report_section_card.dart';

/// 构成环观赏色板（按金额排名，与分类 icon 色脱钩）。
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
  Color(0xFF63B2FF),
  Color(0xFFB37FEB),
];

/// 分类/标签构成：观赏色环 + 下划线式引出 Top8 + 分类图标列表（ADR-033 / ADR-037）。
class ReportCompositionCard extends StatefulWidget {
  const ReportCompositionCard({
    super.key,
    required this.title,
    required this.slices,
    required this.total,
    required this.dim,
    required this.onDimChanged,
    required this.moneyType,
    this.onSliceTap,
  });

  final String title;
  final List<CompositionSlice> slices;
  final double total;
  final CompositionDim dim;
  final ValueChanged<CompositionDim> onDimChanged;
  final ReportMoneyType moneyType;
  final ValueChanged<CompositionSlice>? onSliceTap;

  @override
  State<ReportCompositionCard> createState() => _ReportCompositionCardState();
}

class _ReportCompositionCardState extends State<ReportCompositionCard>
    with RouteAware {
  int _selected = -1;
  bool _expanded = false;
  bool _routeSubscribed = false;

  static const _previewCount = 5;
  static const _calloutTop = 8;
  /// fl_chart：外径 = centerSpace + section.radius（B1 缩小环）。
  static const _baseRadius = 36.0;
  static const _selectedRadius = 44.0;
  static const _centerHole = 40.0;
  static const _chartH = 220.0;
  /// 未选中环相对画布：顶 50、底 18（50+152+18=220）。
  static const _ringTopPad = 50.0;
  static double get _ringCenterY =>
      _ringTopPad + _centerHole + _baseRadius;

  Color _pieColor(int rankIndex) =>
      _kPieColors[rankIndex % _kPieColors.length];

  Color _listAccent(CompositionSlice slice) {
    if (widget.dim == CompositionDim.tag) {
      return TagColors.parse(
        slice.color,
        fallback: PigTokens.primary,
      );
    }
    return categoryIconColor(slice.icon);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      reportRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void dispose() {
    reportRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() {
    if (_selected >= 0) {
      setState(() => _selected = -1);
    }
  }

  @override
  void didUpdateWidget(covariant ReportCompositionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slices != widget.slices || oldWidget.dim != widget.dim) {
      _selected = -1;
      _expanded = false;
    }
  }

  String _centerSubtitle(List<CompositionSlice> slices) {
    if (_selected >= 0 && _selected < slices.length) {
      return slices[_selected].name;
    }
    return widget.moneyType == ReportMoneyType.expense ? '共支出(元)' : '共收入(元)';
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
                  height: _chartH,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final ringShift = Offset(
                        0,
                        _ringCenterY - constraints.maxHeight / 2,
                      );
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.translate(
                            offset: ringShift,
                            child: PieChart(
                            PieChartData(
                              startDegreeOffset: -90,
                              sectionsSpace: 2,
                              centerSpaceRadius: _centerHole,
                              pieTouchData: PieTouchData(
                                touchCallback: (event, response) {
                                  if (event is! FlTapUpEvent) return;
                                  final idx = response
                                      ?.touchedSection?.touchedSectionIndex;
                                  setState(() => _selected = idx ?? -1);
                                },
                              ),
                              sections: [
                                for (var i = 0; i < slices.length; i++)
                                  PieChartSectionData(
                                    color: _pieColor(i),
                                    value: slices[i].total,
                                    title: '',
                                    radius: _selected == i
                                        ? _selectedRadius
                                        : _baseRadius,
                                  ),
                              ],
                            ),
                          ),
                          ),
                          IgnorePointer(
                            child: CustomPaint(
                              size: Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              painter: _CalloutPainter(
                                slices: slices,
                                total: widget.total,
                                selected: _selected,
                                maxLabels: _calloutTop,
                                centerHole: _centerHole,
                                baseRadius: _baseRadius,
                                selectedRadius: _selectedRadius,
                                ringCenterY: _ringCenterY,
                                colors: [
                                  for (var i = 0; i < slices.length; i++)
                                    _pieColor(i),
                                ],
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Transform.translate(
                              offset: ringShift,
                              child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatMoney(
                                    _selected >= 0 &&
                                            _selected < slices.length
                                        ? slices[_selected].total
                                        : widget.total,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 88),
                                  child: Text(
                                    _centerSubtitle(slices),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: PigTokens.textTertiary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: PigTokens.spaceMd),
                for (var i = 0; i < visible.length; i++)
                  _SliceRow(
                    rank: i + 1,
                    slice: visible[i],
                    accent: _listAccent(visible[i]),
                    total: widget.total,
                    asExpense: widget.moneyType == ReportMoneyType.expense,
                    isTag: widget.dim == CompositionDim.tag,
                    onTap: widget.onSliceTap == null
                        ? null
                        : () => widget.onSliceTap!(visible[i]),
                  ),
                if (slices.length > _previewCount)
                  Center(
                    child: TextButton(
                      onPressed: () =>
                          setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? '收起' : '查看更多'),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// 环外引出 + 名称百分比（ADR-037）。
///
/// 横线长固定 = 未选中外径到卡片近边；字贴横线远端；簇内用斜线上抬散开。
class _CalloutPainter extends CustomPainter {
  _CalloutPainter({
    required this.slices,
    required this.total,
    required this.selected,
    required this.maxLabels,
    required this.centerHole,
    required this.baseRadius,
    required this.selectedRadius,
    required this.ringCenterY,
    required this.colors,
  });

  final List<CompositionSlice> slices;
  final double total;
  final int selected;
  final int maxLabels;
  final double centerHole;
  final double baseRadius;
  final double selectedRadius;
  final double ringCenterY;
  final List<Color> colors;

  static const _fontSize = 10.0;
  static const _minGap = 24.0;
  static const _edgePad = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || slices.isEmpty) return;
    final center = Offset(size.width / 2, ringCenterY);

    // 固定用未选中外径；凸出不影响折点/横线/字位。
    final baseOuterR = centerHole + baseRadius;
    final rightEndX = size.width - _edgePad;
    final leftEndX = _edgePad;
    final stubLen = math.max(16.0, rightEndX - (center.dx + baseOuterR));
    final rightFoldX = rightEndX - stubLen;
    final leftFoldX = leftEndX + stubLen;

    final candidates = <_CalloutCandidate>[];
    var start = -math.pi / 2;
    final n = math.min(slices.length, maxLabels);
    for (var i = 0; i < n; i++) {
      final sweep = slices[i].total / total * 2 * math.pi;
      final mid = start + sweep / 2;
      final cosA = math.cos(mid);
      final sinA = math.sin(mid);
      final pct = slices[i].total / total * 100;
      final label = '${_short(slices[i].name)} ${pct.toStringAsFixed(1)}%';
      // 引出起点始终按未选中外缘，与横线几何一致。
      final p0 = Offset(
        center.dx + cosA * (baseOuterR + 0.5),
        center.dy + sinA * (baseOuterR + 0.5),
      );
      candidates.add(
        _CalloutCandidate(
          index: i,
          amount: slices[i].total,
          isRight: cosA >= 0,
          p0: p0,
          idealY: center.dy + sinA * baseOuterR,
          label: label,
          color: colors[i],
        ),
      );
      start += sweep;
    }

    _maybeMoveTailToRight(candidates);
    final placed = _layout(candidates, size.height);
    for (final c in placed) {
      final foldX = c.isRight ? rightFoldX : leftFoldX;
      final endX = c.isRight ? rightEndX : leftEndX;
      final fold = Offset(foldX, c.lineY);
      final end = Offset(endX, c.lineY);

      if (stubLen < 16) continue;

      final tp = TextPainter(
        text: TextSpan(
          text: c.label,
          style: TextStyle(
            fontSize: _fontSize,
            fontWeight: FontWeight.w600,
            color: c.color,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: stubLen);

      // 字贴横线最远端：右标右齐、左标左齐。
      final textY = c.lineY - tp.height - 1;
      final textX = c.isRight ? endX - tp.width : endX;

      final paint = Paint()
        ..color = c.color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..moveTo(c.p0.dx, c.p0.dy)
        ..lineTo(fold.dx, fold.dy)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(path, paint);
      tp.paint(canvas, Offset(textX, textY));
    }
  }

  /// 左侧 ≥5 时，把标注集末尾两块搬到右侧并抬到顶：倒数第二最高，倒数第一次之。
  void _maybeMoveTailToRight(List<_CalloutCandidate> all) {
    if (all.length < 2) return;
    final leftCount = all.where((c) => !c.isRight).length;
    if (leftCount < 5) return;
    all[all.length - 2].isRight = true;
    all[all.length - 2].rightPin = 0;
    all[all.length - 1].isRight = true;
    all[all.length - 1].rightPin = 1;
  }

  /// 同侧按 Y 排布：从下往上抬满最小间距；整块再平移进图区；仍超高则等比压缩（B2，不丢标）。
  /// 斜线相对朝环水平方向：折点 X 固定在环外，从环侧接入，抬高只变陡、不变钝角；横线始终保留。
  List<_CalloutCandidate> _layout(
    List<_CalloutCandidate> all,
    double height,
  ) {
    final left = all.where((c) => !c.isRight).toList()
      ..sort((a, b) => a.idealY.compareTo(b.idealY));
    final rightRest = all.where((c) => c.isRight && c.rightPin == null).toList()
      ..sort((a, b) => a.idealY.compareTo(b.idealY));
    final rightPins = all.where((c) => c.isRight && c.rightPin != null).toList()
      ..sort((a, b) => a.rightPin!.compareTo(b.rightPin!));

    _packSide(left, height);
    final pinMinY = _edgePad + _fontSize + 2;
    if (rightPins.length >= 2) {
      rightPins[0].lineY = pinMinY;
      rightPins[1].lineY = pinMinY + _minGap;
      _packSide(rightRest, height, floorY: rightPins[1].lineY + _minGap);
    } else {
      _packSide(rightRest, height);
    }
    return [...left, ...rightPins, ...rightRest];
  }

  void _packSide(
    List<_CalloutCandidate> side,
    double height, {
    double? floorY,
  }) {
    if (side.isEmpty) return;
    final minY = math.max(_edgePad + _fontSize + 2, floorY ?? 0);
    final maxY = height - _edgePad;
    if (maxY <= minY) {
      for (final c in side) {
        c.lineY = minY;
      }
      return;
    }

    for (final c in side) {
      c.lineY = c.idealY;
    }

    // 先自由上抬（允许暂时超出图区），避免刚抬到顶就叠在 minY。
    for (var i = side.length - 2; i >= 0; i--) {
      final lifted = side[i + 1].lineY - _minGap;
      if (side[i].lineY > lifted) {
        side[i].lineY = lifted;
      }
    }

    if (side.length == 1) {
      side.first.lineY = side.first.lineY.clamp(minY, maxY);
      return;
    }

    final first = side.first.lineY;
    final last = side.last.lineY;
    final avail = maxY - minY;
    final span = last - first;

    if (span < 1e-6) {
      final gap = math.min(_minGap, avail / (side.length - 1));
      for (var i = 0; i < side.length; i++) {
        side[i].lineY = minY + i * gap;
      }
      return;
    }

    if (span > avail) {
      for (final c in side) {
        final t = (c.lineY - first) / span;
        c.lineY = minY + t * avail;
      }
      return;
    }

    var shift = 0.0;
    if (first < minY) shift = minY - first;
    if (last + shift > maxY) shift = maxY - last;
    if (shift == 0) return;
    for (final c in side) {
      c.lineY += shift;
    }
  }

  String _short(String name) {
    if (name.length <= 8) return name;
    return '${name.substring(0, 7)}…';
  }

  @override
  bool shouldRepaint(covariant _CalloutPainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.total != total ||
        oldDelegate.selected != selected ||
        oldDelegate.centerHole != centerHole ||
        oldDelegate.baseRadius != baseRadius ||
        oldDelegate.selectedRadius != selectedRadius ||
        oldDelegate.ringCenterY != ringCenterY;
  }
}

class _CalloutCandidate {
  _CalloutCandidate({
    required this.index,
    required this.amount,
    required this.isRight,
    required this.p0,
    required this.idealY,
    required this.label,
    required this.color,
  });

  final int index;
  final double amount;
  bool isRight;
  final Offset p0;
  final double idealY;
  final String label;
  final Color color;
  /// 右侧置顶：0 最高（倒数第二），1 次高（倒数第一）。
  int? rightPin;
  double lineY = 0;
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
    required this.rank,
    required this.slice,
    required this.accent,
    required this.total,
    required this.asExpense,
    required this.isTag,
    this.onTap,
  });

  final int rank;
  final CompositionSlice slice;
  final Color accent;
  final double total;
  final bool asExpense;
  final bool isTag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : math.min(1.0, slice.total / total);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PigTokens.spaceSm),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 13,
                  color: PigTokens.textTertiary,
                ),
              ),
            ),
            if (isTag)
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            else
              CategoryIconCircle(
                name: slice.name,
                icon: slice.icon,
                iconType: slice.iconType,
                customIconPath: slice.customIconPath,
                diameter: 36,
                iconSize: 18,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: slice.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: PigTokens.textPrimary,
                          ),
                        ),
                        TextSpan(
                          text: ' ${slice.txCount}笔',
                          style: const TextStyle(
                            fontSize: 12,
                            color: PigTokens.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 3,
                      backgroundColor: const Color(0xFFE5E7EB),
                      color: accent.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatSignedMoney(slice.total, asExpense: asExpense),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: PigTokens.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
