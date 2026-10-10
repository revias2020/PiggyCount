import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../../utils/report_period.dart';
import '../../widgets/details/year_month_grid_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_status.dart';
import '../../widgets/report/report_period_pickers.dart';
import '../../widgets/transaction/transaction_row_tile.dart';

/// 分类明细：月度可换月（ADR-029）；报表入口可切周期，与上一层独立。
class CategoryDetailPage extends ConsumerStatefulWidget {
  const CategoryDetailPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.initialMonth,
    this.initialPeriod,
    this.includeChildren = false,
  }) : assert(
          initialMonth != null || initialPeriod != null,
          'initialMonth or initialPeriod required',
        );

  /// `null` 表示未分类。
  final int? categoryId;
  final String categoryName;
  final DateTime? initialMonth;

  /// 报表构成下钻初值；页内可切换，不回写报表。
  final ReportPeriod? initialPeriod;
  final bool includeChildren;

  @override
  ConsumerState<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends ConsumerState<CategoryDetailPage> {
  DateTime? _month;
  ReportPeriod? _period;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPeriod;
    if (initial != null) {
      _period = initial;
    } else {
      final m = widget.initialMonth!;
      _month = DateTime(m.year, m.month);
    }
  }

  CategoryDetailQuery get _query {
    final period = _period;
    if (period != null) {
      return CategoryDetailQuery(
        start: period.start,
        end: period.end,
        categoryId: widget.categoryId,
        includeChildren: widget.includeChildren,
      );
    }
    return CategoryDetailQuery.month(
      month: _month!,
      categoryId: widget.categoryId,
      includeChildren: widget.includeChildren,
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final async = ref.watch(categoryDetailTransactionsProvider(query));
    final period = _period;

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: Text(widget.categoryName)),
      body: async.when(
        loading: () => const AppLoading(message: '加载账单…'),
        error: (e, _) => AppErrorState(
          message: '加载失败，请稍后重试',
          onRetry: () =>
              ref.invalidate(categoryDetailTransactionsProvider(query)),
        ),
        data: (items) {
          var expense = 0.0;
          var income = 0.0;
          for (final item in items) {
            if (item.tx.type == 'expense') {
              expense += item.tx.amount;
            } else {
              income += item.tx.amount;
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (period != null)
                DetailPeriodNavBar(
                  period: period,
                  count: items.length,
                  expense: expense,
                  income: income,
                  onPeriodChanged: (p) => setState(() => _period = p),
                )
              else
                DetailMonthNavBar(
                  month: _month!,
                  count: items.length,
                  expense: expense,
                  income: income,
                  onMonthChanged: (m) => setState(() => _month = m),
                ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? EmptyState(
                        message: period != null ? '本期暂无账单' : '本月暂无账单',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          vertical: PigTokens.spaceSm,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: 60,
                        ),
                        itemBuilder: (context, i) {
                          return Material(
                            color: PigTokens.surface,
                            child: TransactionRowTile(
                              item: items[i],
                              showMonthDay: true,
                              enableLongPressDelete: true,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 分类/标签明细共用的月份导航 + 汇总。
class DetailMonthNavBar extends StatelessWidget {
  const DetailMonthNavBar({
    super.key,
    required this.month,
    required this.count,
    required this.expense,
    required this.income,
    required this.onMonthChanged,
  });

  final DateTime month;
  final int count;
  final double expense;
  final double income;
  final ValueChanged<DateTime> onMonthChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showYearMonthGridSheet(
      context,
      initialMonth: month,
    );
    if (picked != null) {
      onMonthChanged(DateTime(picked.year, picked.month));
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('y年M月').format(month);
    return Material(
      color: PigTokens.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PigTokens.spaceSm,
          PigTokens.spaceSm,
          PigTokens.spaceLg,
          PigTokens.spaceMd,
        ),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上一月',
                  onPressed: () => onMonthChanged(
                    DateTime(month.year, month.month - 1),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => _pick(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一月',
                  onPressed: () => onMonthChanged(
                    DateTime(month.year, month.month + 1),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            _DetailSummaryRow(
              count: count,
              expense: expense,
              income: income,
            ),
          ],
        ),
      ),
    );
  }
}

/// 报表下钻：周期 ◀▶（与报表同语义，页内独立，不回写）。
class DetailPeriodNavBar extends StatelessWidget {
  const DetailPeriodNavBar({
    super.key,
    required this.period,
    required this.count,
    required this.expense,
    required this.income,
    required this.onPeriodChanged,
  });

  final ReportPeriod period;
  final int count;
  final double expense;
  final double income;
  final ValueChanged<ReportPeriod> onPeriodChanged;

  bool get _showArrows => period.scope != ReportScope.custom;

  Future<void> _pick(BuildContext context) async {
    switch (period.scope) {
      case ReportScope.week:
        final picked = await showReportWeekPicker(
          context,
          initialAnchor: period.anchor,
        );
        if (picked != null) {
          onPeriodChanged(ReportPeriod.fromScope(ReportScope.week, picked));
        }
      case ReportScope.month:
        final picked = await showReportMonthPicker(
          context,
          initialMonth: period.anchor,
        );
        if (picked != null) {
          onPeriodChanged(ReportPeriod.fromScope(ReportScope.month, picked));
        }
      case ReportScope.year:
        final picked = await showReportYearPicker(
          context,
          initialYear: period.anchor,
        );
        if (picked != null) {
          onPeriodChanged(ReportPeriod.fromScope(ReportScope.year, picked));
        }
      case ReportScope.custom:
        final endInclusive = period.end.subtract(const Duration(days: 1));
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialDateRange: DateTimeRange(
            start: period.start,
            end: endInclusive,
          ),
          helpText: '选择自定义区间',
        );
        if (range != null) {
          onPeriodChanged(
            ReportPeriod.custom(
              startInclusive: DateTime(
                range.start.year,
                range.start.month,
                range.start.day,
              ),
              endExclusive: DateTime(
                range.end.year,
                range.end.month,
                range.end.day,
              ).add(const Duration(days: 1)),
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = formatReportPeriodTitle(period);
    return Material(
      color: PigTokens.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PigTokens.spaceSm,
          PigTokens.spaceSm,
          PigTokens.spaceLg,
          PigTokens.spaceMd,
        ),
        child: Column(
          children: [
            Row(
              children: [
                if (_showArrows)
                  IconButton(
                    tooltip: '上一周期',
                    onPressed: () => onPeriodChanged(period.previous),
                    icon: const Icon(Icons.chevron_left),
                  )
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: InkWell(
                    onTap: () => _pick(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_showArrows)
                  IconButton(
                    tooltip: '下一周期',
                    onPressed: () => onPeriodChanged(period.next),
                    icon: const Icon(Icons.chevron_right),
                  )
                else
                  IconButton(
                    tooltip: '选择区间',
                    onPressed: () => _pick(context),
                    icon: const Icon(Icons.date_range, size: 20),
                  ),
              ],
            ),
            _DetailSummaryRow(
              count: count,
              expense: expense,
              income: income,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSummaryRow extends StatelessWidget {
  const _DetailSummaryRow({
    required this.count,
    required this.expense,
    required this.income,
  });

  final int count;
  final double expense;
  final double income;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryChip(label: '笔数', value: '$count'),
        ),
        Expanded(
          child: _SummaryChip(
            label: '支出',
            value: formatMoneyCompact(expense),
            color: PigTokens.expense,
          ),
        ),
        Expanded(
          child: _SummaryChip(
            label: '收入',
            value: formatMoneyCompact(income),
            color: PigTokens.income,
          ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color ?? PigTokens.textPrimary,
          ),
        ),
      ],
    );
  }
}
