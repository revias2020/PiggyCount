import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';

/// 账本读写。
class LedgerRepository {
  LedgerRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const currentLedgerKey = 'current_ledger_id';

  Stream<List<Ledger>> watchAll() {
    return (_db.select(_db.ledgers)..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .watch();
  }

  Future<List<Ledger>> getAll() {
    return (_db.select(_db.ledgers)..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  Future<int?> readCurrentLedgerId() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(currentLedgerKey)))
        .getSingleOrNull();
    if (row == null) return null;
    return int.tryParse(row.value);
  }

  Future<void> setCurrentLedgerId(int id) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: currentLedgerKey,
            value: '$id',
          ),
        );
  }

  Future<int> create(String name, {bool select = true}) async {
    final id = await _db.into(_db.ledgers).insert(
          LedgersCompanion.insert(
            name: name.trim(),
            syncId: _uuid.v4(),
          ),
        );
    if (select) {
      await setCurrentLedgerId(id);
    }
    return id;
  }

  Future<void> rename(int id, String name) async {
    await (_db.update(_db.ledgers)..where((t) => t.id.equals(id))).write(
          LedgersCompanion(name: Value(name.trim())),
        );
  }

  /// 删除账本及其账单/标签关联；至少保留一本时返回 false。
  Future<bool> delete(int id) async {
    final all = await getAll();
    if (all.length <= 1) return false;

    await _db.transaction(() async {
      final txs = await (_db.select(_db.transactions)
            ..where((t) => t.ledgerId.equals(id)))
          .get();
      final txIds = txs.map((e) => e.id).toList();
      if (txIds.isNotEmpty) {
        await (_db.delete(_db.transactionTags)
              ..where((t) => t.transactionId.isIn(txIds)))
            .go();
        await (_db.delete(_db.transactions)..where((t) => t.ledgerId.equals(id)))
            .go();
      }
      await (_db.delete(_db.ledgers)..where((t) => t.id.equals(id))).go();
    });

    final current = await readCurrentLedgerId();
    if (current == id) {
      final next = (await getAll()).first;
      await setCurrentLedgerId(next.id);
    }
    return true;
  }
}
