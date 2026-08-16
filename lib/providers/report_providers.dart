import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/statistics_repository.dart';
import '../utils/report_period.dart';
import 'database_provider.dart';
import 'ledger_session_provider.dart';
import 'tab_index_provider.dart';

/// 报表周期类型（周/月/年/自定义）。
final reportScopeProvider = StateProvider<ReportScope>((ref) => ReportScope.month);

/// 支出 / 收入视角。
final reportMoneyTypeProvider =
    StateProvider<ReportMoneyType>((ref) => ReportMoneyType.expense);

/// 构成图维度。
final compositionDimProvider =
    StateProvider<CompositionDim>((ref) => CompositionDim.mainCategory);

/// 当前浏览锚点（切换周月年时用于定位）。
final reportAnchorProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// 自定义区间起点（含）。
final reportCustomStartProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

/// 自定义区间终点（含当天，查询时转成次日 0 点半开）。
final reportCustomEndProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// 由 scope + anchor / custom 拼出的当前周期。
final reportPeriodProvider = Provider<ReportPeriod>((ref) {
  final scope = ref.watch(reportScopeProvider);
  if (scope == ReportScope.custom) {
    final start = ref.watch(reportCustomStartProvider);
    final endInclusive = ref.watch(reportCustomEndProvider);
    return ReportPeriod.custom(
      startInclusive: start,
      endExclusive: endInclusive.add(const Duration(days: 1)),
    );
  }
  return ReportPeriod.fromScope(scope, ref.watch(reportAnchorProvider));
});

/// 报表数据；账本或周期/类型变化时重新拉取。
final reportSnapshotProvider = FutureProvider<ReportSnapshot?>((ref) async {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  if (ledgerId == null) return null;
  final period = ref.watch(reportPeriodProvider);
  final type = ref.watch(reportMoneyTypeProvider);
  return ref.watch(statisticsRepositoryProvider).loadReport(
        ledgerId: ledgerId,
        period: period,
        type: type,
      );
});

/// 账单变更后报表快照是否过期（ADR-005 报表再显刷新）。
final reportSnapshotDirtyProvider = StateProvider<bool>((ref) => false);

void _reloadReportIfDirty(Ref ref) {
  if (!ref.read(reportSnapshotDirtyProvider)) return;
  ref.read(reportSnapshotDirtyProvider.notifier).state = false;
  ref.invalidate(reportSnapshotProvider);
}

void _onBillChanged(Ref ref) {
  ref.read(reportSnapshotDirtyProvider.notifier).state = true;
  // 报表 Tab 已选中（含其上盖着编辑/AI 页）时立刻重算。
  if (ref.read(tabIndexProvider) == 1) {
    _reloadReportIfDirty(ref);
  }
}

/// 绑定账单变更与 Tab 切换；须在主壳 `watch`，否则无人订阅。
final reportRefreshBinderProvider = Provider<void>((ref) {
  final sub =
      ref.watch(transactionRepositoryProvider).onChanged.listen((_) {
    _onBillChanged(ref);
  });
  ref.onDispose(sub.cancel);

  ref.listen<int>(tabIndexProvider, (prev, next) {
    if (next == 1) _reloadReportIfDirty(ref);
  });
});
