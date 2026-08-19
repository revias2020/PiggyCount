/// 报表周期与日期范围计算。
///
/// 所有范围均为半开区间 `[start, end)`，与 Drift 查询约定一致。
library;

/// 周报 / 月报 / 年报 / 自定义。
enum ReportScope { week, month, year, custom }

/// 报表视角：支出或收入（结余在汇总卡单独计算，不做第三视角）。
enum ReportMoneyType { expense, income }

/// 分类构成维度。
enum CompositionDim { mainCategory, subCategory, tag }

/// 某一报表周期的起止与展示用锚点。
class ReportPeriod {
  const ReportPeriod({
    required this.scope,
    required this.start,
    required this.end,
    required this.anchor,
  });

  final ReportScope scope;

  /// 含起点。
  final DateTime start;

  /// 不含终点。
  final DateTime end;

  /// 用于「上一段/下一段」导航的锚点（周=该周内任一天；月=月初；年=年初）。
  final DateTime anchor;

  Duration get duration => end.difference(start);

  /// 用于日均：按自然日数（至少 1，避免除零）。
  int get dayCount {
    final days = end.difference(start).inDays;
    return days <= 0 ? 1 : days;
  }

  /// 上一同长度周期。
  ReportPeriod get previous {
    switch (scope) {
      case ReportScope.week:
        return fromScope(ReportScope.week, anchor.subtract(const Duration(days: 7)));
      case ReportScope.month:
        return fromScope(ReportScope.month, DateTime(anchor.year, anchor.month - 1));
      case ReportScope.year:
        return fromScope(ReportScope.year, DateTime(anchor.year - 1));
      case ReportScope.custom:
        return ReportPeriod(
          scope: ReportScope.custom,
          start: start.subtract(duration),
          end: start,
          anchor: start.subtract(duration),
        );
    }
  }

  /// 下一同长度周期；若会越过「今天所在周期」仍允许浏览（用户可回退）。
  ReportPeriod get next {
    switch (scope) {
      case ReportScope.week:
        return fromScope(ReportScope.week, anchor.add(const Duration(days: 7)));
      case ReportScope.month:
        return fromScope(ReportScope.month, DateTime(anchor.year, anchor.month + 1));
      case ReportScope.year:
        return fromScope(ReportScope.year, DateTime(anchor.year + 1));
      case ReportScope.custom:
        return ReportPeriod(
          scope: ReportScope.custom,
          start: end,
          end: end.add(duration),
          anchor: end,
        );
    }
  }

  /// 由 [scope] + 锚点日期生成标准周期。
  ///
  /// 周报：周一 00:00 ～ 下周一 00:00（ISO 周）。
  static ReportPeriod fromScope(ReportScope scope, DateTime anchor) {
    final day = DateTime(anchor.year, anchor.month, anchor.day);
    switch (scope) {
      case ReportScope.week:
        // DateTime.weekday: Mon=1 … Sun=7
        final monday = day.subtract(Duration(days: day.weekday - 1));
        return ReportPeriod(
          scope: ReportScope.week,
          start: monday,
          end: monday.add(const Duration(days: 7)),
          anchor: monday,
        );
      case ReportScope.month:
        final start = DateTime(day.year, day.month);
        return ReportPeriod(
          scope: ReportScope.month,
          start: start,
          end: DateTime(day.year, day.month + 1),
          anchor: start,
        );
      case ReportScope.year:
        final start = DateTime(day.year);
        return ReportPeriod(
          scope: ReportScope.year,
          start: start,
          end: DateTime(day.year + 1),
          anchor: start,
        );
      case ReportScope.custom:
        // 自定义默认：当月；真正自定义由 [custom] 工厂写入。
        return fromScope(ReportScope.month, day);
    }
  }

  /// 自定义半开区间；[endExclusive] 若为某一天的 0 点，表示含前一天。
  factory ReportPeriod.custom({
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) {
    final start = DateTime(
      startInclusive.year,
      startInclusive.month,
      startInclusive.day,
    );
    var end = DateTime(
      endExclusive.year,
      endExclusive.month,
      endExclusive.day,
    );
    if (!end.isAfter(start)) {
      end = start.add(const Duration(days: 1));
    }
    return ReportPeriod(
      scope: ReportScope.custom,
      start: start,
      end: end,
      anchor: start,
    );
  }
}

/// 报表标题用周期文案（如「2026年8月」「本周」「2026年」）。
String formatReportPeriodTitle(ReportPeriod period) {
  switch (period.scope) {
    case ReportScope.week:
      final endDay = period.end.subtract(const Duration(days: 1));
      return '${period.start.month}/${period.start.day}'
          '–${endDay.month}/${endDay.day}';
    case ReportScope.month:
      return '${period.anchor.year}年${period.anchor.month}月';
    case ReportScope.year:
      return '${period.anchor.year}年';
    case ReportScope.custom:
      final endDay = period.end.subtract(const Duration(days: 1));
      if (period.start.year == endDay.year &&
          period.start.month == endDay.month &&
          period.start.day == endDay.day) {
        return '${period.start.year}/${period.start.month}/${period.start.day}';
      }
      return '${period.start.year}/${period.start.month}/${period.start.day}'
          '–${endDay.year}/${endDay.month}/${endDay.day}';
  }
}
