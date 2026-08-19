import 'package:drift/drift.dart';

import '../app_database.dart';
import '../../utils/report_period.dart';

/// 分类构成条目。
class CompositionSlice {
  const CompositionSlice({
    required this.id,
    required this.name,
    this.icon,
    this.iconType = 'material',
    this.customIconPath,
    this.color,
    required this.total,
    this.txCount = 0,
  });

  final int? id;
  final String name;
  final String? icon;
  /// 与分类管理一致：`material` / `custom`（ADR-037）。
  final String iconType;
  final String? customIconPath;
  /// 标签维：标签色 hex；分类维一般为空。
  final String? color;
  final double total;
  /// 该切片对应笔数（ADR-033 构成分类列表）。
  final int txCount;
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
class RankTagLabel {
  const RankTagLabel({required this.name, this.color});

  final String name;
  final String? color;
}

class RankedTransaction {
  const RankedTransaction({
    required this.id,
    required this.amount,
    required this.happenedAt,
    this.categoryName,
    this.categoryIcon,
    this.categoryIconType = 'material',
    this.categoryCustomIconPath,
    this.note,
    this.tags = const [],
  });

  final int id;
  final double amount;
  final DateTime happenedAt;
  final String? categoryName;
  final String? categoryIcon;
  final String categoryIconType;
  final String? categoryCustomIconPath;
  final String? note;
  /// 该笔全部标签（ADR-036）。
  final List<RankTagLabel> tags;
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

    final incomeTotal = await sumInRange(
      ledgerId: ledgerId,
      type: 'income',
      start: period.start,
      end: period.end,
    );
    final expenseTotal = await sumInRange(
      ledgerId: ledgerId,
      type: 'expense',
      start: period.start,
      end: period.end,
    );
    final periodTotal =
        type == ReportMoneyType.expense ? expenseTotal : incomeTotal;

    final prev = period.previous;
    final prevPeriodTotal = await sumInRange(
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
      ranking: await _buildRanking(txs, byId, limit: 10),
    );
  }

  /// 半开区间 [start, end) 合计；桌面小组件等复用。
  Future<double> sumInRange({
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
    final counts = <int?, int>{};
    final names = <int?, String>{};
    final icons = <int?, String?>{};
    final iconTypes = <int?, String>{};
    final customPaths = <int?, String?>{};
    for (final t in txs) {
      final cat = t.categoryId == null ? null : byId[t.categoryId];
      late final int? rootId;
      late final String name;
      late final String? icon;
      late final String iconType;
      late final String? customPath;
      if (cat == null) {
        rootId = null;
        name = '未分类';
        icon = null;
        iconType = 'material';
        customPath = null;
      } else if (cat.parentId == null) {
        rootId = cat.id;
        name = cat.name;
        icon = cat.icon;
        iconType = cat.iconType;
        customPath = cat.customIconPath;
      } else {
        final parent = byId[cat.parentId];
        rootId = parent?.id ?? cat.id;
        name = parent?.name ?? cat.name;
        icon = parent?.icon ?? cat.icon;
        iconType = parent?.iconType ?? cat.iconType;
        customPath = parent?.customIconPath ?? cat.customIconPath;
      }
      totals.update(rootId, (v) => v + t.amount, ifAbsent: () => t.amount);
      counts.update(rootId, (v) => v + 1, ifAbsent: () => 1);
      names[rootId] = name;
      icons[rootId] = icon;
      iconTypes[rootId] = iconType;
      customPaths[rootId] = customPath;
    }
    return _sortedSlices(
      totals,
      names,
      icons,
      iconTypes: iconTypes,
      customPaths: customPaths,
      counts: counts,
    );
  }

  List<CompositionSlice> _composeSub(
    List<Transaction> txs,
    Map<int, Category> byId,
  ) {
    final totals = <int?, double>{};
    final counts = <int?, int>{};
    final names = <int?, String>{};
    final icons = <int?, String?>{};
    final iconTypes = <int?, String>{};
    final customPaths = <int?, String?>{};
    for (final t in txs) {
      final cat = t.categoryId == null ? null : byId[t.categoryId];
      final id = cat?.id;
      totals.update(id, (v) => v + t.amount, ifAbsent: () => t.amount);
      counts.update(id, (v) => v + 1, ifAbsent: () => 1);
      if (cat == null) {
        names[id] = '未分类';
        icons[id] = null;
        iconTypes[id] = 'material';
        customPaths[id] = null;
      } else if (cat.parentId != null) {
        final parent = byId[cat.parentId];
        names[id] = parent == null ? cat.name : '${parent.name}-${cat.name}';
        icons[id] = cat.icon;
        iconTypes[id] = cat.iconType;
        customPaths[id] = cat.customIconPath;
      } else {
        names[id] = cat.name;
        icons[id] = cat.icon;
        iconTypes[id] = cat.iconType;
        customPaths[id] = cat.customIconPath;
      }
    }
    return _sortedSlices(
      totals,
      names,
      icons,
      iconTypes: iconTypes,
      customPaths: customPaths,
      counts: counts,
    );
  }

  Future<List<CompositionSlice>> _composeTags({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final txs = await (_db.select(_db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..where((t) => t.type.equals(type))
          ..where(
            (t) =>
                t.happenedAt.isBiggerOrEqualValue(start) &
                t.happenedAt.isSmallerThanValue(end),
          ))
        .get();

    final totals = <int?, double>{};
    final counts = <int?, int>{};
    final names = <int?, String>{};
    final colors = <int?, String?>{};

    if (txs.isEmpty) {
      return const [];
    }

    final txIds = txs.map((t) => t.id).toList();
    final linkRows = await (_db.select(_db.transactionTags)
          ..where((t) => t.transactionId.isIn(txIds)))
        .get();
    final tagIds = <int>{};
    final tagsByTx = <int, List<int>>{};
    for (final link in linkRows) {
      tagIds.add(link.tagId);
      tagsByTx.putIfAbsent(link.transactionId, () => []).add(link.tagId);
    }

    final tagRows = tagIds.isEmpty
        ? <Tag>[]
        : await (_db.select(_db.tags)..where((t) => t.id.isIn(tagIds))).get();
    final tagById = {for (final t in tagRows) t.id: t};

    for (final t in txs) {
      final ids = tagsByTx[t.id];
      if (ids == null || ids.isEmpty) {
        totals.update(null, (v) => v + t.amount, ifAbsent: () => t.amount);
        counts.update(null, (v) => v + 1, ifAbsent: () => 1);
        names[null] = '未标注';
        colors[null] = null;
        continue;
      }
      for (final tagId in ids) {
        final tag = tagById[tagId];
        if (tag == null) continue;
        totals.update(tag.id, (v) => v + t.amount, ifAbsent: () => t.amount);
        counts.update(tag.id, (v) => v + 1, ifAbsent: () => 1);
        names[tag.id] = tag.name;
        colors[tag.id] = tag.color;
      }
    }

    return _sortedSlices(totals, names, const {}, counts: counts, colors: colors);
  }

  List<CompositionSlice> _sortedSlices(
    Map<int?, double> totals,
    Map<int?, String> names,
    Map<int?, String?> icons, {
    Map<int?, String> iconTypes = const {},
    Map<int?, String?> customPaths = const {},
    Map<int?, int> counts = const {},
    Map<int?, String?> colors = const {},
  }) {
    final list = totals.entries
        .map(
          (e) => CompositionSlice(
            id: e.key,
            name: names[e.key] ?? '未分类',
            icon: icons[e.key],
            iconType: iconTypes[e.key] ?? 'material',
            customIconPath: customPaths[e.key],
            color: colors[e.key],
            total: e.value,
            txCount: counts[e.key] ?? 0,
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
          final sum = await sumInRange(
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
          final sum = await sumInRange(
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
          final sum = await sumInRange(
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

  Future<List<RankedTransaction>> _buildRanking(
    List<Transaction> txs,
    Map<int, Category> byId, {
    int limit = 10,
  }) async {
    final sorted = List<Transaction>.from(txs)
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final top = sorted.take(limit).toList();
    final tagMap = await _tagsByTransactionIds(top.map((t) => t.id).toList());
    return top.map((t) {
      final cat = t.categoryId == null ? null : byId[t.categoryId];
      return RankedTransaction(
        id: t.id,
        amount: t.amount,
        happenedAt: t.happenedAt,
        categoryName: cat?.name,
        categoryIcon: cat?.icon,
        categoryIconType: cat?.iconType ?? 'material',
        categoryCustomIconPath: cat?.customIconPath,
        note: t.note,
        tags: tagMap[t.id] ?? const [],
      );
    }).toList();
  }

  /// 每笔流水的全部标签名/色（排行展示用，ADR-036）。
  Future<Map<int, List<RankTagLabel>>> _tagsByTransactionIds(
    List<int> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(_db.transactionTags).join([
          innerJoin(
            _db.tags,
            _db.tags.id.equalsExp(_db.transactionTags.tagId),
          ),
        ])
          ..where(_db.transactionTags.transactionId.isIn(ids)))
        .get();
    final map = <int, List<RankTagLabel>>{};
    for (final row in rows) {
      final link = row.readTable(_db.transactionTags);
      final tag = row.readTable(_db.tags);
      map
          .putIfAbsent(link.transactionId, () => <RankTagLabel>[])
          .add(RankTagLabel(name: tag.name, color: tag.color));
    }
    return map;
  }
}
