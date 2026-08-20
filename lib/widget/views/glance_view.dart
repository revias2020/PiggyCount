import 'package:flutter/material.dart';

import '../widget_data_service.dart';
import '../widget_spec.dart' show HWSize;
import 'widget_view_style.dart';

/// 收支速览 headless 视图：小 / 中（ADR-024 仿毛玻璃）。
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
    // 顶行圆点+「今日支出」+眼睛；金额约 20；本月两列均分无竖线；底栏标签 8。
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
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                amountsHidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: widgetTextTertiary(),
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
    final compact = height < 140;
    final pad = compact ? 10.0 : 14.0;
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

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: widgetCardBackground(),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: EdgeInsets.all(pad),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _todayBlock(
                  todayExpenseLabel,
                  _money(todayExpense),
                  kWidgetChartExpense,
                  textSecondary,
                  showEye: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _todayBlock(
                  todayIncomeLabel,
                  _money(todayIncome),
                  kWidgetChartIncome,
                  textSecondary,
                  showEye: false,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: compact ? 36 : 40,
                height: compact ? 36 : 40,
                decoration: BoxDecoration(
                  color: themeColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 22),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 柱区固定高度，不随槽位把剩余空间撑满；过矮时再收缩以免溢出。
                final desired = compact ? 40.0 : 52.0;
                final chartH = desired < constraints.maxHeight
                    ? desired
                    : constraints.maxHeight;
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: chartH,
                    width: double.infinity,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 6 : 10,
                        compact ? 6 : 8,
                        compact ? 6 : 10,
                        compact ? 2 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: widgetInnerPanel(),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: _WeekChart(
                        days: days,
                        amountsHidden: amountsHidden,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _todayBlock(
    String label,
    String value,
    Color dotColor,
    Color labelColor, {
    required bool showEye,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showEye) ...[
              const SizedBox(width: 4),
              Icon(
                amountsHidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 16,
                color: widgetTextTertiary(),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: kWidgetExpense,
              height: 1.05,
              fontFeatures: [kWidgetTabularFeature],
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
  });

  final List<GlanceDayPoint> days;
  final bool amountsHidden;

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
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _DayBars(
                          expense: d.expense,
                          income: d.income,
                          maxVal: maxVal,
                          amountsHidden: amountsHidden,
                          trackHeight: trackH,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final d in days)
              Expanded(
                child: Text(
                  d.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
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
  });

  final double expense;
  final double income;
  final double maxVal;
  final bool amountsHidden;
  final double trackHeight;

  static const _barW = 5.0;

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

  Widget _hiddenDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _dot(kWidgetChartExpense),
        const SizedBox(width: 2),
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
          const SizedBox(width: 2),
          _rail(),
        ],
      );
    }

    Widget bar(double v, Color c) {
      final h = (v / maxVal).clamp(0.0, 1.0) * trackHeight;
      return Container(
        width: _barW,
        height: h < 4 && v > 0 ? 4 : h,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (hasExpense) bar(expense, kWidgetChartExpense),
        if (hasExpense && hasIncome) const SizedBox(width: 2),
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
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _dot(Color c) {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
    );
  }
}
