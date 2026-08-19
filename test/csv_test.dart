import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:piggy_count/data/repositories/category_repository.dart';
import 'package:piggy_count/data/repositories/ledger_repository.dart';
import 'package:piggy_count/data/repositories/tag_repository.dart';
import 'package:piggy_count/data/repositories/transaction_repository.dart';
import 'package:piggy_count/data/seed_service.dart';
import 'package:piggy_count/services/csv/csv_service.dart';
import 'package:piggy_count/utils/bill_fingerprint.dart';

void main() {
  late AppDatabase db;
  late CsvService csv;
  late int ledgerId;

  setUp(() async {
    db = AppDatabase.memory();
    await SeedService(db).ensureSeeded();
    final ledgers = LedgerRepository(db);
    ledgerId = (await ledgers.getAll()).first.id;
    csv = CsvService(
      ledgers: ledgers,
      categories: CategoryRepository(db),
      tags: TagRepository(db),
      transactions: TransactionRepository(db),
    );

    final cats = await db.select(db.categories).get();
    final expense = cats.firstWhere((c) => c.kind == 'expense');
    final happenedAt = DateTime(2026, 8, 1, 10);
    final ledger = (await ledgers.getAll()).first;
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 12.5,
            happenedAt: happenedAt,
            syncId: 'csv-t1',
            fingerprint: BillFingerprint.build(
              ledgerSyncId: ledger.syncId,
              amount: 12.5,
              happenedAt: happenedAt,
            ),
            categoryId: Value(expense.id),
            note: Value('测试'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  test('导出再导入保留关键字段', () async {
    final exported = await csv.exportCsv(ledgerId: ledgerId);
    expect(exported, contains('日期时间'));
    expect(exported, contains('12.50'));

    // 清空账单后导入
    await db.delete(db.transactions).go();
    final n = await csv.importCsv(exported, defaultLedgerId: ledgerId);
    expect(n, 1);
    final rows = await db.select(db.transactions).get();
    expect(rows.length, 1);
    expect(rows.first.amount, 12.5);
    expect(rows.first.note, '测试');
  });
}
