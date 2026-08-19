import 'dart:convert';

import '../data/repositories/statistics_repository.dart';

/// 近 7 日单日收支（滚动窗，含今日）。
class GlanceDayPoint {
  const GlanceDayPoint({
    required this.day,
    required this.label,
    required this.expense,
    required this.income,
  });

  final DateTime day;
  final String label;
  final double expense;
  final double income;

  Map<String, dynamic> toJson() => {
        'd': day.toIso8601String(),
        'l': label,
        'e': expense,
        'i': income,
      };

  factory GlanceDayPoint.fromJson(Map<String, dynamic> j) {
    return GlanceDayPoint(
      day: DateTime.tryParse(j['d'] as String? ?? '') ?? DateTime.now(),
      label: j['l'] as String? ?? '',
      expense: (j['e'] as num?)?.toDouble() ?? 0,
      income: (j['i'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// 收支速览原始金额 + 近 7 日序列。
class GlanceWidgetData {
  const GlanceWidgetData({
    required this.todayExpenseTotal,
    required this.todayIncomeTotal,
    required this.monthExpenseTotal,
    required this.monthIncomeTotal,
    required this.last7Days,
  });

  final double todayExpenseTotal;
  final double todayIncomeTotal;
  final double monthExpenseTotal;
  final double monthIncomeTotal;
  final List<GlanceDayPoint> last7Days;

  static const empty = GlanceWidgetData(
    todayExpenseTotal: 0,
    todayIncomeTotal: 0,
    monthExpenseTotal: 0,
    monthIncomeTotal: 0,
    last7Days: [],
  );

  String last7DaysJson() =>
      jsonEncode(last7Days.map((e) => e.toJson()).toList());

  static List<GlanceDayPoint> parseLast7DaysJson(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => GlanceDayPoint.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

/// 小组件取数（今日 + 本自然月 + 滚动近 7 日，当前账本）。
abstract final class WidgetDataService {
  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static Future<GlanceWidgetData> gatherGlance({
    required StatisticsRepository stats,
    required int ledgerId,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final monthStart = DateTime(now.year, now.month);
    final monthEnd = DateTime(now.year, now.month + 1);
    final rangeStart = today.subtract(const Duration(days: 6));

    final dayFutures = <Future<GlanceDayPoint>>[];
    for (var i = 0; i < 7; i++) {
      final day = rangeStart.add(Duration(days: i));
      final next = day.add(const Duration(days: 1));
      final isToday = day == today;
      dayFutures.add(() async {
        final results = await Future.wait([
          stats.sumInRange(
            ledgerId: ledgerId,
            type: 'expense',
            start: day,
            end: next,
          ),
          stats.sumInRange(
            ledgerId: ledgerId,
            type: 'income',
            start: day,
            end: next,
          ),
        ]);
        return GlanceDayPoint(
          day: day,
          label: isToday ? '今日' : _weekdays[day.weekday - 1],
          expense: results[0],
          income: results[1],
        );
      }());
    }

    final totals = await Future.wait([
      stats.sumInRange(
        ledgerId: ledgerId,
        type: 'expense',
        start: today,
        end: tomorrow,
      ),
      stats.sumInRange(
        ledgerId: ledgerId,
        type: 'income',
        start: today,
        end: tomorrow,
      ),
      stats.sumInRange(
        ledgerId: ledgerId,
        type: 'expense',
        start: monthStart,
        end: monthEnd,
      ),
      stats.sumInRange(
        ledgerId: ledgerId,
        type: 'income',
        start: monthStart,
        end: monthEnd,
      ),
      Future.wait(dayFutures),
    ]);

    return GlanceWidgetData(
      todayExpenseTotal: totals[0] as double,
      todayIncomeTotal: totals[1] as double,
      monthExpenseTotal: totals[2] as double,
      monthIncomeTotal: totals[3] as double,
      last7Days: totals[4] as List<GlanceDayPoint>,
    );
  }
}
