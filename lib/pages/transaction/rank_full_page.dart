import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/transaction_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../../utils/report_period.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_status.dart';
import '../../widgets/report/report_rank_tile.dart';
import 'record_editor_sheet.dart';
import '../../widgets/pig_toast.dart';

/// 排行全页：金额双向排序、三列汇总、仅批量删除（ADR-033）。
class RankFullPage extends ConsumerStatefulWidget {
  const RankFullPage({
    super.key,
    required this.period,
    required this.moneyType,
    required this.expenseTotal,
    required this.incomeTotal,
  });

  final ReportPeriod period;
  final ReportMoneyType moneyType;
  final double expenseTotal;
  final double incomeTotal;

  @override
  ConsumerState<RankFullPage> createState() => _RankFullPageState();
}

class _RankFullPageState extends ConsumerState<RankFullPage> {
  bool _ascending = false;
  bool _batchMode = false;
  final Set<int> _selectedIds = {};

  String get _title {
    final type =
        widget.moneyType == ReportMoneyType.expense ? '支出' : '收入';
    return '${formatReportPeriodTitle(widget.period)}$type排行';
  }

  List<TransactionListItem> _sorted(List<TransactionListItem> items) {
    final list = List<TransactionListItem>.from(items);
    list.sort((a, b) {
      final cmp = a.tx.amount.compareTo(b.tx.amount);
      return _ascending ? cmp : -cmp;
    });
    return list;
  }

  Future<void> _batchDelete() async {
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 $count 笔账单？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(transactionRepositoryProvider);
    for (final id in _selectedIds.toList()) {
      await repo.delete(id);
    }
    if (!mounted) return;
    setState(() {
      _batchMode = false;
      _selectedIds.clear();
    });
    PigToast.show(context, '已删除 $count 笔');
  }

  @override
  Widget build(BuildContext context) {
    final query = RankFullQuery(
      start: widget.period.start,
      end: widget.period.end,
      type: widget.moneyType,
    );
    final async = ref.watch(rankFullTransactionsProvider(query));

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: Text(_batchMode ? '已选 ${_selectedIds.length}' : _title),
        leading: _batchMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _batchMode = false;
                  _selectedIds.clear();
                }),
              )
            : null,
        actions: [
          if (_batchMode && async.hasValue)
            TextButton(
              onPressed: () {
                final results = _sorted(async.requireValue);
                setState(() {
                  if (_selectedIds.length == results.length) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds
                      ..clear()
                      ..addAll(results.map((e) => e.tx.id));
                  }
                });
              },
              child: const Text('全选'),
            ),
          if (_batchMode)
            TextButton(
              onPressed: _selectedIds.isEmpty ? null : _batchDelete,
              child: const Text(
                '删除',
                style: TextStyle(color: PigTokens.danger),
              ),
            ),
        ],
      ),
      body: async.when(
        loading: () => const AppLoading(message: '加载排行…'),
        error: (e, _) => AppErrorState(
          message: '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(rankFullTransactionsProvider(query)),
        ),
        data: (raw) {
          final items = _sorted(raw);
          return Column(
            children: [
              Material(
                color: PigTokens.surface,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        PigTokens.spaceLg,
                        PigTokens.spaceSm,
                        PigTokens.spaceSm,
                        PigTokens.spaceSm,
                      ),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () =>
                                setState(() => _ascending = !_ascending),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _ascending ? '金额从小到大' : '金额从大到小',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.swap_vert, size: 18),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (!_batchMode)
                            IconButton(
                              tooltip: '批量',
                              onPressed: items.isEmpty
                                  ? null
                                  : () => setState(() => _batchMode = true),
                              icon: const Icon(Icons.checklist_rtl),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: PigTokens.spaceMd,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SummaryCol(
                              label: '总支出(元)',
                              value: formatMoney(widget.expenseTotal),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: const Color(0xFFE5E7EB),
                          ),
                          Expanded(
                            child: _SummaryCol(
                              label: '总收入(元)',
                              value: formatMoney(widget.incomeTotal),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: const Color(0xFFE5E7EB),
                          ),
                          Expanded(
                            child: _SummaryCol(
                              label: '共计',
                              value: '${items.length}笔',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(message: '暂无排行数据')
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                          top: PigTokens.spaceSm,
                          bottom: PigTokens.spaceXl,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final id = item.tx.id;
                          return ReportRankTile.fromListItem(
                            item: item,
                            moneyType: widget.moneyType,
                            selected: _selectedIds.contains(id),
                            showCheckbox: _batchMode,
                            onToggleSelect: () {
                              setState(() {
                                if (_selectedIds.contains(id)) {
                                  _selectedIds.remove(id);
                                } else {
                                  _selectedIds.add(id);
                                }
                              });
                            },
                            onTap: () => showRecordEditorSheet(
                              context,
                              transactionId: id,
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

class _SummaryCol extends StatelessWidget {
  const _SummaryCol({required this.label, required this.value});

  final String label;
  final String value;

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
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
