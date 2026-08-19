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
import '../../widgets/report/report_compare_rank_card.dart';
import '../../widgets/report/report_composition_card.dart';
import '../../widgets/report/report_period_pickers.dart';
import '../../widgets/report/report_summary_card.dart';
import '../../widgets/report/report_trend_chart.dart';
import '../ai/ai_chat_page.dart';
import '../transaction/category_detail_page.dart';
import '../transaction/rank_full_page.dart';
import '../transaction/record_editor_sheet.dart';
import '../transaction/tag_detail_page.dart';

/// 「报表」：周/月/年/自定义 + 汇总/趋势/构成/对比/排行。
///
/// 报表主页：周期切换、汇总与图表卡；不含「订阅设置」。
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
    DateTime? picked;
    switch (scope) {
      case ReportScope.week:
        picked = await showReportWeekPicker(
          context,
          initialAnchor: anchor,
        );
      case ReportScope.month:
        picked = await showReportMonthPicker(
          context,
          initialMonth: anchor,
        );
      case ReportScope.year:
        picked = await showReportYearPicker(
          context,
          initialYear: anchor,
        );
      case ReportScope.custom:
        return;
    }
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
          onSliceTap: (slice) => _openCompositionDetail(context, slice),
        ),
        ReportCompareRankCard(
          compareTitle: compareTitle,
          rankTitle: '$periodLabel$typeLabel排行',
          comparePoints: snap.compareSeries,
          highlightStart: period.start,
          rankItems: snap.ranking,
          moneyType: moneyType,
          onRankTap: (item) => showRecordEditorSheet(
            context,
            transactionId: item.id,
          ),
          onViewAll: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RankFullPage(
                  period: period,
                  moneyType: moneyType,
                  expenseTotal: snap.expenseTotal,
                  incomeTotal: snap.incomeTotal,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _openCompositionDetail(BuildContext context, CompositionSlice slice) {
    if (dim == CompositionDim.tag) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TagDetailPage(
            tagId: slice.id,
            tagName: slice.name,
            lockedPeriod: period,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryDetailPage(
          categoryId: slice.id,
          categoryName: slice.name,
          lockedPeriod: period,
          includeChildren: dim == CompositionDim.mainCategory && slice.id != null,
        ),
      ),
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: PigTokens.spaceMd,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: scope == t.$1
                                ? FontWeight.w700
                                : FontWeight.w500,
                            // 选中近黑加粗，短蓝线承担聚焦色（跟参考图）。
                            color: scope == t.$1
                                ? PigTokens.textPrimary
                                : PigTokens.textSecondary,
                          ),
                          child: Text(t.$2, textAlign: TextAlign.center),
                        ),
                        const SizedBox(height: 6),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          // 约文字宽度 40–50%，不铺满 Tab 格、也不铺满整段字。
                          width: scope == t.$1 ? 18 : 0,
                          height: 3,
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
          PigTokens.spaceMd,
          0,
          PigTokens.spaceMd,
          PigTokens.spaceMd,
        ),
        child: Row(
          children: [
            _CompactPeriodSwitcher(
              label: _label(),
              showArrows: scope != ReportScope.custom,
              onPrev: onPrev,
              onNext: onNext,
              onTapLabel: onPickPeriod,
            ),
            const Spacer(),
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
        return DateFormat('y年M月').format(period.anchor);
      case ReportScope.year:
        return '${period.anchor.year}年';
      case ReportScope.custom:
        final s = period.start;
        final e = period.end.subtract(const Duration(days: 1));
        return '${s.month}/${s.day} - ${e.month}/${e.day}';
    }
  }
}

/// 靠左紧凑 `< 文案 >`（ADR-016）；自定义无箭头，仅点文案。
class _CompactPeriodSwitcher extends StatelessWidget {
  const _CompactPeriodSwitcher({
    required this.label,
    required this.showArrows,
    required this.onPrev,
    required this.onNext,
    required this.onTapLabel,
  });

  final String label;
  final bool showArrows;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onTapLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PigTokens.surfaceSecondary,
      borderRadius: BorderRadius.circular(PigTokens.radiusPill),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showArrows)
              _CompactChevron(icon: Icons.chevron_left, onTap: onPrev),
            GestureDetector(
              onTap: onTapLabel,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: showArrows ? PigTokens.spaceXs : PigTokens.spaceMd,
                  vertical: PigTokens.spaceSm,
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: PigTokens.textPrimary,
                  ),
                ),
              ),
            ),
            if (showArrows)
              _CompactChevron(icon: Icons.chevron_right, onTap: onNext)
            else
              Padding(
                padding: const EdgeInsets.only(right: PigTokens.spaceSm),
                child: IconButton(
                  onPressed: onTapLabel,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  icon: const Icon(
                    Icons.date_range,
                    size: 18,
                    color: PigTokens.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactChevron extends StatelessWidget {
  const _CompactChevron({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 20, color: PigTokens.textSecondary),
      ),
    );
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
