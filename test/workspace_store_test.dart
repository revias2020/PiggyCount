import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:piggy_count/data/repositories/ledger_repository.dart';
import 'package:piggy_count/data/seed_service.dart';
import 'package:piggy_count/sync/workspace_codec.dart';
import 'package:piggy_count/sync/workspace_merge.dart';
import 'package:piggy_count/sync/workspace_store.dart';
import 'package:piggy_count/utils/bill_fingerprint.dart';

void main() {
  test('工作区 JSON 往返保留账本与分类', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await SeedService(db).ensureSeeded();
    final snap = await WorkspaceStore(db).capture();
    expect(snap.categories, isNotEmpty);
    final json = jsonDecode(jsonEncode(WorkspaceCodec.encode(snap))) as Map;
    final back = WorkspaceCodec.decode(Map<String, Object?>.from(json));
    expect(back.categories.length, snap.categories.length);
    expect(back.tagGroups.length, snap.tagGroups.length);
    expect(
      back.ledgers.map((e) => e.syncId).toSet(),
      snap.ledgers.map((e) => e.syncId).toSet(),
    );
  });

  test('两台同名默认账本折合后本机只留一本', () async {
    final local = AppDatabase.memory();
    final remote = AppDatabase.memory();
    addTearDown(local.close);
    addTearDown(remote.close);
    await SeedService(local).ensureSeeded();
    await SeedService(remote).ensureSeeded();

    final store = WorkspaceStore(local);
    final merged = WorkspaceMerge.merge(
      local: await store.capture(),
      remote: await WorkspaceStore(remote).capture(),
    );
    await store.apply(merged.merged);

    final live = await LedgerRepository(local).getAll();
    expect(live, hasLength(1));
    expect(live.single.name, '日常账本');
  });

  test('工作区 JSON 往返保留账单身份', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await SeedService(db).ensureSeeded();
    final ledger = (await db.select(db.ledgers).get()).first;
    final at = DateTime(2026, 8, 1, 8, 30, 15);
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            ledgerId: ledger.id,
            type: 'expense',
            amount: 12.3,
            happenedAt: at,
            syncId: 'bill-uuid',
            fingerprint: BillFingerprint.build(
              ledgerSyncId: ledger.syncId,
              amount: 12.3,
              happenedAt: at,
            ),
          ),
        );
    final snap = await WorkspaceStore(db).capture();
    final json = jsonDecode(jsonEncode(WorkspaceCodec.encode(snap))) as Map;
    final back = WorkspaceCodec.decode(Map<String, Object?>.from(json));
    final bill = back.bills.singleWhere((b) => b.syncId == 'bill-uuid');
    expect(bill.amount, 12.3);
    expect(json['version'], 2);
  });

  test('按身份 apply：改金额换指纹仍是一行', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await SeedService(db).ensureSeeded();
    final store = WorkspaceStore(db);
    final ledger = (await db.select(db.ledgers).get()).first;
    final at = DateTime(2026, 8, 1, 8, 30, 15);
    final firstFp = BillFingerprint.build(
      ledgerSyncId: ledger.syncId,
      amount: 8,
      happenedAt: at,
    );
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            ledgerId: ledger.id,
            type: 'expense',
            amount: 8,
            happenedAt: at,
            syncId: 'same-bill',
            fingerprint: firstFp,
          ),
        );

    final snap = await store.capture();
    final original = snap.bills.singleWhere((b) => b.syncId == 'same-bill');
    final edited = original.copyWith(
      amount: 9,
      fingerprint: BillFingerprint.build(
        ledgerSyncId: ledger.syncId,
        amount: 9,
        happenedAt: at,
      ),
      updatedAt: DateTime(2026, 8, 1, 12),
    );
    await store.apply(snap.copyWith(bills: [edited]));

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(1));
    expect(rows.single.syncId, 'same-bill');
    expect(rows.single.amount, 9);
    expect(rows.single.fingerprint, isNot(firstFp));
  });

  test('apply 硬删超过 90 天的账单墓碑', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await SeedService(db).ensureSeeded();
    final store = WorkspaceStore(db);
    final ledger = (await db.select(db.ledgers).get()).first;
    final at = DateTime(2026, 8, 1, 8, 30, 15);
    final now = DateTime.now();
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            ledgerId: ledger.id,
            type: 'expense',
            amount: 1,
            happenedAt: at,
            syncId: 'old-tomb',
            fingerprint: BillFingerprint.build(
              ledgerSyncId: ledger.syncId,
              amount: 1,
              happenedAt: at,
            ),
            updatedAt: Value(now.subtract(const Duration(days: 91))),
            deletedAt: Value(now.subtract(const Duration(days: 91))),
          ),
        );
    await store.apply(await store.capture());
    final rows = await db.select(db.transactions).get();
    expect(rows.where((r) => r.syncId == 'old-tomb'), isEmpty);
  });
}
