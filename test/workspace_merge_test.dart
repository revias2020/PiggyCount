import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/sync/workspace_merge.dart';
import 'package:piggy_count/sync/workspace_models.dart';
import 'package:piggy_count/utils/bill_fingerprint.dart';

void main() {
  final t0 = DateTime(2026, 8, 1, 10, 0, 0);
  final t1 = DateTime(2026, 8, 1, 11, 0, 0);
  final t2 = DateTime(2026, 8, 1, 12, 0, 0);
  final happened = DateTime(2026, 8, 1, 8, 30, 15);

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
    final localFp = BillFingerprint.build(
      ledgerSyncId: localId,
      amount: 12.3,
      happenedAt: happened,
    );
    final local = WorkspaceSnapshot(
      ledgers: [
        SyncLedger(syncId: localId, name: '日常账本', updatedAt: t0),
      ],
      bills: [
        SyncBill(
          fingerprint: localFp,
          ledgerSyncId: localId,
          type: 'expense',
          amount: 12.3,
          happenedAt: happened,
          updatedAt: t0,
        ),
      ],
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
    expect(
      result.merged.bills.single.fingerprint,
      BillFingerprint.build(
        ledgerSyncId: remoteId,
        amount: 12.3,
        happenedAt: happened,
      ),
    );
  });

  test('账单按指纹合并，较晚改动覆盖分类名', () {
    const ledger = 'led-1';
    final fp = BillFingerprint.build(
      ledgerSyncId: ledger,
      amount: 8,
      happenedAt: happened,
    );
    final local = WorkspaceSnapshot(
      ledgers: [SyncLedger(syncId: ledger, name: '日常', updatedAt: t0)],
      bills: [
        SyncBill(
          fingerprint: fp,
          ledgerSyncId: ledger,
          type: 'expense',
          amount: 8,
          happenedAt: happened,
          categoryName: '餐饮',
          updatedAt: t0,
        ),
      ],
    );
    final remote = WorkspaceSnapshot(
      ledgers: [SyncLedger(syncId: ledger, name: '日常', updatedAt: t0)],
      bills: [
        SyncBill(
          fingerprint: fp,
          ledgerSyncId: ledger,
          type: 'expense',
          amount: 8,
          happenedAt: happened,
          categoryName: '购物',
          updatedAt: t2,
        ),
      ],
    );
    final result = WorkspaceMerge.merge(local: local, remote: remote);
    expect(result.merged.bills.single.categoryName, '购物');
    expect(result.preview.bills.updated, 1);
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
    final fp = BillFingerprint.build(
      ledgerSyncId: id,
      amount: 1,
      happenedAt: happened,
    );
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
        SyncBill(
          fingerprint: fp,
          ledgerSyncId: id,
          type: 'expense',
          amount: 1,
          happenedAt: happened,
          updatedAt: t2,
        ),
      ],
    );
    final result = WorkspaceMerge.merge(local: local, remote: remote);
    expect(result.merged.ledgers.single.isLive, isTrue);
    expect(result.merged.bills.single.isLive, isTrue);
  });
}
