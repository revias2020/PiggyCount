import 'package:flutter/material.dart';

import '../widget_data_service.dart';
import '../widget_spec.dart' show HWSize, WidgetSpec;
import 'widget_view_style.dart';

/// 收支速览 headless 视图：小 / 中（ADR-024 仿毛玻璃）。
///
/// 中号：渲图 [width]×[height] 跟槽（ADR-062）；上下透明与浮卡按总高
/// `10:162:10`；卡内按浮卡比例；字号等取 `min(W/364, contentH/162)`。
class GlanceView extends StatelessWidget {
  const GlanceView.medium({
    super.key,
    required this.todayExpense,
    required this.todayIncome,
    required this.themeColor,
    required this.width,
    required this.height,
    required this.last7Days,
    this.amountsHidden = false,
    this.titleLabel = '收支速览',
    this.monthSuffix = '月',
    this.todayExpenseLabel = '今日支出',
    this.todayIncomeLabel = '今日收入',
    this.monthExpenseLabel = '本月支出',
    this.monthIncomeLabel = '本月收入',
    this.todayLabel = '今日',
    this.monthExpense = '',
    this.monthIncome = '',
  }) : size = HWSize.medium;

  const GlanceView.small({
    super.key,
    required this.todayExpense,
    required this.monthExpense,
    required this.monthIncome,
    required this.themeColor,
    required this.width,
    required this.height,
    this.amountsHidden = false,
    this.todayLabel = '今日',
    this.todayExpenseLabel = '今日支出',
    this.monthExpenseLabel = '本月支出',
    this.monthIncomeLabel = '本月收入',
    this.todayIncome = '',
    this.titleLabel = '',
    this.monthSuffix = '',
    this.todayIncomeLabel = '',
    this.last7Days = const [],
  }) : size = HWSize.small;

  final HWSize size;
  final String todayExpense;
  final String todayIncome;
  final String monthExpense;
  final String monthIncome;
  final Color themeColor;
  final String titleLabel;
  final String monthSuffix;
  final String todayLabel;
  final String todayExpenseLabel;
  final String todayIncomeLabel;
  final String monthExpenseLabel;
  final String monthIncomeLabel;
  final double width;
  final double height;
  final bool amountsHidden;
  final List<GlanceDayPoint> last7Days;

  static const masked = '****';

  String _money(String value) => amountsHidden ? masked : value;

  @override
  Widget build(BuildContext context) {
    return size == HWSize.small ? _buildSmall() : _buildMedium();
  }

  Widget _buildSmall() {
    final textSecondary = widgetTextSecondary();
    final pad = width < 130 ? 10.0 : 12.0;
    // 顶行圆点+「今日支出」；金额约 20（点金额=隐私）；本月两列均分无竖线；底栏标签 8。
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: widgetCardBackground(),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: themeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  todayExpenseLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: textSecondary,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(todayExpense),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kWidgetExpense,
                height: 1.0,
                fontFeatures: [kWidgetTabularFeature],
              ),
            ),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _miniStat(
                  monthExpenseLabel,
                  _money(monthExpense),
                  kWidgetExpense,
                  textSecondary,
                ),
              ),
              Expanded(
                child: _miniStat(
                  monthIncomeLabel,
                  _money(monthIncome),
                  kWidgetIncome,
                  textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
    String label,
    String value,
    Color valueColor,
    Color labelColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 8, color: labelColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: valueColor,
            fontFeatures: const [kWidgetTabularFeature],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildMedium() {
    final textSecondary = widgetTextSecondary();
    final designH = WidgetSpec.mediumDesignHeight;
    final designContent = WidgetSpec.glanceMediumContentHeight;
    // 纵向：透明 / 浮卡 / 透明 = 10:162:10（相对整高）。
    final contentH = height * (designContent / designH);
    final verticalPad = ((height - contentH) / 2).clamp(0.0, height / 2);
    final scale = (width / WidgetSpec.mediumDesignWidth)
        .clamp(0.0, contentH / designContent);
    // 卡内相对浮卡：14 / 46 / 12 / 76 / 14。
    final pad = contentH * (WidgetSpec.glanceMediumPad / designContent);
    final todayH =
        contentH * (WidgetSpec.glanceMediumTodayRowHeight / designContent);
    final gap =
        contentH * (WidgetSpec.glanceMediumTodayChartGap / designContent);
    final chartH =
        contentH * (WidgetSpec.glanceMediumChartHeight / designContent);
    final days = last7Days.isEmpty
        ? List.generate(
            7,
            (i) => GlanceDayPoint(
              day: DateTime.now().subtract(Duration(days: 6 - i)),
              label: i == 6 ? '今日' : '—',
              expense: 0,
              income: 0,
            ),
          )
        : last7Days;
    final addSize = (40 * scale).clamp(0.0, todayH);
    final gapH = 8 * scale;

    return Container(
      width: width,
      height: height,
      color: Colors.transparent,
      padding: EdgeInsets.symmetric(vertical: verticalPad),
      child: Container(
        width: width,
        height: contentH,
        decoration: BoxDecoration(
          color: widgetCardBackground(),
          borderRadius: BorderRadius.circular(20 * scale),
        ),
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: todayH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _todayBlock(
                      todayExpenseLabel,
                      _money(todayExpense),
                      kWidgetChartExpense,
                      textSecondary,
                      scale,
                    ),
                  ),
                  SizedBox(width: gapH),
                  Expanded(
                    child: _todayBlock(
                      todayIncomeLabel,
                      _money(todayIncome),
                      kWidgetChartIncome,
                      textSecondary,
                      scale,
                    ),
                  ),
                  SizedBox(width: gapH),
                  Container(
                    width: addSize,
                    height: addSize,
                    decoration: BoxDecoration(
                      color: themeColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 22 * scale,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: gap),
            SizedBox(
              height: chartH,
              width: double.infinity,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  10 * scale,
                  8 * scale,
                  10 * scale,
                  4 * scale,
                ),
                decoration: BoxDecoration(
                  color: widgetInnerPanel(),
                  borderRadius: BorderRadius.circular(14 * scale),
                ),
                child: _WeekChart(
                  days: days,
                  amountsHidden: amountsHidden,
                  scale: scale,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayBlock(
    String label,
    String value,
    Color dotColor,
    Color labelColor,
    double scale,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 7 * scale,
              height: 7 * scale,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 5 * scale),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: 6 * scale),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 22 * scale,
              fontWeight: FontWeight.w700,
              color: kWidgetExpense,
              height: 1.05,
              fontFeatures: const [kWidgetTabularFeature],
            ),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({
    required this.days,
    required this.amountsHidden,
    required this.scale,
  });

  final List<GlanceDayPoint> days;
  final bool amountsHidden;
  final double scale;

  @override
  Widget build(BuildContext context) {
    var maxVal = 0.0;
    for (final d in days) {
      if (d.expense > maxVal) maxVal = d.expense;
      if (d.income > maxVal) maxVal = d.income;
    }
    if (maxVal <= 0) maxVal = 1;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackH = constraints.maxHeight;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final d in days)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2 * scale),
                        child: _DayBars(
                          expense: d.expense,
                          income: d.income,
                          maxVal: maxVal,
                          amountsHidden: amountsHidden,
                          trackHeight: trackH,
                          scale: scale,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: 4 * scale),
        Row(
          children: [
            for (final d in days)
              Expanded(
                child: Text(
                  d.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9 * scale,
                    color: widgetTextSecondary(),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayBars extends StatelessWidget {
  const _DayBars({
    required this.expense,
    required this.income,
    required this.maxVal,
    required this.amountsHidden,
    required this.trackHeight,
    required this.scale,
  });

  final double expense;
  final double income;
  final double maxVal;
  final bool amountsHidden;
  final double trackHeight;
  final double scale;

  @override
  Widget build(BuildContext context) {
    // ADR-027：占满轨道高度，无数据也保留浅色柱轨。
    return SizedBox(
      height: trackHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: amountsHidden ? _hiddenDots() : _valueBars(),
      ),
    );
  }

  double get _barW => 5 * scale;
  double get _gap => 2 * scale;
  double get _minBar => 4 * scale;

  Widget _hiddenDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _dot(kWidgetChartExpense),
        SizedBox(width: _gap),
        _dot(kWidgetChartIncome),
      ],
    );
  }

  Widget _valueBars() {
    final hasExpense = expense > 0;
    final hasIncome = income > 0;
    if (!hasExpense && !hasIncome) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _rail(),
          SizedBox(width: _gap),
          _rail(),
        ],
      );
    }

    Widget bar(double v, Color c) {
      final h = (v / maxVal).clamp(0.0, 1.0) * trackHeight;
      return Container(
        width: _barW,
        height: h < _minBar && v > 0 ? _minBar : h,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2 * scale),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (hasExpense) bar(expense, kWidgetChartExpense),
        if (hasExpense && hasIncome) SizedBox(width: _gap),
        if (hasIncome) bar(income, kWidgetChartIncome),
      ],
    );
  }

  Widget _rail() {
    return Container(
      width: _barW,
      height: trackHeight,
      decoration: BoxDecoration(
        color: widgetTextTertiary().withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(2 * scale),
      ),
    );
  }

  Widget _dot(Color c) {
    return Container(
      width: 4 * scale,
      height: 4 * scale,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
    );
  }
}
