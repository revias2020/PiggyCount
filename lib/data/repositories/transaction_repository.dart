import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../utils/bill_fingerprint.dart';
import '../../utils/happened_at.dart';
import '../app_database.dart';

/// 列表展示用的账单标签摘要（id + 名 + 色）。
class ListTagLabel {
  const ListTagLabel({
    required this.id,
    required this.name,
    required this.color,
  });

  final int id;
  final String name;
  final String color;
}

/// 列表展示用的账单聚合行（含分类名与标签）。
class TransactionListItem {
  const TransactionListItem({
    required this.tx,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    this.categoryIconType = 'material',
    this.categoryCustomIconPath,
    this.categoryParentId,
    this.tags = const [],
  });

  final Transaction tx;
  final int? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final String categoryIconType;
  final String? categoryCustomIconPath;
  /// 子分类时为所属主分类 id；主分类或未分类时为 null。
  final int? categoryParentId;
  final List<ListTagLabel> tags;

  List<String> get tagNames => [for (final t in tags) t.name];
}

/// 某一自然日的账单分组（含日汇总，供明细列表直接渲染）。
class DayTransactionGroup {
  const DayTransactionGroup({
    required this.day,
    required this.items,
    required this.expense,
    required this.income,
  });

  final DateTime day;
  final List<TransactionListItem> items;
  final double expense;
  final double income;
}

/// 某月明细视图模型：月汇总 + 按日倒序分组，避免在 Widget build 里重复计算。
class MonthLedgerView {
  const MonthLedgerView({
    required this.monthExpense,
    required this.monthIncome,
    required this.days,
  });

  final double monthExpense;
  final double monthIncome;
  final List<DayTransactionGroup> days;

  bool get isEmpty => days.isEmpty;

  /// 从扁平列表预计算分组与汇总。
  factory MonthLedgerView.fromItems(List<TransactionListItem> items) {
    if (items.isEmpty) {
      return const MonthLedgerView(
        monthExpense: 0,
        monthIncome: 0,
        days: [],
      );
    }

    var monthExpense = 0.0;
    var monthIncome = 0.0;
    final buckets = <DateTime, List<TransactionListItem>>{};

    for (final item in items) {
      final happened = item.tx.happenedAt;
      final day = DateTime(happened.year, happened.month, happened.day);
      buckets.putIfAbsent(day, () => []).add(item);
      if (item.tx.type == 'expense') {
        monthExpense += item.tx.amount;
      } else {
        monthIncome += item.tx.amount;
      }
    }

    final dayKeys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    final days = <DayTransactionGroup>[];
    for (final day in dayKeys) {
      final dayItems = buckets[day]!;
      var expense = 0.0;
      var income = 0.0;
      for (final i in dayItems) {
        if (i.tx.type == 'expense') {
          expense += i.tx.amount;
        } else {
          income += i.tx.amount;
        }
      }
      days.add(
        DayTransactionGroup(
          day: day,
          items: dayItems,
          expense: expense,
          income: income,
        ),
      );
    }

    return MonthLedgerView(
      monthExpense: monthExpense,
      monthIncome: monthIncome,
      days: days,
    );
  }
}

/// 账单 CRUD 与按月查询。
class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  final _changed = StreamController<void>.broadcast();

  /// 任意账单增删改成功后发出（供报表再显刷新等订阅，ADR-005）。
  Stream<void> get onChanged => _changed.stream;

  /// 同步整表写入后手动通知（Drift watch 会自己刷新列表）。
  void notifyChanged() => _notifyChanged();

  void _notifyChanged() {
    if (!_changed.isClosed) _changed.add(null);
  }

  /// 一次查出多笔账单的标签，避免按笔 N+1。
  Future<Map<int, List<ListTagLabel>>> _tagsByTransactionIds(
    List<int> transactionIds,
  ) async {
    if (transactionIds.isEmpty) return const {};

    final rows = await (_db.select(_db.transactionTags).join([
          innerJoin(
            _db.tags,
            _db.tags.id.equalsExp(_db.transactionTags.tagId),
          ),
        ])
          ..where(
            _db.transactionTags.transactionId.isIn(transactionIds),
          ))
        .get();

    final map = <int, List<ListTagLabel>>{};
    for (final row in rows) {
      final link = row.readTable(_db.transactionTags);
      final tag = row.readTable(_db.tags);
      map.putIfAbsent(link.transactionId, () => []).add(
            ListTagLabel(id: tag.id, name: tag.name, color: tag.color),
          );
    }
    return map;
  }

  Future<List<TransactionListItem>> _mapJoinedRows(
    List<TypedResult> rows,
  ) async {
    final txs = <Transaction>[];
    final cats = <Category?>[];
    for (final row in rows) {
      txs.add(row.readTable(_db.transactions));
      cats.add(row.readTableOrNull(_db.categories));
    }
    final tagMap = await _tagsByTransactionIds(txs.map((t) => t.id).toList());
    final items = <TransactionListItem>[];
    for (var i = 0; i < txs.length; i++) {
      final tx = txs[i];
      final cat = cats[i];
      items.add(
        TransactionListItem(
          tx: tx,
          categoryId: cat?.id ?? tx.categoryId,
          categoryName: cat?.name,
          categoryIcon: cat?.icon,
          categoryIconType: cat?.iconType ?? 'material',
          categoryCustomIconPath: cat?.customIconPath,
          categoryParentId: cat?.parentId,
          tags: tagMap[tx.id] ?? const [],
        ),
      );
    }
    return items;
  }

  /// 账单行 stream + tags 表变更时重拉标签（ADR-035 标签展示新鲜度）。
  Stream<List<TransactionListItem>> _watchMapped(
    Stream<List<TypedResult>> rowsWatch,
  ) {
    return Stream.multi((controller) {
      List<TypedResult>? latestRows;
      var inFlight = false;
      var queued = false;

      Future<void> emitMapped() async {
        if (latestRows == null) return;
        if (inFlight) {
          queued = true;
          return;
        }
        inFlight = true;
        try {
          do {
            queued = false;
            final snapshot = latestRows!;
            try {
              final items = await _mapJoinedRows(snapshot);
              if (!controller.isClosed) controller.add(items);
            } catch (e, st) {
              if (!controller.isClosed) controller.addError(e, st);
            }
          } while (queued && !controller.isClosed);
        } finally {
          inFlight = false;
        }
      }

      final rowsSub = rowsWatch.listen(
        (rows) {
          latestRows = rows;
          emitMapped();
        },
        onError: controller.addError,
        onDone: controller.close,
      );
      final tagsSub = _db
          .tableUpdates(TableUpdateQuery.onTable(_db.tags))
          .listen(
            (_) => emitMapped(),
            onError: controller.addError,
          );

      controller.onCancel = () async {
        await rowsSub.cancel();
        await tagsSub.cancel();
      };
    });
  }

  /// 监听指定账本、某自然月内的账单（按时间倒序）。
  Stream<List<TransactionListItem>> watchMonth({
    required int ledgerId,
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);

    final query = _db.select(_db.transactions).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.transactions.categoryId),
      ),
    ])
      ..where(_db.transactions.ledgerId.equals(ledgerId))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(
        _db.transactions.happenedAt.isBiggerOrEqualValue(start) &
            _db.transactions.happenedAt.isSmallerThanValue(end),
      )
      ..orderBy([OrderingTerm.desc(_db.transactions.happenedAt)]);

    return _watchMapped(query.watch());
  }

  /// 监听当前账本全部账单（搜索页用；按时间倒序）。
  Stream<List<TransactionListItem>> watchLedger({required int ledgerId}) {
    final query = _db.select(_db.transactions).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.transactions.categoryId),
      ),
    ])
      ..where(_db.transactions.ledgerId.equals(ledgerId))
      ..where(_db.transactions.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(_db.transactions.happenedAt)]);

    return _watchMapped(query.watch());
  }

  /// 某自然日的账单（日历页当日列表）。
  Stream<List<TransactionListItem>> watchDay({
    required int ledgerId,
    required DateTime day,
  }) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final query = _db.select(_db.transactions).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.transactions.categoryId),
      ),
    ])
      ..where(_db.transactions.ledgerId.equals(ledgerId))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(
        _db.transactions.happenedAt.isBiggerOrEqualValue(start) &
            _db.transactions.happenedAt.isSmallerThanValue(end),
      )
      ..orderBy([OrderingTerm.desc(_db.transactions.happenedAt)]);

    return _watchMapped(query.watch());
  }

  /// 指定账本 + 半开区间 + 分类 id 集合。
  Stream<List<TransactionListItem>> watchRangeByCategoryIds({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
    required List<int> categoryIds,
  }) {
    if (categoryIds.isEmpty) {
      return Stream.value(const []);
    }

    final query = _db.select(_db.transactions).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.transactions.categoryId),
      ),
    ])
      ..where(_db.transactions.ledgerId.equals(ledgerId))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(_db.transactions.categoryId.isIn(categoryIds))
      ..where(
        _db.transactions.happenedAt.isBiggerOrEqualValue(start) &
            _db.transactions.happenedAt.isSmallerThanValue(end),
      )
      ..orderBy([OrderingTerm.desc(_db.transactions.happenedAt)]);

    return _watchMapped(query.watch());
  }

  /// 指定账本 + 半开区间 + 未分类。
  Stream<List<TransactionListItem>> watchRangeUncategorized({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) {
    final query = _db.select(_db.transactions).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.transactions.categoryId),
      ),
    ])
      ..where(_db.transactions.ledgerId.equals(ledgerId))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(_db.transactions.categoryId.isNull())
      ..where(
        _db.transactions.happenedAt.isBiggerOrEqualValue(start) &
            _db.transactions.happenedAt.isSmallerThanValue(end),
      )
      ..orderBy([OrderingTerm.desc(_db.transactions.happenedAt)]);

    return _watchMapped(query.watch());
  }

  /// 指定账本 + 半开区间 + 无标签（ADR-039 未标注）。
  Stream<List<TransactionListItem>> watchRangeUntagged({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) {
    final query = _db.select(_db.transactions).join([
      leftOuterJoin(
        _db.transactionTags,
        _db.transactionTags.transactionId.equalsExp(_db.transactions.id),
      ),
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.transactions.categoryId),
      ),
    ])
      ..where(_db.transactions.ledgerId.equals(ledgerId))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(_db.transactionTags.tagId.isNull())
      ..where(
        _db.transactions.happenedAt.isBiggerOrEqualValue(start) &
            _db.transactions.happenedAt.isSmallerThanValue(end),
      )
      ..orderBy([OrderingTerm.desc(_db.transactions.happenedAt)]);

    return _watchMapped(query.watch());
  }

  /// 指定账本 + 半开区间 + 标签。
  Stream<List<TransactionListItem>> watchRangeByTag({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
    required int tagId,
  }) {
    final query = _db.select(_db.transactions).join([
      innerJoin(
        _db.transactionTags,
        _db.transactionTags.transactionId.equalsExp(_db.transactions.id),
      ),
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.transactions.categoryId),
      ),
    ])
      ..where(_db.transactions.ledgerId.equals(ledgerId))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(_db.transactionTags.tagId.equals(tagId))
      ..where(
        _db.transactions.happenedAt.isBiggerOrEqualValue(start) &
            _db.transactions.happenedAt.isSmallerThanValue(end),
      )
      ..orderBy([OrderingTerm.desc(_db.transactions.happenedAt)]);

    return _watchMapped(query.watch());
  }

  /// 指定账本 + 半开区间 + 收支类型（排行全页）。
  Stream<List<TransactionListItem>> watchRangeByType({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
    required String type,
  }) {
    final query = _db.select(_db.transactions).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.transactions.categoryId),
      ),
    ])
      ..where(_db.transactions.ledgerId.equals(ledgerId))
      ..where(_db.transactions.deletedAt.isNull())
      ..where(_db.transactions.type.equals(type))
      ..where(
        _db.transactions.happenedAt.isBiggerOrEqualValue(start) &
            _db.transactions.happenedAt.isSmallerThanValue(end),
      )
      ..orderBy([OrderingTerm.desc(_db.transactions.amount)]);

    return _watchMapped(query.watch());
  }

  /// 指定账本 + 自然月 + 分类 id 集合（主类展开后的 id 列表）。
  Stream<List<TransactionListItem>> watchMonthByCategoryIds({
    required int ledgerId,
    required DateTime month,
    required List<int> categoryIds,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return watchRangeByCategoryIds(
      ledgerId: ledgerId,
      start: start,
      end: end,
      categoryIds: categoryIds,
    );
  }

  /// 指定账本 + 自然月 + 未分类。
  Stream<List<TransactionListItem>> watchMonthUncategorized({
    required int ledgerId,
    required DateTime month,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return watchRangeUncategorized(
      ledgerId: ledgerId,
      start: start,
      end: end,
    );
  }

  /// 指定账本 + 自然月 + 标签。
  Stream<List<TransactionListItem>> watchMonthByTag({
    required int ledgerId,
    required DateTime month,
    required int tagId,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return watchRangeByTag(
      ledgerId: ledgerId,
      start: start,
      end: end,
      tagId: tagId,
    );
  }

  Future<Transaction?> getById(int id) {
    return (_db.select(_db.transactions)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// 导出用：按账本拉取账单（[ledgerId] 为空则全部账本）。
  Future<List<TransactionListItem>> listForExport({int? ledgerId}) async {
    final query = _db.select(_db.transactions).join([
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.transactions.categoryId),
      ),
    ])
      ..where(_db.transactions.deletedAt.isNull());
    if (ledgerId != null) {
      query.where(_db.transactions.ledgerId.equals(ledgerId));
    }
    query.orderBy([OrderingTerm.asc(_db.transactions.happenedAt)]);
    final rows = await query.get();
    return _mapJoinedRows(rows);
  }

  Future<List<int>> getTagIds(int transactionId) async {
    final rows = await (_db.select(_db.transactionTags)
          ..where((t) => t.transactionId.equals(transactionId)))
        .get();
    return rows.map((e) => e.tagId).toList();
  }

  Future<int> insert({
    required int ledgerId,
    required String type,
    required double amount,
    int? categoryId,
    required DateTime happenedAt,
    String? note,
    List<int> tagIds = const [],
    String source = 'manual',
  }) async {
    final ledger = await (_db.select(_db.ledgers)
          ..where((t) => t.id.equals(ledgerId)))
        .getSingle();
    final at = HappenedAt.toSecond(happenedAt);
    final fp = BillFingerprint.build(
      ledgerSyncId: ledger.syncId,
      amount: amount,
      happenedAt: at,
    );
    final clash = await (_db.select(_db.transactions)
          ..where((t) => t.fingerprint.equals(fp))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    if (clash.isNotEmpty) {
      throw StateError('已存在相同账本、金额与时间的账单');
    }
    final now = HappenedAt.now();
    final id = await _db.transaction(() async {
      final id = await _db.into(_db.transactions).insert(
            TransactionsCompanion.insert(
              ledgerId: ledgerId,
              type: type,
              amount: amount,
              happenedAt: at,
              syncId: _uuid.v4(),
              fingerprint: fp,
              categoryId: Value(categoryId),
              note: Value(note?.trim().isEmpty == true ? null : note?.trim()),
              source: Value(source),
              updatedAt: Value(now),
            ),
          );
      for (final tagId in tagIds) {
        await _db.into(_db.transactionTags).insert(
              TransactionTagsCompanion.insert(
                transactionId: id,
                tagId: tagId,
              ),
            );
      }
      return id;
    });
    _notifyChanged();
    return id;
  }

  Future<void> update({
    required int id,
    required String type,
    required double amount,
    int? categoryId,
    required DateTime happenedAt,
    String? note,
    List<int> tagIds = const [],
  }) async {
    final existing = await (_db.select(_db.transactions)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    final ledger = await (_db.select(_db.ledgers)
          ..where((t) => t.id.equals(existing.ledgerId)))
        .getSingle();
    final at = HappenedAt.toSecond(happenedAt);
    final fp = BillFingerprint.build(
      ledgerSyncId: ledger.syncId,
      amount: amount,
      happenedAt: at,
    );
    if (fp != existing.fingerprint) {
      final clash = await (_db.select(_db.transactions)
            ..where((t) => t.fingerprint.equals(fp))
            ..where((t) => t.deletedAt.isNull())
            ..where((t) => t.id.isNotValue(id)))
          .get();
      if (clash.isNotEmpty) {
        throw StateError('已存在相同账本、金额与时间的账单');
      }
    }
    final now = HappenedAt.now();
    await _db.transaction(() async {
      await (_db.update(_db.transactions)..where((t) => t.id.equals(id)))
          .write(
        TransactionsCompanion(
          type: Value(type),
          amount: Value(amount),
          categoryId: Value(categoryId),
          happenedAt: Value(at),
          fingerprint: Value(fp),
          updatedAt: Value(now),
          note: Value(note?.trim().isEmpty == true ? null : note?.trim()),
        ),
      );
      await (_db.delete(_db.transactionTags)
            ..where((t) => t.transactionId.equals(id)))
          .go();
      for (final tagId in tagIds) {
        await _db.into(_db.transactionTags).insert(
              TransactionTagsCompanion.insert(
                transactionId: id,
                tagId: tagId,
              ),
            );
      }
    });
    _notifyChanged();
  }

  Future<void> delete(int id) async {
    final now = HappenedAt.now();
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
          TransactionsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    _notifyChanged();
  }

  /// 是否已有存活账单占用该指纹（[excludeId] 编辑时排除自身）。
  Future<bool> fingerprintTaken(String fingerprint, {int? excludeId}) async {
    final q = _db.select(_db.transactions)
      ..where((t) => t.fingerprint.equals(fingerprint))
      ..where((t) => t.deletedAt.isNull());
    if (excludeId != null) {
      q.where((t) => t.id.isNotValue(excludeId));
    }
    return (await q.get()).isNotEmpty;
  }
}
