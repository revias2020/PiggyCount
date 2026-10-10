import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/report_period.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_status.dart';
import '../../widgets/transaction/transaction_row_tile.dart';
import 'category_detail_page.dart';

/// 标签明细：月度可换月（ADR-029）；报表入口可切周期，与上一层独立。
/// [tagId] 为 null 表示未标注（ADR-039）。
class TagDetailPage extends ConsumerStatefulWidget {
  const TagDetailPage({
    super.key,
    this.tagId,
    required this.tagName,
    this.initialMonth,
    this.initialPeriod,
  }) : assert(
          initialMonth != null || initialPeriod != null,
          'initialMonth or initialPeriod required',
        );

  /// `null` 表示未标注。
  final int? tagId;
  final String tagName;
  final DateTime? initialMonth;

  /// 报表构成下钻初值；页内可切换，不回写报表。
  final ReportPeriod? initialPeriod;

  @override
  ConsumerState<TagDetailPage> createState() => _TagDetailPageState();
}

class _TagDetailPageState extends ConsumerState<TagDetailPage> {
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

  TagDetailQuery get _query {
    final period = _period;
    if (period != null) {
      return TagDetailQuery(
        start: period.start,
        end: period.end,
        tagId: widget.tagId,
      );
    }
    return TagDetailQuery.month(month: _month!, tagId: widget.tagId);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final async = ref.watch(tagDetailTransactionsProvider(query));
    final period = _period;

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: Text(widget.tagName)),
      body: async.when(
        loading: () => const AppLoading(message: '加载账单…'),
        error: (e, _) => AppErrorState(
          message: '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(tagDetailTransactionsProvider(query)),
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
