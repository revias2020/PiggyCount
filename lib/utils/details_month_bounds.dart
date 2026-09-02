/// 明细「浏览月」可选范围：与年月网格一致（今−8 年 … 本月）。
abstract final class DetailsMonthBounds {
  static const yearsBack = 8;

  static DateTime _monthStart(int year, int month) =>
      DateTime(year, month);

  static int _monthKey(DateTime d) => d.year * 12 + d.month;

  static DateTime earliestMonth() {
    final now = DateTime.now();
    return _monthStart(now.year - yearsBack, 1);
  }

  static DateTime latestMonth() {
    final now = DateTime.now();
    return _monthStart(now.year, now.month);
  }

  static bool isFutureMonth(int year, int month) {
    return _monthKey(_monthStart(year, month)) > _monthKey(latestMonth());
  }

  static bool isBeforeEarliest(int year, int month) {
    return _monthKey(_monthStart(year, month)) <
        _monthKey(earliestMonth());
  }

  static bool canGoPrevious(DateTime month) {
    return _monthKey(_monthStart(month.year, month.month)) >
        _monthKey(earliestMonth());
  }

  static bool canGoNext(DateTime month) {
    return _monthKey(_monthStart(month.year, month.month)) <
        _monthKey(latestMonth());
  }

  /// [delta] −1 = 上一月，+1 = 下一月；不可达时返回 null。
  static DateTime? shiftMonth(DateTime month, int delta) {
    if (delta == -1 && !canGoPrevious(month)) return null;
    if (delta == 1 && !canGoNext(month)) return null;
    return _monthStart(month.year, month.month + delta);
  }
}
