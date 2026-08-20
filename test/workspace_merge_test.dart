import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/sync/workspace_merge.dart';
import 'package:piggy_count/sync/workspace_models.dart';
import 'package:piggy_count/utils/bill_fingerprint.dart';

void main() {
  final t0 = DateTime(2026, 8, 1, 10, 0, 0);
  final t1 = DateTime(2026, 8, 1, 11, 0, 0);
  final t2 = DateTime(2026, 8, 1, 12, 0, 0);
  final happened = DateTime(2026, 8, 1, 8, 30, 15);

  SyncBill bill({
    required String syncId,
    required String ledger,
    required double amount,
    String? categoryName,
    DateTime? updatedAt,
    DateTime? deletedAt,
    DateTime? happenedAt,
  }) {
    final at = happenedAt ?? happened;
    return SyncBill(
      syncId: syncId,
      fingerprint: BillFingerprint.build(
        ledgerSyncId: ledger,
        amount: amount,
        happenedAt: at,
      ),
      ledgerSyncId: ledger,
      type: 'expense',
      amount: amount,
      happenedAt: at,
      categoryName: categoryName,
      updatedAt: updatedAt ?? t0,
      deletedAt: deletedAt,
    );
  }

  test('同 UUID 较晚改动整条覆盖', () {
    final local = WorkspaceSnapshot(
      ledgers: [
        SyncLedger(syncId: 'aaa', name: '日常', updatedAt: t0),
      ],
    );
    final remote = WorkspaceSnapshot(
      ledgers: [
        SyncLedger(syncId: 'aaa', name: '生活', updatedAt: t1),
      ],
    );
    final result = WorkspaceMerge.merge(local: local, remote: remote);
    expect(result.merged.ledgers.single.name, '生活');
    expect(result.preview.ledgers.updated, 1);
  });

  test('账本同名折合留下较小 UUID 并改写账单指纹', () {
    const localId = 'bbb-ledger';
    const remoteId = 'aaa-ledger';
    final local = WorkspaceSnapshot(
      ledgers: [
        SyncLedger(syncId: localId, name: '日常账本', updatedAt: t0),
      ],
      bills: [bill(syncId: 'b1', ledger: localId, amount: 12.3)],
    );
    final remote = WorkspaceSnapshot(
      ledgers: [
        SyncLedger(syncId: remoteId, name: '日常账本', updatedAt: t1),
      ],
    );
    final result = WorkspaceMerge.merge(local: local, remote: remote);
    final live = result.merged.ledgers.where((l) => l.isLive).toList();
    expect(live, hasLength(1));
    expect(live.single.syncId, remoteId);
    expect(result.merged.bills.single.ledgerSyncId, remoteId);
    expect(result.merged.bills.single.syncId, 'b1');
    expect(
      result.merged.bills.single.fingerprint,
      BillFingerprint.build(
        ledgerSyncId: remoteId,
        amount: 12.3,
        happenedAt: happened,
      ),
    );
  });

  test('同一账单身份较晚改动覆盖分类名', () {
    const ledger = 'led-1';
    final local = WorkspaceSnapshot(
      ledgers: [SyncLedger(syncId: ledger, name: '日常', updatedAt: t0)],
      bills: [
        bill(
          syncId: 'same',
          ledger: ledger,
          amount: 8,
          categoryName: '餐饮',
          updatedAt: t0,
        ),
      ],
    );
    final remote = WorkspaceSnapshot(
      ledgers: [SyncLedger(syncId: ledger, name: '日常', updatedAt: t0)],
      bills: [
        bill(
          syncId: 'same',
          ledger: ledger,
          amount: 8,
          categoryName: '购物',
          updatedAt: t2,
        ),
      ],
    );
    final result = WorkspaceMerge.merge(local: local, remote: remote);
    expect(result.merged.bills, hasLength(1));
    expect(result.merged.bills.single.categoryName, '购物');
    expect(result.preview.bills.updated, 1);
    expect(result.preview.duplicates, isEmpty);
  });

  test('改金额换指纹仍按身份合并为一条', () {
    const ledger = 'led-1';
    final local = WorkspaceSnapshot(
      ledgers: [SyncLedger(syncId: ledger, name: '日常', updatedAt: t0)],
      bills: [
        bill(syncId: 'same', ledger: ledger, amount: 8, updatedAt: t2),
      ],
    );
    final remote = WorkspaceSnapshot(
      ledgers: [SyncLedger(syncId: ledger, name: '日常', updatedAt: t0)],
      bills: [
        bill(syncId: 'same', ledger: ledger, amount: 9, updatedAt: t0),
      ],
    );
    final result = WorkspaceMerge.merge(local: local, remote: remote);
    expect(result.merged.bills, hasLength(1));
    expect(result.merged.bills.single.amount, 8);
    expect(result.preview.duplicates, isEmpty);
  });

  test('不同身份同指纹列为疑似重复，默认不折合', () {
    const ledger = 'led-1';
    final local = WorkspaceSnapshot(
      ledgers: [SyncLedger(syncId: ledger, name: '日常', updatedAt: t0)],
      bills: [
        bill(
          syncId: 'a',
          ledger: ledger,
          amount: 8,
          categoryName: '餐饮',
          updatedAt: t0,
        ),
      ],
    );
    final remote = WorkspaceSnapshot(
      ledgers: [SyncLedger(syncId: ledger, name: '日常', updatedAt: t0)],
      bills: [
        bill(
          syncId: 'b',
          ledger: ledger,
          amount: 8,
          categoryName: '购物',
          updatedAt: t2,
        ),
      ],
    );
    final result = WorkspaceMerge.merge(local: local, remote: remote);
    expect(result.merged.bills.where((b) => b.isLive), hasLength(2));
    expect(result.preview.duplicates, hasLength(1));
    expect(result.preview.duplicates.single.bills, hasLength(2));

    final folded = WorkspaceMerge.foldBillDuplicates(
      snap: result.merged,
      mergeFingerprints: {
        result.preview.duplicates.single.fingerprint,
      },
      now: t2,
    );
    final live = folded.bills.where((b) => b.isLive).toList();
    expect(live, hasLength(1));
    expect(live.single.syncId, 'b');
    expect(live.single.categoryName, '购物');
    expect(folded.bills.where((b) => !b.isLive), hasLength(1));
  });

  test('主变子但仍有子时强制子变主并写预览冲突', () {
    final local = WorkspaceSnapshot(
      categories: [
        SyncCategory(
          syncId: 'food',
          name: '餐饮',
          kind: 'expense',
          updatedAt: t0,
        ),
        SyncCategory(
          syncId: 'lunch',
          name: '午餐',
          kind: 'expense',
          parentSyncId: 'food',
          updatedAt: t0,
        ),
      ],
    );
    final remote = WorkspaceSnapshot(
      categories: [
        SyncCategory(
          syncId: 'shop',
          name: '购物',
          kind: 'expense',
          updatedAt: t0,
        ),
        SyncCategory(
          syncId: 'food',
          name: '餐饮',
          kind: 'expense',
          parentSyncId: 'shop',
          updatedAt: t1,
        ),
        SyncCategory(
          syncId: 'lunch',
          name: '午餐',
          kind: 'expense',
          parentSyncId: 'food',
          updatedAt: t0,
        ),
      ],
    );
    final result = WorkspaceMerge.merge(local: local, remote: remote);
    final food = result.merged.categories.firstWhere((c) => c.syncId == 'food');
    final lunch =
        result.merged.categories.firstWhere((c) => c.syncId == 'lunch');
    expect(food.parentSyncId, 'shop');
    expect(lunch.parentSyncId, isNull);
    expect(result.preview.categoryTreeConflict, isNotNull);
  });

  test('对端较晚账单改动使已删账本复活', () {
    const id = 'led-res';
    final local = WorkspaceSnapshot(
      ledgers: [
        SyncLedger(
          syncId: id,
          name: '日常',
          updatedAt: t1,
          deletedAt: t1,
        ),
      ],
    );
    final remote = WorkspaceSnapshot(
      ledgers: [
        SyncLedger(
          syncId: id,
          name: '日常',
          updatedAt: t0,
        ),
      ],
      bills: [
        bill(syncId: 'bx', ledger: id, amount: 1, updatedAt: t2),
      ],
    );
    final result = WorkspaceMerge.merge(local: local, remote: remote);
    expect(result.merged.ledgers.single.isLive, isTrue);
    expect(result.merged.bills.single.isLive, isTrue);
  });

  test('账单墓碑超过 90 天从快照裁掉', () {
    const ledger = 'led-1';
    final now = DateTime(2026, 8, 19, 12);
    final snap = WorkspaceSnapshot(
      bills: [
        bill(
          syncId: 'old',
          ledger: ledger,
          amount: 1,
          deletedAt: now.subtract(const Duration(days: 91)),
        ),
        bill(
          syncId: 'fresh',
          ledger: ledger,
          amount: 2,
          deletedAt: now.subtract(const Duration(days: 10)),
        ),
        bill(syncId: 'live', ledger: ledger, amount: 3),
      ],
    );
    final pruned = WorkspaceMerge.pruneExpiredBillTombs(snap, now);
    expect(pruned.bills.map((b) => b.syncId), ['fresh', 'live']);
  });
}
