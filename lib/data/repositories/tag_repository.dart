import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';

/// 标签组 + 其下标签（按 sortOrder / id）。
class TagGroupBundle {
  const TagGroupBundle({required this.group, required this.tags});

  final TagGroup group;
  final List<Tag> tags;

  bool get isString => group.kind == TagGroupKind.string;
  bool get isNumber => group.kind == TagGroupKind.number;
}

/// 标签与标签组读写。
class TagRepository {
  TagRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const defaultGroupName = '默认';

  Stream<List<Tag>> watchAll() {
    return (_db.select(_db.tags)..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.id),
        ]))
        .watch();
  }

  Future<List<Tag>> getAll() {
    return (_db.select(_db.tags)..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.id),
        ]))
        .get();
  }

  Stream<List<TagGroup>> watchGroups() {
    return (_db.select(_db.tagGroups)..orderBy([
          (g) => OrderingTerm.asc(g.sortOrder),
          (g) => OrderingTerm.asc(g.id),
        ]))
        .watch();
  }

  Future<List<TagGroup>> getGroups() {
    return (_db.select(_db.tagGroups)..orderBy([
          (g) => OrderingTerm.asc(g.sortOrder),
          (g) => OrderingTerm.asc(g.id),
        ]))
        .get();
  }

  /// 组或标签任一变化都推送（仅 watch 组表时，增删标签 UI 不会刷新）。
  Stream<List<TagGroupBundle>> watchBundles() {
    return _db
        .customSelect(
          'SELECT 1 AS _',
          readsFrom: {_db.tagGroups, _db.tags},
        )
        .watch()
        .asyncMap((_) => getBundles());
  }

  Future<List<TagGroupBundle>> getBundles() async {
    final groups = await getGroups();
    final tags = await getAll();
    return [
      for (final g in groups)
        TagGroupBundle(
          group: g,
          tags: tags.where((t) => t.groupId == g.id).toList(),
        ),
    ];
  }

  Future<TagGroup?> findGroupByName(String name) async {
    final rows = await (_db.select(_db.tagGroups)
          ..where((g) => g.name.equals(name.trim())))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> ensureDefaultGroupId() async {
    final existing = await findGroupByName(defaultGroupName);
    if (existing != null) return existing.id;
    return createGroup(name: defaultGroupName, kind: TagGroupKind.string);
  }

  Future<int> createGroup({
    required String name,
    required String kind,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('组名不能为空');
    }
    if (kind != TagGroupKind.string && kind != TagGroupKind.number) {
      throw ArgumentError('无效的标签组类型');
    }
    return _db.into(_db.tagGroups).insert(
          TagGroupsCompanion.insert(
            name: trimmed,
            kind: kind,
            syncId: _uuid.v4(),
          ),
        );
  }

  Future<void> renameGroup(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await (_db.update(_db.tagGroups)..where((g) => g.id.equals(id))).write(
          TagGroupsCompanion(name: Value(trimmed)),
        );
  }

  /// 组内仍有标签则抛错（禁删）。
  Future<void> deleteGroup(int id) async {
    final count = await (_db.select(_db.tags)
          ..where((t) => t.groupId.equals(id)))
        .get();
    if (count.isNotEmpty) {
      throw StateError('组内仍有标签，请先移出或删除');
    }
    await (_db.delete(_db.tagGroups)..where((g) => g.id.equals(id))).go();
  }

  Future<int> create(
    String name, {
    int? groupId,
    double? rangeMin,
    double? rangeMax,
  }) async {
    final gid = groupId ?? await ensureDefaultGroupId();
    final group = await (_db.select(_db.tagGroups)
          ..where((g) => g.id.equals(gid)))
        .getSingle();

    double? min = rangeMin;
    double? max = rangeMax;
    if (group.kind == TagGroupKind.string) {
      min = null;
      max = null;
    } else {
      _assertValidRange(min: min, max: max);
      await _assertNoOverlap(
        groupId: gid,
        rangeMin: min,
        rangeMax: max,
      );
    }

    return _db.into(_db.tags).insert(
          TagsCompanion.insert(
            name: name.trim(),
            groupId: gid,
            rangeMin: Value(min),
            rangeMax: Value(max),
            syncId: _uuid.v4(),
          ),
        );
  }

  Future<void> rename(int id, String name) async {
    await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
          TagsCompanion(name: Value(name.trim())),
        );
  }

  Future<void> updateTag({
    required int id,
    String? name,
    int? groupId,
    double? rangeMin,
    double? rangeMax,
    bool clearRangeMax = false,
  }) async {
    final tag = await (_db.select(_db.tags)..where((t) => t.id.equals(id)))
        .getSingle();
    final gid = groupId ?? tag.groupId;
    final group = await (_db.select(_db.tagGroups)
          ..where((g) => g.id.equals(gid)))
        .getSingle();

    double? min = rangeMin ?? tag.rangeMin;
    double? max = clearRangeMax ? null : (rangeMax ?? tag.rangeMax);

    if (group.kind == TagGroupKind.string) {
      min = null;
      max = null;
    } else {
      _assertValidRange(min: min, max: max);
      await _assertNoOverlap(
        groupId: gid,
        rangeMin: min,
        rangeMax: max,
        excludeTagId: id,
      );
    }

    await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
          TagsCompanion(
            name: name != null ? Value(name.trim()) : const Value.absent(),
            groupId: Value(gid),
            rangeMin: Value(min),
            rangeMax: Value(max),
          ),
        );
  }

  Future<void> delete(int id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.transactionTags)..where((t) => t.tagId.equals(id)))
          .go();
      await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 金额是否落入数值标签区间 `[min, max)`。
  static bool amountInRange(double amount, Tag tag) {
    final min = tag.rangeMin ?? double.negativeInfinity;
    final max = tag.rangeMax;
    if (amount < min) return false;
    if (max != null && amount >= max) return false;
    return true;
  }

  void _assertValidRange({required double? min, required double? max}) {
    if (min == null) {
      throw ArgumentError('数值组标签必须设置下限');
    }
    if (max != null && max <= min) {
      throw ArgumentError('上限必须大于下限');
    }
  }

  Future<void> _assertNoOverlap({
    required int groupId,
    required double? rangeMin,
    required double? rangeMax,
    int? excludeTagId,
  }) async {
    final others = await (_db.select(_db.tags)
          ..where((t) => t.groupId.equals(groupId)))
        .get();
    for (final o in others) {
      if (excludeTagId != null && o.id == excludeTagId) continue;
      if (_rangesOverlap(
        aMin: rangeMin!,
        aMax: rangeMax,
        bMin: o.rangeMin ?? double.negativeInfinity,
        bMax: o.rangeMax,
      )) {
        throw StateError('与「${o.name}」区间重叠');
      }
    }
  }

  /// 两段 `[min, max)` 是否相交（max==null 视为 +∞）。
  static bool _rangesOverlap({
    required double aMin,
    required double? aMax,
    required double bMin,
    required double? bMax,
  }) {
    final aHi = aMax ?? double.infinity;
    final bHi = bMax ?? double.infinity;
    return aMin < bHi && bMin < aHi;
  }
}
