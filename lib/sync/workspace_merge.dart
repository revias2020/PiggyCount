import '../utils/bill_fingerprint.dart';
import 'workspace_models.dart';

/// 工作区合并：分类/标签 → 账本折合改写指纹 → 账单。ADR-042。
abstract final class WorkspaceMerge {
  static WorkspaceMergeResult merge({
    required WorkspaceSnapshot local,
    required WorkspaceSnapshot remote,
  }) {
    final groupRewrite = <String, String>{};
    final tagGroups = _foldNamed(
      _unionById(local.tagGroups, remote.tagGroups, (g) => g.syncId, _lwwGroup),
      nameOf: (g) => g.name,
      idOf: (g) => g.syncId,
      isLive: (g) => g.isLive,
      applyId: (g, id) => g.copyWith(syncId: id),
      tombstone: (g, at) => g.copyWith(deletedAt: at, updatedAt: at),
      lww: _lwwGroup,
      rewrite: groupRewrite,
    );

    var tags = _foldNamed(
      _unionById(local.tags, remote.tags, (t) => t.syncId, _lwwTag),
      nameOf: (t) => t.name,
      idOf: (t) => t.syncId,
      isLive: (t) => t.isLive,
      applyId: (t, id) => t.copyWith(syncId: id),
      tombstone: (t, at) => t.copyWith(deletedAt: at, updatedAt: at),
      lww: _lwwTag,
      rewrite: <String, String>{},
    );
    tags = [
      for (final t in tags)
        t.copyWith(
          groupSyncId: groupRewrite[t.groupSyncId] ?? t.groupSyncId,
        ),
    ];

    final catRewrite = <String, String>{};
    final foldedCats = <SyncCategory>[];
    for (final kind in const ['expense', 'income']) {
      final localKind = local.categories.where((c) => c.kind == kind).toList();
      final remoteKind = remote.categories.where((c) => c.kind == kind).toList();
      foldedCats.addAll(
        _foldNamed(
          _unionById(localKind, remoteKind, (c) => c.syncId, _lwwCategory),
          nameOf: (c) => c.name,
          idOf: (c) => c.syncId,
          isLive: (c) => c.isLive,
          applyId: (c, id) => c.copyWith(syncId: id),
          tombstone: (c, at) => c.copyWith(deletedAt: at, updatedAt: at),
          lww: _lwwCategory,
          rewrite: catRewrite,
        ),
      );
    }
    final rewrittenParents = [
      for (final c in foldedCats)
        c.parentSyncId == null
            ? c
            : c.copyWith(parentSyncId: catRewrite[c.parentSyncId] ?? c.parentSyncId),
    ];
    final categories = <SyncCategory>[];
    String? treeConflict;
    for (final kind in const ['expense', 'income']) {
      final normalized = _normalizeForest(
        rewrittenParents.where((c) => c.kind == kind).toList(),
      );
      if (normalized.conflict) {
        treeConflict = '同步后部分子分类将提升为主分类';
      }
      categories.addAll(normalized.categories);
    }

    final ledgerRewrite = <String, String>{};
    var ledgers = _foldNamed(
      _unionById(local.ledgers, remote.ledgers, (l) => l.syncId, _lwwLedger),
      nameOf: (l) => l.name,
      idOf: (l) => l.syncId,
      isLive: (l) => l.isLive,
      applyId: (l, id) => l.copyWith(syncId: id),
      tombstone: (l, at) => l.copyWith(deletedAt: at, updatedAt: at),
      lww: _lwwLedger,
      rewrite: ledgerRewrite,
    );

    final allBillsForResurrection = [
      ...local.bills,
      ...remote.bills,
    ];
    ledgers = [
      for (final ledger in ledgers)
        _maybeResurrect(ledger, allBillsForResurrection),
    ];

    String rewriteLedgerId(String id) => ledgerRewrite[id] ?? id;

    final rewrittenLocal = [
      for (final b in local.bills) _rewriteBillLedger(b, rewriteLedgerId),
    ];
    final rewrittenRemote = [
      for (final b in remote.bills) _rewriteBillLedger(b, rewriteLedgerId),
    ];
    final bills = _unionById(
      rewrittenLocal,
      rewrittenRemote,
      (b) => b.fingerprint,
      _lwwBill,
    );

    final merged = WorkspaceSnapshot(
      ledgers: ledgers,
      categories: categories,
      tagGroups: tagGroups,
      tags: tags,
      bills: bills,
    );

    return WorkspaceMergeResult(
      merged: merged,
      preview: SyncPreview(
        catalog: _sumCounts([
          _diff(
            local.categories.where((e) => e.isLive).map((e) => e.syncId),
            merged.categories,
            (e) => e.syncId,
            (e) => e.isLive,
            _categoryChanged,
            local.categories,
          ),
          _diff(
            local.tagGroups.where((e) => e.isLive).map((e) => e.syncId),
            merged.tagGroups,
            (e) => e.syncId,
            (e) => e.isLive,
            _groupChanged,
            local.tagGroups,
          ),
          _diff(
            local.tags.where((e) => e.isLive).map((e) => e.syncId),
            merged.tags,
            (e) => e.syncId,
            (e) => e.isLive,
            _tagChanged,
            local.tags,
          ),
        ]),
        ledgers: _diff(
          local.ledgers.where((e) => e.isLive).map((e) => e.syncId),
          merged.ledgers,
          (e) => e.syncId,
          (e) => e.isLive,
          _ledgerChanged,
          local.ledgers,
        ),
        bills: _diff(
          local.bills.where((e) => e.isLive).map((e) => e.fingerprint),
          merged.bills,
          (e) => e.fingerprint,
          (e) => e.isLive,
          _billChanged,
          local.bills,
        ),
        categoryTreeConflict: treeConflict,
      ),
    );
  }

  static SyncLedger _maybeResurrect(
    SyncLedger ledger,
    List<SyncBill> bills,
  ) {
    final deletedAt = ledger.deletedAt;
    if (deletedAt == null) return ledger;
    final later = bills.any(
      (b) =>
          b.ledgerSyncId == ledger.syncId && b.updatedAt.isAfter(deletedAt),
    );
    if (!later) return ledger;
    DateTime latest = deletedAt;
    for (final b in bills) {
      if (b.ledgerSyncId == ledger.syncId && b.updatedAt.isAfter(latest)) {
        latest = b.updatedAt;
      }
    }
    return ledger.copyWith(clearDeletedAt: true, updatedAt: latest);
  }

  static SyncBill _rewriteBillLedger(
    SyncBill bill,
    String Function(String) rewrite,
  ) {
    final ledgerId = rewrite(bill.ledgerSyncId);
    if (ledgerId == bill.ledgerSyncId) return bill;
    return bill.copyWith(
      ledgerSyncId: ledgerId,
      fingerprint: BillFingerprint.build(
        ledgerSyncId: ledgerId,
        amount: bill.amount,
        happenedAt: bill.happenedAt,
      ),
    );
  }

  static ({List<SyncCategory> categories, bool conflict}) _normalizeForest(
    List<SyncCategory> input,
  ) {
    final live = [for (final c in input) if (c.isLive) c];
    final childrenOf = <String, List<String>>{};
    for (final c in live) {
      final p = c.parentSyncId;
      if (p != null) {
        (childrenOf[p] ??= []).add(c.syncId);
      }
    }
    final promote = <String>{};
    for (final c in live) {
      if (c.parentSyncId == null) continue;
      final kids = childrenOf[c.syncId];
      if (kids != null && kids.isNotEmpty) {
        promote.addAll(kids);
      }
    }
    if (promote.isEmpty) {
      return (categories: input, conflict: false);
    }
    return (
      categories: [
        for (final c in input)
          promote.contains(c.syncId) ? c.copyWith(clearParent: true) : c,
      ],
      conflict: true,
    );
  }
}

List<T> _unionById<T>(
  List<T> local,
  List<T> remote,
  String Function(T) idOf,
  T Function(T a, T b) lww,
) {
  final map = <String, T>{};
  for (final item in local) {
    map[idOf(item)] = item;
  }
  for (final item in remote) {
    final id = idOf(item);
    final existing = map[id];
    map[id] = existing == null ? item : lww(existing, item);
  }
  return map.values.toList();
}

List<T> _foldNamed<T>(
  List<T> items, {
  required String Function(T) nameOf,
  required String Function(T) idOf,
  required bool Function(T) isLive,
  required T Function(T, String) applyId,
  required T Function(T, DateTime) tombstone,
  required T Function(T, T) lww,
  required Map<String, String> rewrite,
}) {
  final byId = {for (final item in items) idOf(item): item};
  final groups = <String, List<T>>{};
  for (final item in items) {
    if (!isLive(item)) continue;
    (groups[nameOf(item)] ??= []).add(item);
  }
  for (final group in groups.values) {
    if (group.length < 2) continue;
    final ids = [for (final item in group) idOf(item)]..sort();
    final surviving = ids.first;
    var winner = group.first;
    for (final item in group.skip(1)) {
      winner = lww(winner, item);
    }
    winner = applyId(winner, surviving);
    byId[surviving] = winner;
    final at = _updatedAtOf(winner as Object).add(const Duration(microseconds: 1));
    for (final id in ids.skip(1)) {
      rewrite[id] = surviving;
      final old = byId[id];
      if (old == null) continue;
      byId[id] = tombstone(old, at);
    }
  }
  return byId.values.toList();
}

DateTime _updatedAtOf(Object item) {
  if (item is SyncLedger) return item.updatedAt;
  if (item is SyncCategory) return item.updatedAt;
  if (item is SyncTagGroup) return item.updatedAt;
  if (item is SyncTag) return item.updatedAt;
  if (item is SyncBill) return item.updatedAt;
  throw ArgumentError('unknown entity');
}

T _pickLww<T>({
  required T a,
  required T b,
  required DateTime aAt,
  required DateTime bAt,
  required String aId,
  required String bId,
}) {
  if (aAt.isAfter(bAt)) return a;
  if (bAt.isAfter(aAt)) return b;
  return aId.compareTo(bId) <= 0 ? a : b;
}

SyncLedger _lwwLedger(SyncLedger a, SyncLedger b) => _pickLww(
      a: a,
      b: b,
      aAt: a.updatedAt,
      bAt: b.updatedAt,
      aId: a.syncId,
      bId: b.syncId,
    );

SyncCategory _lwwCategory(SyncCategory a, SyncCategory b) => _pickLww(
      a: a,
      b: b,
      aAt: a.updatedAt,
      bAt: b.updatedAt,
      aId: a.syncId,
      bId: b.syncId,
    );

SyncTagGroup _lwwGroup(SyncTagGroup a, SyncTagGroup b) => _pickLww(
      a: a,
      b: b,
      aAt: a.updatedAt,
      bAt: b.updatedAt,
      aId: a.syncId,
      bId: b.syncId,
    );

SyncTag _lwwTag(SyncTag a, SyncTag b) => _pickLww(
      a: a,
      b: b,
      aAt: a.updatedAt,
      bAt: b.updatedAt,
      aId: a.syncId,
      bId: b.syncId,
    );

SyncBill _lwwBill(SyncBill a, SyncBill b) => _pickLww(
      a: a,
      b: b,
      aAt: a.updatedAt,
      bAt: b.updatedAt,
      aId: a.fingerprint,
      bId: b.fingerprint,
    );

SyncPreviewCounts _diff<T>(
  Iterable<String> localLiveIds,
  List<T> merged,
  String Function(T) idOf,
  bool Function(T) isLive,
  bool Function(T local, T merged) changed,
  List<T> localAll,
) {
  final localLive = localLiveIds.toSet();
  final mergedById = {for (final e in merged) idOf(e): e};
  final localById = {for (final e in localAll) idOf(e): e};
  var added = 0;
  var updated = 0;
  var deleted = 0;
  for (final e in merged) {
    final id = idOf(e);
    if (isLive(e)) {
      if (!localLive.contains(id)) {
        added++;
      } else {
        final loc = localById[id];
        if (loc != null && changed(loc, e)) updated++;
      }
    }
  }
  for (final id in localLive) {
    final m = mergedById[id];
    if (m == null || !isLive(m)) deleted++;
  }
  return SyncPreviewCounts(added: added, updated: updated, deleted: deleted);
}

SyncPreviewCounts _sumCounts(List<SyncPreviewCounts> parts) {
  var added = 0;
  var updated = 0;
  var deleted = 0;
  for (final p in parts) {
    added += p.added;
    updated += p.updated;
    deleted += p.deleted;
  }
  return SyncPreviewCounts(added: added, updated: updated, deleted: deleted);
}

bool _ledgerChanged(SyncLedger a, SyncLedger b) =>
    a.name != b.name || a.deletedAt != b.deletedAt;

bool _categoryChanged(SyncCategory a, SyncCategory b) =>
    a.name != b.name ||
    a.parentSyncId != b.parentSyncId ||
    a.icon != b.icon ||
    a.deletedAt != b.deletedAt;

bool _groupChanged(SyncTagGroup a, SyncTagGroup b) =>
    a.name != b.name || a.scope != b.scope || a.deletedAt != b.deletedAt;

bool _tagChanged(SyncTag a, SyncTag b) =>
    a.name != b.name ||
    a.groupSyncId != b.groupSyncId ||
    a.color != b.color ||
    a.deletedAt != b.deletedAt;

bool _billChanged(SyncBill a, SyncBill b) =>
    a.amount != b.amount ||
    a.happenedAt != b.happenedAt ||
    a.categoryName != b.categoryName ||
    a.note != b.note ||
    a.ledgerSyncId != b.ledgerSyncId ||
    a.deletedAt != b.deletedAt;
