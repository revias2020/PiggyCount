import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/ledger_session_provider.dart';
import '../../styles/tokens.dart';
import '../ledger_list_sheet.dart';
import 'year_month_grid_sheet.dart';

/// 明细一体顶栏：品牌 + 账本 + 日历 + 搜索。
class DetailsTopBar extends ConsumerWidget {
  const DetailsTopBar({
    super.key,
    required this.onOpenCalendar,
    required this.onOpenSearch,
  });

  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(ledgerSessionProvider);
    final name = session.valueOrNull?.current.name ?? '加载中…';

    return Material(
      color: PigTokens.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PigTokens.spaceLg,
            PigTokens.spaceSm,
            PigTokens.spaceSm,
            PigTokens.spaceSm,
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/brand/piggyCount.png',
                width: 28,
                height: 28,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.savings_outlined,
                  color: PigTokens.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: PigTokens.spaceSm),
              const Text(
                '小猪记账',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: PigTokens.textPrimary,
                ),
              ),
              const SizedBox(width: PigTokens.spaceMd),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(PigTokens.radiusPill),
                    onTap: () => showLedgerListSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PigTokens.spaceMd,
                        vertical: PigTokens.spaceXs + 2,
                      ),
                      decoration: BoxDecoration(
                        color: PigTokens.primarySoft,
                        borderRadius:
                            BorderRadius.circular(PigTokens.radiusPill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: PigTokens.primary,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: PigTokens.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '日历',
                onPressed: onOpenCalendar,
                icon: const Icon(Icons.calendar_month_outlined),
                color: PigTokens.textPrimary,
              ),
              IconButton(
                tooltip: '搜索',
                onPressed: onOpenSearch,
                icon: const Icon(Icons.search),
                color: PigTokens.textPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 月份点选 + 收入｜支出｜结余。
class MonthSummaryBar extends StatelessWidget {
  const MonthSummaryBar({
    super.key,
    required this.month,
    required this.income,
    required this.expense,
    required this.onMonthChanged,
  });

  final DateTime month;
  final double income;
  final double expense;
  final ValueChanged<DateTime> onMonthChanged;

  double get _balance => income - expense;

  Future<void> _pickMonth(BuildContext context) async {
    final picked = await showYearMonthGridSheet(
      context,
      initialMonth: month,
    );
    if (picked != null) onMonthChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final yearLabel = DateFormat('y年').format(month);
    final monthLabel = DateFormat('MM月').format(month);

    return Material(
      color: PigTokens.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PigTokens.spaceLg,
          PigTokens.spaceXs,
          PigTokens.spaceLg,
          PigTokens.spaceMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: () => _pickMonth(context),
              borderRadius: BorderRadius.circular(PigTokens.radiusCard),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PigTokens.spaceXs,
                  vertical: PigTokens.spaceXs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          yearLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: PigTokens.textTertiary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              monthLabel,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: PigTokens.textPrimary,
                                height: 1.1,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: PigTokens.textSecondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: PigTokens.spaceMd),
              color: PigTokens.surfaceInput,
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _Metric(label: '收入', value: income),
                  ),
                  Expanded(
                    child: _Metric(label: '支出', value: expense),
                  ),
                  Expanded(
                    child: _Metric(label: '结余', value: _balance),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final text = value < 0
        ? value.toStringAsFixed(value.abs() >= 100 ? 0 : 2)
        : _formatCompact(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: PigTokens.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: PigTokens.textPrimary,
          ),
        ),
      ],
    );
  }

  String _formatCompact(double v) {
    if (v >= 1000) {
      final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
      // 千分位
      final parts = s.split('.');
      final whole = parts[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
      return parts.length > 1 ? '$whole.${parts[1]}' : whole;
    }
    return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
  }
}
