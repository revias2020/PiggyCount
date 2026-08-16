import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/statistics_repository.dart';
import '../../providers/ai_providers.dart';
import '../../providers/report_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/report_period.dart';
import '../../widgets/ai_fab.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_status.dart';
import '../../widgets/report/report_compare_chart.dart';
import '../../widgets/report/report_composition_card.dart';
import '../../widgets/report/report_rank_list.dart';
import '../../widgets/report/report_summary_card.dart';
import '../../widgets/report/report_trend_chart.dart';
import '../ai/ai_chat_page.dart';
import '../transaction/record_editor_sheet.dart';

/// 「报表」：周/月/年/自定义 + 汇总/趋势/构成/对比/排行。
///
/// 布局对照 docs/assets fig4、fig6；不含「订阅设置」。
class ReportPage extends ConsumerWidget {
  const ReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(reportScopeProvider);
    final moneyType = ref.watch(reportMoneyTypeProvider);
    final period = ref.watch(reportPeriodProvider);
    final asyncSnap = ref.watch(reportSnapshotProvider);
    final dim = ref.watch(compositionDimProvider);
    final aiEnabled =
        ref.watch(aiAssistantEnabledProvider).valueOrNull ?? true;

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScopeTabs(
              scope: scope,
              onChanged: (s) {
                ref.read(reportScopeProvider.notifier).state = s;
                if (s != ReportScope.custom) {
                  ref.read(reportAnchorProvider.notifier).state =
                      DateTime.now();
                }
              },
            ),
            _PeriodAndTypeBar(
              scope: scope,
              period: period,
              moneyType: moneyType,
              onPrev: () => _shiftPeriod(ref, -1),
              onNext: () => _shiftPeriod(ref, 1),
              onPickPeriod: () => _pickPeriod(context, ref),
              onTypeChanged: (t) {
                ref.read(reportMoneyTypeProvider.notifier).state = t;
              },
            ),
            Expanded(
              child: asyncSnap.when(
                // 再显刷新时保留旧快照，避免整页闪骨架（ADR-005）。
                skipLoadingOnReload: true,
                skipLoadingOnRefresh: true,
                loading: () => const AppLoading(message: '加载报表…'),
                error: (e, _) => AppErrorState(
                  message: '报表加载失败，请稍后重试',
                  onRetry: () => ref.invalidate(reportSnapshotProvider),
                ),
                data: (snap) {
                  if (snap == null) {
                    return const EmptyState(
                      icon: Icons.pie_chart_outline,
                      message: '暂无报表数据',
                      detail: '请先选择账本',
                    );
                  }
                  final empty = snap.periodTotal <= 0 &&
                      snap.incomeTotal <= 0 &&
                      snap.expenseTotal <= 0;
                  if (empty) {
                    return const EmptyState(
                      icon: Icons.pie_chart_outline,
                      message: '暂无报表数据',
                      detail: '记几笔账之后这里会展示趋势与分类构成',
                    );
                  }
                  return _ReportBody(
                    scope: scope,
                    period: period,
                    moneyType: moneyType,
                    dim: dim,
                    snap: snap,
                    onDimChanged: (d) {
                      ref.read(compositionDimProvider.notifier).state = d;
                    },
                  );
                },
              ),
            ),
          ],
        ),
        if (aiEnabled)
          AiFab(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AiChatPage()),
              );
            },
          ),
      ],
    );
  }

  void _shiftPeriod(WidgetRef ref, int direction) {
    final scope = ref.read(reportScopeProvider);
    if (scope == ReportScope.custom) return;
    final period = ref.read(reportPeriodProvider);
    final next = direction < 0 ? period.previous : period.next;
    ref.read(reportAnchorProvider.notifier).state = next.anchor;
  }

  Future<void> _pickPeriod(BuildContext context, WidgetRef ref) async {
    final scope = ref.read(reportScopeProvider);
    if (scope == ReportScope.custom) {
      await _pickCustomRange(context, ref);
      return;
    }
    final anchor = ref.read(reportAnchorProvider);
    if (scope == ReportScope.year) {
      final picked = await showDatePicker(
        context: context,
        initialDate: anchor,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: '选择年份（取该日所在年）',
      );
      if (picked != null) {
        ref.read(reportAnchorProvider.notifier).state = picked;
      }
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: scope == ReportScope.week ? '选择周内任意一天' : '选择月份（取该日所在月）',
    );
    if (picked != null) {
      ref.read(reportAnchorProvider.notifier).state = picked;
    }
  }

  Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
    final start = ref.read(reportCustomStartProvider);
    final end = ref.read(reportCustomEndProvider);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: start, end: end),
      helpText: '选择自定义区间',
    );
    if (range != null) {
      ref.read(reportCustomStartProvider.notifier).state = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      ref.read(reportCustomEndProvider.notifier).state = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
      );
    }
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.scope,
    required this.period,
    required this.moneyType,
    required this.dim,
    required this.snap,
    required this.onDimChanged,
  });

  final ReportScope scope;
  final ReportPeriod period;
  final ReportMoneyType moneyType;
  final CompositionDim dim;
  final ReportSnapshot snap;
  final ValueChanged<CompositionDim> onDimChanged;

  @override
  Widget build(BuildContext context) {
    final typeLabel = moneyType == ReportMoneyType.expense ? '支出' : '收入';
    final periodLabel = _periodShortLabel(scope, period);
    final slices = switch (dim) {
      CompositionDim.mainCategory => snap.mainComposition,
      CompositionDim.subCategory => snap.subComposition,
      CompositionDim.tag => snap.tagComposition,
    };
    final compareTitle = switch (scope) {
      ReportScope.week => '近几周$typeLabel对比',
      ReportScope.month => '月$typeLabel对比',
      ReportScope.year => '近几年$typeLabel对比',
      ReportScope.custom => '',
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        ReportSummaryCard(
          scope: scope,
          moneyType: moneyType,
          periodTotal: snap.periodTotal,
          dayCount: period.dayCount,
          periodDelta: snap.periodDelta,
          balance: snap.balance,
        ),
        ReportTrendChart(
          title: '$periodLabel$typeLabel趋势',
          points: snap.trend,
          moneyType: moneyType,
        ),
        ReportCompositionCard(
          title: '$periodLabel$typeLabel分类构成',
          slices: slices,
          total: snap.periodTotal,
          dim: dim,
          onDimChanged: onDimChanged,
          moneyType: moneyType,
        ),
        if (snap.compareSeries.isNotEmpty)
          ReportCompareChart(
            title: compareTitle,
            points: snap.compareSeries,
            highlightStart: period.start,
          ),
        ReportRankList(
          title: '$periodLabel$typeLabel排行',
          items: snap.ranking,
          moneyType: moneyType,
          onTap: (item) => showRecordEditorSheet(
            context,
            transactionId: item.id,
          ),
        ),
      ],
    );
  }

  String _periodShortLabel(ReportScope scope, ReportPeriod period) {
    switch (scope) {
      case ReportScope.week:
        return '本周';
      case ReportScope.month:
        return '${period.anchor.month}月';
      case ReportScope.year:
        return '${period.anchor.year}年';
      case ReportScope.custom:
        return '本期';
    }
  }
}

class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({required this.scope, required this.onChanged});

  final ReportScope scope;
  final ValueChanged<ReportScope> onChanged;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (ReportScope.week, '周报'),
      (ReportScope.month, '月报'),
      (ReportScope.year, '年报'),
      (ReportScope.custom, '自定义'),
    ];
    return Material(
      color: PigTokens.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PigTokens.spaceSm),
        child: Row(
          children: [
            for (final t in tabs)
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(t.$1),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: PigTokens.spaceMd,
                        ),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: scope == t.$1
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: scope == t.$1
                                ? PigTokens.primary
                                : PigTokens.textSecondary,
                          ),
                          child: Text(t.$2, textAlign: TextAlign.center),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: scope == t.$1
                              ? PigTokens.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodAndTypeBar extends StatelessWidget {
  const _PeriodAndTypeBar({
    required this.scope,
    required this.period,
    required this.moneyType,
    required this.onPrev,
    required this.onNext,
    required this.onPickPeriod,
    required this.onTypeChanged,
  });

  final ReportScope scope;
  final ReportPeriod period;
  final ReportMoneyType moneyType;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPickPeriod;
  final ValueChanged<ReportMoneyType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PigTokens.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PigTokens.spaceXs,
          0,
          PigTokens.spaceMd,
          PigTokens.spaceMd,
        ),
        child: Row(
          children: [
            if (scope != ReportScope.custom)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
              )
            else
              const SizedBox(width: PigTokens.spaceSm),
            Expanded(
              child: GestureDetector(
                onTap: onPickPeriod,
                child: Text(
                  _label(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: PigTokens.textPrimary,
                  ),
                ),
              ),
            ),
            if (scope != ReportScope.custom)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              )
            else
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onPickPeriod,
                icon: const Icon(Icons.date_range, size: 20),
              ),
            const SizedBox(width: PigTokens.spaceXs),
            _TypeToggle(value: moneyType, onChanged: onTypeChanged),
          ],
        ),
      ),
    );
  }

  String _label() {
    final now = DateTime.now();
    switch (scope) {
      case ReportScope.week:
        final start = period.start;
        final endInclusive = period.end.subtract(const Duration(days: 1));
        final isThisWeek =
            !now.isBefore(period.start) && now.isBefore(period.end);
        final range =
            '${start.month}/${start.day}-${endInclusive.month}/${endInclusive.day}';
        return isThisWeek ? '$range(本周)' : range;
      case ReportScope.month:
        return DateFormat('y年 M月').format(period.anchor);
      case ReportScope.year:
        return '${period.anchor.year}年';
      case ReportScope.custom:
        final s = period.start;
        final e = period.end.subtract(const Duration(days: 1));
        return '${s.month}/${s.day} - ${e.month}/${e.day}';
    }
  }
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.value, required this.onChanged});

  final ReportMoneyType value;
  final ValueChanged<ReportMoneyType> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, ReportMoneyType t) {
      final selected = value == t;
      return GestureDetector(
        onTap: () => onChanged(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: PigTokens.spaceMd,
            vertical: PigTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            color: selected ? PigTokens.primary : PigTokens.surfaceSecondary,
            borderRadius: BorderRadius.circular(PigTokens.radiusCard - 4),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected
                  ? PigTokens.textOnPrimary
                  : PigTokens.textSecondary,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        cell('支出', ReportMoneyType.expense),
        const SizedBox(width: PigTokens.spaceXs),
        cell('收入', ReportMoneyType.income),
      ],
    );
  }
}
