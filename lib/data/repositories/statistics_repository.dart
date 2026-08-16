import 'package:drift/drift.dart';

import '../app_database.dart';
import '../../utils/report_period.dart';

/// 分类构成条目。
class CompositionSlice {
  const CompositionSlice({
    required this.id,
    required this.name,
    this.icon,
    required this.total,
  });

  final int? id;
  final String name;
  final String? icon;
  final double total;
}

/// 趋势折线 / 对比柱状的一个点。
class SeriesPoint {
  const SeriesPoint({
    required this.label,
    required this.value,
    required this.bucketStart,
  });

  final String label;
  final double value;
  final DateTime bucketStart;
}

/// 单笔排行行。
class RankedTransaction {
  const RankedTransaction({
    required this.id,
    required this.amount,
    required this.happenedAt,
    this.categoryName,
    this.categoryIcon,
    this.note,
  });

  final int id;
  final double amount;
  final DateTime happenedAt;
  final String? categoryName;
  final String? categoryIcon;
  final String? note;
}

/// 某一周期的完整报表快照（一次拉取，避免 UI 多路 Future 竞态）。
class ReportSnapshot {
  const ReportSnapshot({
    required this.periodTotal,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.prevPeriodTotal,
    required this.trend,
    required this.mainComposition,
    required this.subComposition,
    required this.tagComposition,
    required this.compareSeries,
    required this.ranking,
  });

  /// 当前视角（支出或收入）合计。
  final double periodTotal;

  final double incomeTotal;
  final double expenseTotal;

  /// 上一周期同视角合计（环比差 = periodTotal − prevPeriodTotal）。
  final double prevPeriodTotal;

  final List<SeriesPoint> trend;
  final List<CompositionSlice> mainComposition;
  final List<CompositionSlice> subComposition;
  final List<CompositionSlice> tagComposition;

  /// 横向对比柱（月报近 6 月；周报近 6 周；年报近 6 年；自定义为空）。
  final List<SeriesPoint> compareSeries;
  final List<RankedTransaction> ranking;

  /// 收支结余 = 收入 − 支出。
  double get balance => incomeTotal - expenseTotal;

  /// 环比差额（正数表示比上期多花/多收）。
  double get periodDelta => periodTotal - prevPeriodTotal;
}

/// 报表聚合查询；按账本 + 半开时间范围过滤。
class StatisticsRepository {
  StatisticsRepository(this._db);

  final AppDatabase _db;

  /// 拉取报表页所需全部数据。
  Future<ReportSnapshot> loadReport({
    required int ledgerId,
    required ReportPeriod period,
    required ReportMoneyType type,
  }) async {
    final typeStr = type == ReportMoneyType.expense ? 'expense' : 'income';

    final incomeTotal = await _sumInRange(
      ledgerId: ledgerId,
      type: 'income',
      start: period.start,
      end: period.end,
    );
    final expenseTotal = await _sumInRange(
      ledgerId: ledgerId,
      type: 'expense',
      start: period.start,
      end: period.end,
    );
    final periodTotal =
        type == ReportMoneyType.expense ? expenseTotal : incomeTotal;

    final prev = period.previous;
    final prevPeriodTotal = await _sumInRange(
      ledgerId: ledgerId,
      type: typeStr,
      start: prev.start,
      end: prev.end,
    );

    final txs = await _listInRange(
      ledgerId: ledgerId,
      type: typeStr,
      start: period.start,
      end: period.end,
    );

    final categories = await _db.select(_db.categories).get();
    final byId = {for (final c in categories) c.id: c};

    return ReportSnapshot(
      periodTotal: periodTotal,
      incomeTotal: incomeTotal,
      expenseTotal: expenseTotal,
      prevPeriodTotal: prevPeriodTotal,
      trend: _buildTrend(period, txs),
      mainComposition: _composeMain(txs, byId),
      subComposition: _composeSub(txs, byId),
      tagComposition: await _composeTags(
        ledgerId: ledgerId,
        type: typeStr,
        start: period.start,
        end: period.end,
      ),
      compareSeries: await _buildCompareSeries(
        ledgerId: ledgerId,
        type: typeStr,
        period: period,
      ),
      ranking: _buildRanking(txs, byId),
    );
  }

  Future<double> _sumInRange({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..where((t) => t.type.equals(type))
          ..where(
            (t) =>
                t.happenedAt.isBiggerOrEqualValue(start) &
                t.happenedAt.isSmallerThanValue(end),
          ))
        .get();
    var sum = 0.0;
    for (final r in rows) {
      sum += r.amount;
    }
    return sum;
  }

  Future<List<Transaction>> _listInRange({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) {
    return (_db.select(_db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..where((t) => t.type.equals(type))
          ..where(
            (t) =>
                t.happenedAt.isBiggerOrEqualValue(start) &
                t.happenedAt.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.amount)]))
        .get();
  }

  List<SeriesPoint> _buildTrend(ReportPeriod period, List<Transaction> txs) {
    switch (period.scope) {
      case ReportScope.week:
      case ReportScope.month:
        return _dailySeries(period.start, period.end, txs);
      case ReportScope.year:
        return _monthlySeriesInYear(period.start.year, txs);
      case ReportScope.custom:
        if (period.dayCount <= 62) {
          return _dailySeries(period.start, period.end, txs);
        }
        return _monthlyBuckets(period.start, period.end, txs);
    }
  }

  List<SeriesPoint> _dailySeries(
    DateTime start,
    DateTime end,
    List<Transaction> txs,
  ) {
    final map = <DateTime, double>{};
    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      map[d] = 0;
    }
    for (final t in txs) {
      final day =
          DateTime(t.happenedAt.year, t.happenedAt.month, t.happenedAt.day);
      if (map.containsKey(day)) {
        map[day] = map[day]! + t.amount;
      }
    }
    return map.entries
        .map(
          (e) => SeriesPoint(
            label: '${e.key.month}/${e.key.day}',
            value: e.value,
            bucketStart: e.key,
          ),
        )
        .toList();
  }

  List<SeriesPoint> _monthlySeriesInYear(int year, List<Transaction> txs) {
    final points = <SeriesPoint>[];
    for (var m = 1; m <= 12; m++) {
      final start = DateTime(year, m);
      var total = 0.0;
      for (final t in txs) {
        if (t.happenedAt.year == year && t.happenedAt.month == m) {
          total += t.amount;
        }
      }
      points.add(SeriesPoint(label: '$m月', value: total, bucketStart: start));
    }
    return points;
  }

  List<SeriesPoint> _monthlyBuckets(
    DateTime start,
    DateTime end,
    List<Transaction> txs,
  ) {
    final points = <SeriesPoint>[];
    var cursor = DateTime(start.year, start.month);
    while (cursor.isBefore(end)) {
      final next = DateTime(cursor.year, cursor.month + 1);
      var total = 0.0;
      for (final t in txs) {
        if (!t.happenedAt.isBefore(start) &&
            t.happenedAt.isBefore(end) &&
            !t.happenedAt.isBefore(cursor) &&
            t.happenedAt.isBefore(next)) {
          total += t.amount;
        }
      }
      points.add(
        SeriesPoint(
          label: '${cursor.year}/${cursor.month}',
          value: total,
          bucketStart: cursor,
        ),
      );
      cursor = next;
    }
    return points;
  }

  List<CompositionSlice> _composeMain(
    List<Transaction> txs,
    Map<int, Category> byId,
  ) {
    final totals = <int?, double>{};
    final names = <int?, String>{};
    final icons = <int?, String?>{};
    for (final t in txs) {
      final cat = t.categoryId == null ? null : byId[t.categoryId];
      late final int? rootId;
      late final String name;
      late final String? icon;
      if (cat == null) {
        rootId = null;
        name = '未分类';
        icon = null;
      } else if (cat.parentId == null) {
        rootId = cat.id;
        name = cat.name;
        icon = cat.icon;
      } else {
        final parent = byId[cat.parentId];
        rootId = parent?.id ?? cat.id;
        name = parent?.name ?? cat.name;
        icon = parent?.icon ?? cat.icon;
      }
      totals.update(rootId, (v) => v + t.amount, ifAbsent: () => t.amount);
      names[rootId] = name;
      icons[rootId] = icon;
    }
    return _sortedSlices(totals, names, icons);
  }

  List<CompositionSlice> _composeSub(
    List<Transaction> txs,
    Map<int, Category> byId,
  ) {
    final totals = <int?, double>{};
    final names = <int?, String>{};
    final icons = <int?, String?>{};
    for (final t in txs) {
      final cat = t.categoryId == null ? null : byId[t.categoryId];
      final id = cat?.id;
      totals.update(id, (v) => v + t.amount, ifAbsent: () => t.amount);
      names[id] = cat?.name ?? '未分类';
      icons[id] = cat?.icon;
    }
    return _sortedSlices(totals, names, icons);
  }

  Future<List<CompositionSlice>> _composeTags({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..where((t) => t.type.equals(type))
          ..where(
            (t) =>
                t.happenedAt.isBiggerOrEqualValue(start) &
                t.happenedAt.isSmallerThanValue(end),
          ))
        .join([
      innerJoin(
        _db.transactionTags,
        _db.transactionTags.transactionId.equalsExp(_db.transactions.id),
      ),
      innerJoin(
        _db.tags,
        _db.tags.id.equalsExp(_db.transactionTags.tagId),
      ),
    ]).get();

    final totals = <int?, double>{};
    final names = <int?, String>{};
    for (final r in rows) {
      final t = r.readTable(_db.transactions);
      final tag = r.readTable(_db.tags);
      totals.update(tag.id, (v) => v + t.amount, ifAbsent: () => t.amount);
      names[tag.id] = tag.name;
    }
    return _sortedSlices(totals, names, const {});
  }

  List<CompositionSlice> _sortedSlices(
    Map<int?, double> totals,
    Map<int?, String> names,
    Map<int?, String?> icons,
  ) {
    final list = totals.entries
        .map(
          (e) => CompositionSlice(
            id: e.key,
            name: names[e.key] ?? '未分类',
            icon: icons[e.key],
            total: e.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  Future<List<SeriesPoint>> _buildCompareSeries({
    required int ledgerId,
    required String type,
    required ReportPeriod period,
  }) async {
    switch (period.scope) {
      case ReportScope.month:
        final points = <SeriesPoint>[];
        final base = period.anchor;
        for (var i = 5; i >= 0; i--) {
          final m = DateTime(base.year, base.month - i);
          final sum = await _sumInRange(
            ledgerId: ledgerId,
            type: type,
            start: m,
            end: DateTime(m.year, m.month + 1),
          );
          points.add(
            SeriesPoint(label: '${m.month}月', value: sum, bucketStart: m),
          );
        }
        return points;
      case ReportScope.week:
        final weeks = <ReportPeriod>[];
        var p = period;
        for (var i = 0; i < 6; i++) {
          weeks.insert(0, p);
          p = p.previous;
        }
        final points = <SeriesPoint>[];
        for (final w in weeks) {
          final sum = await _sumInRange(
            ledgerId: ledgerId,
            type: type,
            start: w.start,
            end: w.end,
          );
          points.add(
            SeriesPoint(
              label: '${w.start.month}/${w.start.day}',
              value: sum,
              bucketStart: w.start,
            ),
          );
        }
        return points;
      case ReportScope.year:
        final points = <SeriesPoint>[];
        final y = period.anchor.year;
        for (var i = 5; i >= 0; i--) {
          final year = y - i;
          final sum = await _sumInRange(
            ledgerId: ledgerId,
            type: type,
            start: DateTime(year),
            end: DateTime(year + 1),
          );
          points.add(
            SeriesPoint(
              label: '$year',
              value: sum,
              bucketStart: DateTime(year),
            ),
          );
        }
        return points;
      case ReportScope.custom:
        return const [];
    }
  }

  List<RankedTransaction> _buildRanking(
    List<Transaction> txs,
    Map<int, Category> byId, {
    int limit = 20,
  }) {
    final sorted = List<Transaction>.from(txs)
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return sorted.take(limit).map((t) {
      final cat = t.categoryId == null ? null : byId[t.categoryId];
      return RankedTransaction(
        id: t.id,
        amount: t.amount,
        happenedAt: t.happenedAt,
        categoryName: cat?.name,
        categoryIcon: cat?.icon,
        note: t.note,
      );
    }).toList();
  }
}
