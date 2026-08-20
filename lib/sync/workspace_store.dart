import 'package:drift/drift.dart';

import '../data/app_database.dart';
import '../data/repositories/ledger_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../utils/happened_at.dart';
import 'workspace_merge.dart';
import 'workspace_models.dart';

/// 本机工作区 ↔ 同步快照。
class WorkspaceStore {
  WorkspaceStore(this._db);

  final AppDatabase _db;

  Future<WorkspaceSnapshot> capture() async {
    final ledgers = await _db.select(_db.ledgers).get();
    final categories = await _db.select(_db.categories).get();
    final groups = await _db.select(_db.tagGroups).get();
    final tags = await _db.select(_db.tags).get();
    final txs = await _db.select(_db.transactions).get();
    final links = await _db.select(_db.transactionTags).get();

    final catById = {for (final c in categories) c.id: c};
    final ledgerById = {for (final l in ledgers) l.id: l};
    final tagNameById = {
      for (final t in tags)
        t.id: TagRepository.originalName(
          t.name,
          deleted: t.deletedAt != null,
        ),
    };
    final tagIdsByTx = <int, List<int>>{};
    for (final link in links) {
      (tagIdsByTx[link.transactionId] ??= []).add(link.tagId);
    }

    return WorkspaceSnapshot(
      ledgers: [
        for (final l in ledgers)
          SyncLedger(
            syncId: l.syncId,
            name: l.name,
            updatedAt: l.updatedAt,
            deletedAt: l.deletedAt,
          ),
      ],
      categories: [
        for (final c in categories)
          SyncCategory(
            syncId: c.syncId,
            name: c.name,
            kind: c.kind,
            parentSyncId: c.parentId == null ? null : catById[c.parentId]?.syncId,
            icon: c.icon,
            iconType: c.iconType,
            sortOrder: c.sortOrder,
            updatedAt: c.updatedAt,
            deletedAt: c.deletedAt,
          ),
      ],
      tagGroups: [
        for (final g in groups)
          SyncTagGroup(
            syncId: g.syncId,
            name: TagRepository.originalName(
              g.name,
              deleted: g.deletedAt != null,
            ),
            kind: g.kind,
            scope: g.scope,
            sortOrder: g.sortOrder,
            updatedAt: g.updatedAt,
            deletedAt: g.deletedAt,
          ),
      ],
      tags: [
        for (final t in tags)
          SyncTag(
            syncId: t.syncId,
            name: TagRepository.originalName(
              t.name,
              deleted: t.deletedAt != null,
            ),
            groupSyncId: _groupSyncId(groups, t.groupId),
            color: t.color,
            rangeMin: t.rangeMin,
            rangeMax: t.rangeMax,
            sortOrder: t.sortOrder,
            updatedAt: t.updatedAt,
            deletedAt: t.deletedAt,
          ),
      ],
      bills: [
        for (final tx in txs)
          SyncBill(
            syncId: tx.syncId,
            fingerprint: tx.fingerprint,
            ledgerSyncId: ledgerById[tx.ledgerId]?.syncId ?? '',
            type: tx.type,
            amount: tx.amount,
            happenedAt: tx.happenedAt,
            categoryName: tx.categoryId == null
                ? null
                : catById[tx.categoryId]?.name,
            note: tx.note,
            tagNames: [
              for (final id in tagIdsByTx[tx.id] ?? const <int>[])
                if (tagNameById[id] != null) tagNameById[id]!,
            ],
            source: tx.source,
            updatedAt: tx.updatedAt,
            deletedAt: tx.deletedAt,
          ),
      ],
    );
  }

  static String _groupSyncId(List<TagGroup> groups, int groupId) {
    for (final g in groups) {
      if (g.id == groupId) return g.syncId;
    }
    return '';
  }

  /// 把合并结果写入本机。按同步身份 upsert，含墓碑；并硬删过期账单墓碑。
  Future<void> apply(WorkspaceSnapshot snap) async {
    await _db.transaction(() async {
      await _applyGroups(snap.tagGroups);
      await _applyTags(snap.tags);
      await _applyCategories(snap.categories);
      await _applyLedgers(snap.ledgers);
      await _applyBills(snap.bills);
      await _fixCurrentLedger();
    });
  }

  Future<void> _applyGroups(List<SyncTagGroup> items) async {
    final existing = await _db.select(_db.tagGroups).get();
    final bySync = {for (final e in existing) e.syncId: e};
    for (final item in items) {
      final row = bySync[item.syncId];
      if (row == null) {
        final id = await _db.into(_db.tagGroups).insert(
              TagGroupsCompanion.insert(
                name: '__sync_${item.syncId}',
                kind: item.kind,
                scope: Value(item.scope),
                sortOrder: Value(item.sortOrder),
                syncId: item.syncId,
                updatedAt: Value(item.updatedAt),
                deletedAt: Value(item.deletedAt),
              ),
            );
        bySync[item.syncId] = (await (_db.select(_db.tagGroups)
              ..where((t) => t.id.equals(id)))
            .getSingle());
      } else {
        await (_db.update(_db.tagGroups)..where((t) => t.id.equals(row.id)))
            .write(
          TagGroupsCompanion(
            name: Value('__sync_${item.syncId}'),
            kind: Value(item.kind),
            scope: Value(item.scope),
            sortOrder: Value(item.sortOrder),
            updatedAt: Value(item.updatedAt),
            deletedAt: Value(item.deletedAt),
          ),
        );
      }
    }
    final latest = await _db.select(_db.tagGroups).get();
    final idBySync = {for (final e in latest) e.syncId: e.id};
    for (final item in items) {
      final id = idBySync[item.syncId];
      if (id == null) continue;
      await (_db.update(_db.tagGroups)..where((t) => t.id.equals(id))).write(
            TagGroupsCompanion(
              name: Value(
                item.isLive
                    ? item.name
                    : TagRepository.tombstoneName(id, item.name),
              ),
            ),
          );
    }
  }

  Future<void> _applyTags(List<SyncTag> items) async {
    final groups = await _db.select(_db.tagGroups).get();
    final groupId = {for (final g in groups) g.syncId: g.id};
    final existing = await _db.select(_db.tags).get();
    final bySync = {for (final e in existing) e.syncId: e};
    for (final item in items) {
      final gid = groupId[item.groupSyncId];
      if (gid == null) continue;
      final row = bySync[item.syncId];
      if (row == null) {
        final id = await _db.into(_db.tags).insert(
              TagsCompanion.insert(
                name: '__sync_${item.syncId}',
                groupId: gid,
                color: Value(item.color ?? '#607D8B'),
                rangeMin: Value(item.rangeMin),
                rangeMax: Value(item.rangeMax),
                sortOrder: Value(item.sortOrder),
                syncId: item.syncId,
                updatedAt: Value(item.updatedAt),
                deletedAt: Value(item.deletedAt),
              ),
            );
        bySync[item.syncId] = (await (_db.select(_db.tags)
              ..where((t) => t.id.equals(id)))
            .getSingle());
      } else {
        await (_db.update(_db.tags)..where((t) => t.id.equals(row.id))).write(
              TagsCompanion(
                name: Value('__sync_${item.syncId}'),
                groupId: Value(gid),
                color: Value(item.color ?? row.color),
                rangeMin: Value(item.rangeMin),
                rangeMax: Value(item.rangeMax),
                sortOrder: Value(item.sortOrder),
                updatedAt: Value(item.updatedAt),
                deletedAt: Value(item.deletedAt),
              ),
            );
      }
    }
    final latest = await _db.select(_db.tags).get();
    final idBySync = {for (final e in latest) e.syncId: e.id};
    for (final item in items) {
      final id = idBySync[item.syncId];
      if (id == null) continue;
      await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
            TagsCompanion(
              name: Value(
                item.isLive
                    ? item.name
                    : TagRepository.tombstoneName(id, item.name),
              ),
            ),
          );
    }
  }

  Future<void> _applyCategories(List<SyncCategory> items) async {
    final existing = await _db.select(_db.categories).get();
    final bySync = {for (final e in existing) e.syncId: e};
    for (final item in items) {
      if (bySync.containsKey(item.syncId)) continue;
      final id = await _db.into(_db.categories).insert(
            CategoriesCompanion.insert(
              name: item.name,
              kind: item.kind,
              syncId: item.syncId,
              icon: Value(item.icon ?? 'category'),
              iconType: Value(item.iconType),
              sortOrder: Value(item.sortOrder),
              updatedAt: Value(item.updatedAt),
              deletedAt: Value(item.deletedAt),
            ),
          );
      bySync[item.syncId] = (await (_db.select(_db.categories)
            ..where((t) => t.id.equals(id)))
          .getSingle());
    }
    for (final item in items) {
      final row = bySync[item.syncId];
      if (row == null) continue;
      final parentId = item.parentSyncId == null
          ? null
          : bySync[item.parentSyncId]?.id;
      await (_db.update(_db.categories)..where((t) => t.id.equals(row.id)))
          .write(
        CategoriesCompanion(
          name: Value(item.name),
          kind: Value(item.kind),
          parentId: Value(parentId),
          icon: Value(item.icon ?? row.icon),
          iconType: Value(item.iconType),
          sortOrder: Value(item.sortOrder),
          updatedAt: Value(item.updatedAt),
          deletedAt: Value(item.deletedAt),
        ),
      );
    }
  }

  Future<void> _applyLedgers(List<SyncLedger> items) async {
    final existing = await _db.select(_db.ledgers).get();
    final bySync = {for (final e in existing) e.syncId: e};
    for (final item in items) {
      final row = bySync[item.syncId];
      if (row == null) {
        await _db.into(_db.ledgers).insert(
              LedgersCompanion.insert(
                name: item.name,
                syncId: item.syncId,
                updatedAt: Value(item.updatedAt),
                deletedAt: Value(item.deletedAt),
              ),
            );
      } else {
        await (_db.update(_db.ledgers)..where((t) => t.id.equals(row.id)))
            .write(
          LedgersCompanion(
            name: Value(item.name),
            updatedAt: Value(item.updatedAt),
            deletedAt: Value(item.deletedAt),
          ),
        );
      }
    }
  }

  Future<void> _applyBills(List<SyncBill> items) async {
    final ledgers = await _db.select(_db.ledgers).get();
    final ledgerId = {for (final l in ledgers) l.syncId: l.id};
    final cats = await (_db.select(_db.categories)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final tags = await (_db.select(_db.tags)..where((t) => t.deletedAt.isNull()))
        .get();
    final tagIdByName = {for (final t in tags) t.name: t.id};
    final existing = await _db.select(_db.transactions).get();
    final bySync = {for (final e in existing) e.syncId: e};

    int? categoryId(SyncBill bill) {
      final name = bill.categoryName;
      if (name == null || name.isEmpty) return null;
      for (final c in cats) {
        if (c.kind == bill.type && c.name == name) return c.id;
      }
      return null;
    }

    for (final item in items) {
      final lid = ledgerId[item.ledgerSyncId];
      if (lid == null) continue;
      final row = bySync[item.syncId];
      if (row == null) {
        final id = await _db.into(_db.transactions).insert(
              TransactionsCompanion.insert(
                ledgerId: lid,
                type: item.type,
                amount: item.amount,
                happenedAt: HappenedAt.toSecond(item.happenedAt),
                syncId: item.syncId,
                fingerprint: item.fingerprint,
                categoryId: Value(categoryId(item)),
                note: Value(item.note),
                source: Value(item.source),
                updatedAt: Value(item.updatedAt),
                deletedAt: Value(item.deletedAt),
              ),
            );
        await _replaceBillTags(id, item.tagNames, tagIdByName);
      } else {
        await (_db.update(_db.transactions)..where((t) => t.id.equals(row.id)))
            .write(
          TransactionsCompanion(
            ledgerId: Value(lid),
            type: Value(item.type),
            amount: Value(item.amount),
            happenedAt: Value(HappenedAt.toSecond(item.happenedAt)),
            fingerprint: Value(item.fingerprint),
            categoryId: Value(categoryId(item)),
            note: Value(item.note),
            source: Value(item.source),
            updatedAt: Value(item.updatedAt),
            deletedAt: Value(item.deletedAt),
          ),
        );
        await _replaceBillTags(row.id, item.tagNames, tagIdByName);
      }
    }

    final keep = {for (final item in items) item.syncId};
    final now = HappenedAt.now();
    for (final row in existing) {
      if (keep.contains(row.syncId) || row.deletedAt != null) continue;
      await (_db.update(_db.transactions)..where((t) => t.id.equals(row.id)))
          .write(
        TransactionsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }

    final latest = await _db.select(_db.transactions).get();
    for (final row in latest) {
      if (row.deletedAt == null) continue;
      if (now.difference(row.deletedAt!) <= WorkspaceMerge.billTombRetention) {
        continue;
      }
      await (_db.delete(_db.transactionTags)
            ..where((t) => t.transactionId.equals(row.id)))
          .go();
      await (_db.delete(_db.transactions)..where((t) => t.id.equals(row.id)))
          .go();
    }
  }

  Future<void> _replaceBillTags(
    int txId,
    List<String> names,
    Map<String, int> tagIdByName,
  ) async {
    await (_db.delete(_db.transactionTags)
          ..where((t) => t.transactionId.equals(txId)))
        .go();
    for (final name in names) {
      final tagId = tagIdByName[name];
      if (tagId == null) continue;
      await _db.into(_db.transactionTags).insert(
            TransactionTagsCompanion.insert(
              transactionId: txId,
              tagId: tagId,
            ),
          );
    }
  }

  Future<void> _fixCurrentLedger() async {
    final ledgers = LedgerRepository(_db);
    final current = await ledgers.readCurrentLedgerId();
    if (current != null) {
      final row = await ledgers.getById(current);
      if (row != null) return;
    }
    final live = await ledgers.getAll();
    if (live.isNotEmpty) {
      await ledgers.setCurrentLedgerId(live.first.id);
    }
  }
}
