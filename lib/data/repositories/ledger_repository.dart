import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../utils/happened_at.dart';
import '../app_database.dart';

/// 账本读写。
class LedgerRepository {
  LedgerRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const currentLedgerKey = 'current_ledger_id';

  Stream<List<Ledger>> watchAll() {
    return (_db.select(_db.ledgers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .watch();
  }

  Future<List<Ledger>> getAll() {
    return (_db.select(_db.ledgers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  Future<Ledger?> getById(int id) {
    return (_db.select(_db.ledgers)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// 未删除账本中是否已有同名（[excludeId] 改名时排除自身）。
  Future<bool> nameTaken(String name, {int? excludeId}) async {
    final trimmed = name.trim();
    final q = _db.select(_db.ledgers)
      ..where((t) => t.name.equals(trimmed))
      ..where((t) => t.deletedAt.isNull());
    if (excludeId != null) {
      q.where((t) => t.id.isNotValue(excludeId));
    }
    return (await q.get()).isNotEmpty;
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
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('账本名称不能为空');
    }
    if (await nameTaken(trimmed)) {
      throw StateError('已存在同名账本');
    }
    final now = HappenedAt.now();
    final id = await _db.into(_db.ledgers).insert(
          LedgersCompanion.insert(
            name: trimmed,
            syncId: _uuid.v4(),
            updatedAt: Value(now),
          ),
        );
    if (select) {
      await setCurrentLedgerId(id);
    }
    return id;
  }

  Future<void> rename(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('账本名称不能为空');
    }
    if (await nameTaken(trimmed, excludeId: id)) {
      throw StateError('已存在同名账本');
    }
    final now = HappenedAt.now();
    await (_db.update(_db.ledgers)..where((t) => t.id.equals(id))).write(
          LedgersCompanion(
            name: Value(trimmed),
            updatedAt: Value(now),
          ),
        );
  }

  /// 软删账本及其账单；至少保留一本时返回 false。
  Future<bool> delete(int id) async {
    final all = await getAll();
    if (all.length <= 1) return false;

    final now = HappenedAt.now();
    await _db.transaction(() async {
      await (_db.update(_db.transactions)..where((t) => t.ledgerId.equals(id)))
          .write(
        TransactionsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await (_db.update(_db.ledgers)..where((t) => t.id.equals(id))).write(
            LedgersCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });

    final current = await readCurrentLedgerId();
    if (current == id) {
      final rest = await getAll();
      if (rest.isNotEmpty) {
        await setCurrentLedgerId(rest.first.id);
      }
    }
    return true;
  }
}
