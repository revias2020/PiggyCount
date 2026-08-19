import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/transaction_repository.dart';
import '../utils/report_period.dart';
import 'database_provider.dart';
import 'ledger_session_provider.dart';

/// 明细页当前浏览的月份（取月的 1 号 0 点）。
final detailsMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

/// 当前账本 + 当前月份的账单流。
final monthTransactionsProvider =
    StreamProvider<List<TransactionListItem>>((ref) {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final month = ref.watch(detailsMonthProvider);
  if (ledgerId == null) {
    return Stream.value(const []);
  }
  return ref.watch(transactionRepositoryProvider).watchMonth(
        ledgerId: ledgerId,
        month: month,
      );
});

/// 明细页用：在 provider 层预计算月汇总与按日分组，避免 ListView build 热路径重复算。
final monthLedgerProvider = Provider<AsyncValue<MonthLedgerView>>((ref) {
  return ref.watch(monthTransactionsProvider).whenData(
        MonthLedgerView.fromItems,
      );
});

final expenseCategoriesProvider = StreamProvider((ref) {
  return ref.watch(categoryRepositoryProvider).watchByKind('expense');
});

final incomeCategoriesProvider = StreamProvider((ref) {
  return ref.watch(categoryRepositoryProvider).watchByKind('income');
});

final tagsProvider = StreamProvider((ref) {
  return ref.watch(tagRepositoryProvider).watchAll();
});

/// 标签组 + 组内标签（标签管理 / 记一笔按组展示）。
final tagGroupBundlesProvider = StreamProvider((ref) {
  return ref.watch(tagRepositoryProvider).watchBundles();
});

/// 当前账本全部账单（搜索页）。
final ledgerTransactionsProvider =
    StreamProvider<List<TransactionListItem>>((ref) {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  if (ledgerId == null) {
    return Stream.value(const []);
  }
  return ref.watch(transactionRepositoryProvider).watchLedger(
        ledgerId: ledgerId,
      );
});

/// 日历页当前聚焦的月份（与明细月份独立）。
final calendarMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

/// 日历页选中的自然日；切月时可清空。
final calendarSelectedDayProvider = StateProvider<DateTime?>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// 日历聚焦月的账单（用于格子摘要）。
final calendarMonthTransactionsProvider =
    StreamProvider<List<TransactionListItem>>((ref) {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final month = ref.watch(calendarMonthProvider);
  if (ledgerId == null) {
    return Stream.value(const []);
  }
  return ref.watch(transactionRepositoryProvider).watchMonth(
        ledgerId: ledgerId,
        month: month,
      );
});

/// 日历选中日的账单列表。
final calendarDayTransactionsProvider =
    StreamProvider<List<TransactionListItem>>((ref) {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final day = ref.watch(calendarSelectedDayProvider);
  if (ledgerId == null || day == null) {
    return Stream.value(const []);
  }
  return ref.watch(transactionRepositoryProvider).watchDay(
        ledgerId: ledgerId,
        day: day,
      );
});

/// 日历月：按日汇总收入/支出。key = `yyyy-MM-dd`。
final calendarDailyTotalsProvider =
    Provider<AsyncValue<Map<String, (double income, double expense)>>>((ref) {
  return ref.watch(calendarMonthTransactionsProvider).whenData((items) {
    final map = <String, (double, double)>{};
    for (final item in items) {
      final t = item.tx.happenedAt;
      final key =
          '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      final prev = map[key] ?? (0.0, 0.0);
      if (item.tx.type == 'expense') {
        map[key] = (prev.$1, prev.$2 + item.tx.amount);
      } else {
        map[key] = (prev.$1 + item.tx.amount, prev.$2);
      }
    }
    return map;
  });
});

/// 分类明细查询键（月度可换月，或报表只读区间；ADR-029/033）。
@immutable
class CategoryDetailQuery {
  const CategoryDetailQuery({
    required this.start,
    required this.end,
    this.categoryId,
    this.includeChildren = false,
  });

  factory CategoryDetailQuery.month({
    required DateTime month,
    int? categoryId,
    bool includeChildren = false,
  }) {
    final start = DateTime(month.year, month.month);
    return CategoryDetailQuery(
      start: start,
      end: DateTime(month.year, month.month + 1),
      categoryId: categoryId,
      includeChildren: includeChildren,
    );
  }

  final DateTime start;
  final DateTime end;
  final int? categoryId;
  final bool includeChildren;

  @override
  bool operator ==(Object other) {
    return other is CategoryDetailQuery &&
        other.start == start &&
        other.end == end &&
        other.categoryId == categoryId &&
        other.includeChildren == includeChildren;
  }

  @override
  int get hashCode =>
      Object.hash(start, end, categoryId, includeChildren);
}

final categoryDetailTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionListItem>, CategoryDetailQuery>((ref, query) async* {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  if (ledgerId == null) {
    yield const [];
    return;
  }
  final repo = ref.watch(transactionRepositoryProvider);
  if (query.categoryId == null) {
    yield* repo.watchRangeUncategorized(
      ledgerId: ledgerId,
      start: query.start,
      end: query.end,
    );
    return;
  }
  var ids = <int>[query.categoryId!];
  if (query.includeChildren) {
    final children =
        await ref.read(categoryRepositoryProvider).childrenOf(query.categoryId!);
    ids = [query.categoryId!, ...children.map((c) => c.id)];
  }
  yield* repo.watchRangeByCategoryIds(
    ledgerId: ledgerId,
    start: query.start,
    end: query.end,
    categoryIds: ids,
  );
});

@immutable
class TagDetailQuery {
  const TagDetailQuery({
    required this.start,
    required this.end,
    this.tagId,
  });

  factory TagDetailQuery.month({
    required DateTime month,
    int? tagId,
  }) {
    final start = DateTime(month.year, month.month);
    return TagDetailQuery(
      start: start,
      end: DateTime(month.year, month.month + 1),
      tagId: tagId,
    );
  }

  final DateTime start;
  final DateTime end;

  /// `null` 表示未标注（无标签账单）。
  final int? tagId;

  @override
  bool operator ==(Object other) {
    return other is TagDetailQuery &&
        other.start == start &&
        other.end == end &&
        other.tagId == tagId;
  }

  @override
  int get hashCode => Object.hash(start, end, tagId);
}

final tagDetailTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionListItem>, TagDetailQuery>((ref, query) {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  if (ledgerId == null) {
    return Stream.value(const []);
  }
  final repo = ref.watch(transactionRepositoryProvider);
  if (query.tagId == null) {
    return repo.watchRangeUntagged(
      ledgerId: ledgerId,
      start: query.start,
      end: query.end,
    );
  }
  return repo.watchRangeByTag(
    ledgerId: ledgerId,
    start: query.start,
    end: query.end,
    tagId: query.tagId!,
  );
});

/// 排行全页：周期内指定收支类型的流水。
@immutable
class RankFullQuery {
  const RankFullQuery({
    required this.start,
    required this.end,
    required this.type,
  });

  final DateTime start;
  final DateTime end;
  final ReportMoneyType type;

  @override
  bool operator ==(Object other) {
    return other is RankFullQuery &&
        other.start == start &&
        other.end == end &&
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(start, end, type);
}

final rankFullTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionListItem>, RankFullQuery>((ref, query) {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  if (ledgerId == null) {
    return Stream.value(const []);
  }
  final typeStr =
      query.type == ReportMoneyType.expense ? 'expense' : 'income';
  return ref.watch(transactionRepositoryProvider).watchRangeByType(
        ledgerId: ledgerId,
        start: query.start,
        end: query.end,
        type: typeStr,
      );
});
