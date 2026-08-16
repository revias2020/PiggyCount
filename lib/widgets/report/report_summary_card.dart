import 'package:flutter/material.dart';

import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../../utils/report_period.dart';

/// 报表顶部 2×2 汇总卡：本期合计、日均、环比、结余。
class ReportSummaryCard extends StatelessWidget {
  const ReportSummaryCard({
    super.key,
    required this.scope,
    required this.moneyType,
    required this.periodTotal,
    required this.dayCount,
    required this.periodDelta,
    required this.balance,
  });

  final ReportScope scope;
  final ReportMoneyType moneyType;
  final double periodTotal;
  final int dayCount;
  final double periodDelta;
  final double balance;

  String get _scopeLabel => switch (scope) {
        ReportScope.week => '本周',
        ReportScope.month => '本月',
        ReportScope.year => '本年',
        ReportScope.custom => '本期',
      };

  String get _typeLabel =>
      moneyType == ReportMoneyType.expense ? '支出' : '收入';

  String get _prevLabel => switch (scope) {
        ReportScope.week => '比上周$_typeLabel',
        ReportScope.month => '比上月$_typeLabel',
        ReportScope.year => '比上年$_typeLabel',
        ReportScope.custom => '比上期$_typeLabel',
      };

  @override
  Widget build(BuildContext context) {
    final daily = periodTotal / dayCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        PigTokens.spaceMd,
        PigTokens.spaceSm,
        PigTokens.spaceMd,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PigTokens.spaceLg,
        vertical: PigTokens.spaceLg,
      ),
      decoration: BoxDecoration(
        color: PigTokens.surface,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: '$_scopeLabel$_typeLabel(元)',
                  value: formatMoney(periodTotal),
                  emphasize: true,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '日均$_typeLabel(元)',
                  value: formatMoney(daily),
                ),
              ),
            ],
          ),
          const SizedBox(height: PigTokens.spaceLg),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: '$_prevLabel(元)',
                  value: formatMoney(periodDelta),
                  emphasizeSign: true,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '收支结余(元)',
                  value: formatMoney(balance),
                  emphasizeSign: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.emphasizeSign = false,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool emphasizeSign;

  @override
  Widget build(BuildContext context) {
    Color? valueColor;
    if (emphasizeSign && value.startsWith('-')) {
      valueColor = PigTokens.danger;
    } else if (emphasizeSign &&
        value != '0.00' &&
        !value.startsWith('-') &&
        value != '0') {
      valueColor = PigTokens.income;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: PigTokens.textTertiary,
          ),
        ),
        const SizedBox(height: PigTokens.spaceXs),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 22 : 18,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: valueColor ?? PigTokens.textPrimary,
          ),
        ),
      ],
    );
  }
}
