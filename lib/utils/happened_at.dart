/// 账单时间（发生时刻）工具：存到秒、界面到分（ADR-042）。
abstract final class HappenedAt {
  /// 去掉毫秒，保留到秒。
  static DateTime toSecond(DateTime value) {
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    );
  }

  /// 此刻，到秒。
  static DateTime now() => toSecond(DateTime.now());

  /// 改日期：换年月日，保留原时分秒。
  static DateTime withDate(DateTime current, DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      current.hour,
      current.minute,
      current.second,
    );
  }

  /// 改时间：换时分，保留原秒。
  static DateTime withHourMinute(DateTime current, int hour, int minute) {
    return DateTime(
      current.year,
      current.month,
      current.day,
      hour,
      minute,
      current.second,
    );
  }

  /// 日历「在该日记账」：选中日 + 此刻时分秒。
  static DateTime onCalendarDay(DateTime day) {
    final n = DateTime.now();
    return DateTime(
      day.year,
      day.month,
      day.day,
      n.hour,
      n.minute,
      n.second,
    );
  }
}
