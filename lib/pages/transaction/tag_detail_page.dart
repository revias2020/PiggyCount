import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/report_period.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_status.dart';
import '../../widgets/transaction/transaction_row_tile.dart';
import 'category_detail_page.dart';

/// 标签明细：月度可换月（ADR-029）；报表入口带只读周期（ADR-033）。
/// [tagId] 为 null 表示未标注（ADR-039）。
class TagDetailPage extends ConsumerStatefulWidget {
  const TagDetailPage({
    super.key,
    this.tagId,
    required this.tagName,
    this.initialMonth,
    this.lockedPeriod,
  }) : assert(
          initialMonth != null || lockedPeriod != null,
          'initialMonth or lockedPeriod required',
        );

  /// `null` 表示未标注。
  final int? tagId;
  final String tagName;
  final DateTime? initialMonth;
  final ReportPeriod? lockedPeriod;

  @override
  ConsumerState<TagDetailPage> createState() => _TagDetailPageState();
}

class _TagDetailPageState extends ConsumerState<TagDetailPage> {
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

  TagDetailQuery get _query {
    final locked = widget.lockedPeriod;
    if (locked != null) {
      return TagDetailQuery(
        start: locked.start,
        end: locked.end,
        tagId: widget.tagId,
      );
    }
    return TagDetailQuery.month(month: _month, tagId: widget.tagId);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final async = ref.watch(tagDetailTransactionsProvider(query));
    final locked = widget.lockedPeriod;

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
