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
import '../../widgets/transaction/transaction_row_tile.dart';

/// 分类明细：月度可换月（ADR-029）；报表入口带只读周期（ADR-033）。
class CategoryDetailPage extends ConsumerStatefulWidget {
  const CategoryDetailPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.initialMonth,
    this.lockedPeriod,
    this.includeChildren = false,
  }) : assert(
          initialMonth != null || lockedPeriod != null,
          'initialMonth or lockedPeriod required',
        );

  /// `null` 表示未分类。
  final int? categoryId;
  final String categoryName;
  final DateTime? initialMonth;

  /// 非空时顶栏区间只读，列表按该周期过滤。
  final ReportPeriod? lockedPeriod;
  final bool includeChildren;

  @override
  ConsumerState<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends ConsumerState<CategoryDetailPage> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final locked = widget.lockedPeriod;
    if (locked != null) {
      _month = DateTime(locked.anchor.year, locked.anchor.month);
    } else {
      final m = widget.initialMonth!;
      _month = DateTime(m.year, m.month);
    }
  }

  CategoryDetailQuery get _query {
    final locked = widget.lockedPeriod;
    if (locked != null) {
      return CategoryDetailQuery(
        start: locked.start,
        end: locked.end,
        categoryId: widget.categoryId,
        includeChildren: widget.includeChildren,
      );
    }
    return CategoryDetailQuery.month(
      month: _month,
      categoryId: widget.categoryId,
      includeChildren: widget.includeChildren,
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final async = ref.watch(categoryDetailTransactionsProvider(query));
    final locked = widget.lockedPeriod;

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
              if (locked != null)
                DetailPeriodReadonlyBar(
                  label: formatReportPeriodTitle(locked),
                  count: items.length,
                  expense: expense,
                  income: income,
                )
              else
                DetailMonthNavBar(
                  month: _month,
                  count: items.length,
                  expense: expense,
                  income: income,
                  onMonthChanged: (m) => setState(() => _month = m),
                ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? EmptyState(
                        message: locked != null ? '本期暂无账单' : '本月暂无账单',
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
                            child: TransactionRowTile(item: items[i]),
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

/// 报表下钻：只读周期文案 + 汇总（ADR-033）。
class DetailPeriodReadonlyBar extends StatelessWidget {
  const DetailPeriodReadonlyBar({
    super.key,
    required this.label,
    required this.count,
    required this.expense,
    required this.income,
  });

  final String label;
  final int count;
  final double expense;
  final double income;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PigTokens.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PigTokens.spaceLg,
          PigTokens.spaceMd,
          PigTokens.spaceLg,
          PigTokens.spaceMd,
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: PigTokens.spaceSm),
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
