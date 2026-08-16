import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:piggy_count/data/repositories/statistics_repository.dart';
import 'package:piggy_count/data/seed_service.dart';
import 'package:piggy_count/utils/report_period.dart';

void main() {
  group('ReportPeriod', () {
    test('周报对齐到周一～周日半开区间', () {
      // 2026-08-13 周四 → 周一起点 8/10
      final p = ReportPeriod.fromScope(
        ReportScope.week,
        DateTime(2026, 8, 13),
      );
      expect(p.start, DateTime(2026, 8, 10));
      expect(p.end, DateTime(2026, 8, 17));
      expect(p.dayCount, 7);
    });

    test('月报 previous/next 跨年', () {
      final p = ReportPeriod.fromScope(
        ReportScope.month,
        DateTime(2026, 1, 15),
      );
      expect(p.previous.start, DateTime(2025, 12, 1));
      expect(p.next.start, DateTime(2026, 2, 1));
    });
  });

  group('StatisticsRepository', () {
    late AppDatabase db;
    late StatisticsRepository stats;
    late int ledgerId;

    setUp(() async {
      db = AppDatabase.memory();
      await SeedService(db).ensureSeeded();
      ledgerId = (await db.select(db.ledgers).get()).first.id;
      stats = StatisticsRepository(db);

      final cats = await db.select(db.categories).get();
      final expense = cats.firstWhere((c) => c.kind == 'expense');

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              ledgerId: ledgerId,
              type: 'expense',
              amount: 100,
              happenedAt: DateTime(2026, 8, 13, 12),
              syncId: 't1',
              categoryId: Value(expense.id),
            ),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              ledgerId: ledgerId,
              type: 'income',
              amount: 50,
              happenedAt: DateTime(2026, 8, 14, 9),
              syncId: 't2',
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('月报汇总与结余', () async {
      final period = ReportPeriod.fromScope(
        ReportScope.month,
        DateTime(2026, 8, 1),
      );
      final snap = await stats.loadReport(
        ledgerId: ledgerId,
        period: period,
        type: ReportMoneyType.expense,
      );
      expect(snap.periodTotal, 100);
      expect(snap.incomeTotal, 50);
      expect(snap.expenseTotal, 100);
      expect(snap.balance, -50);
      expect(snap.mainComposition, isNotEmpty);
      expect(snap.ranking.length, 1);
    });
  });
}
