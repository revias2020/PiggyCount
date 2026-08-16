import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/transaction_repository.dart';
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
