import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../utils/happened_at.dart';
import '../../utils/tag_colors.dart';
import '../app_database.dart';
import '../default_catalog_applier.dart';

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

  /// 无 groupId 时的落点组名（ADR-039；「外部导入」）。
  static String get ungroupedFallbackGroupName => '外部导入';

  /// 软删时改名腾出 UNIQUE，载荷里再剥前缀还原。
  static String tombstoneName(int id, String name) => '__deleted_${id}__$name';

  static String originalName(String stored, {required bool deleted}) {
    if (!deleted) return stored;
    final m = RegExp(r'^__deleted_\d+__').firstMatch(stored);
    if (m == null) return stored;
    return stored.substring(m.end);
  }

  Stream<List<Tag>> watchAll() {
    return (_db.select(_db.tags)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .watch();
  }

  Future<List<Tag>> getAll() {
    return (_db.select(_db.tags)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  Stream<List<TagGroup>> watchGroups() {
    return (_db.select(_db.tagGroups)
          ..where((g) => g.deletedAt.isNull())
          ..orderBy([
            (g) => OrderingTerm.asc(g.sortOrder),
            (g) => OrderingTerm.asc(g.id),
          ]))
        .watch();
  }

  Future<List<TagGroup>> getGroups() {
    return (_db.select(_db.tagGroups)
          ..where((g) => g.deletedAt.isNull())
          ..orderBy([
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
          ..where((g) => g.name.equals(name.trim()))
          ..where((g) => g.deletedAt.isNull()))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<bool> groupNameTaken(String name, {int? excludeId}) async {
    final trimmed = name.trim();
    final q = _db.select(_db.tagGroups)
      ..where((g) => g.name.equals(trimmed))
      ..where((g) => g.deletedAt.isNull());
    if (excludeId != null) {
      q.where((g) => g.id.isNotValue(excludeId));
    }
    return (await q.get()).isNotEmpty;
  }

  Future<bool> nameTaken(String name, {int? excludeId}) async {
    final trimmed = name.trim();
    final q = _db.select(_db.tags)
      ..where((t) => t.name.equals(trimmed))
      ..where((t) => t.deletedAt.isNull());
    if (excludeId != null) {
      q.where((t) => t.id.isNotValue(excludeId));
    }
    return (await q.get()).isNotEmpty;
  }

  /// 确保「外部导入」组存在，供无 groupId 创建使用（ADR-039）。
  Future<int> ensureUngroupedFallbackGroupId() async {
    final existing = await findGroupByName(ungroupedFallbackGroupName);
    if (existing != null) return existing.id;
    return createGroup(
      name: ungroupedFallbackGroupName,
      kind: TagGroupKind.string,
      scope: TagGroupScope.both,
    );
  }

  Future<int> createGroup({
    required String name,
    required String kind,
    String scope = TagGroupScope.both,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('组名不能为空');
    }
    if (kind != TagGroupKind.string && kind != TagGroupKind.number) {
      throw ArgumentError('无效的标签组类型');
    }
    if (scope != TagGroupScope.both &&
        scope != TagGroupScope.expense &&
        scope != TagGroupScope.income) {
      throw ArgumentError('无效的生效范围');
    }
    if (await groupNameTaken(trimmed)) {
      throw StateError('已存在同名标签组');
    }
    final now = HappenedAt.now();
    return _db.into(_db.tagGroups).insert(
          TagGroupsCompanion.insert(
            name: trimmed,
            kind: kind,
            scope: Value(scope),
            syncId: _uuid.v4(),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> updateGroup({
    required int id,
    String? name,
    String? scope,
  }) async {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isEmpty) return;
    if (scope != null &&
        scope != TagGroupScope.both &&
        scope != TagGroupScope.expense &&
        scope != TagGroupScope.income) {
      throw ArgumentError('无效的生效范围');
    }
    if (trimmed != null && await groupNameTaken(trimmed, excludeId: id)) {
      throw StateError('已存在同名标签组');
    }
    final now = HappenedAt.now();
    await (_db.update(_db.tagGroups)..where((g) => g.id.equals(id))).write(
          TagGroupsCompanion(
            name: trimmed != null ? Value(trimmed) : const Value.absent(),
            scope: scope != null ? Value(scope) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> renameGroup(int id, String name) async {
    await updateGroup(id: id, name: name);
  }

  /// 组内仍有标签则抛错（禁删）。
  Future<void> deleteGroup(int id) async {
    final count = await (_db.select(_db.tags)
          ..where((t) => t.groupId.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    if (count.isNotEmpty) {
      throw StateError('组内仍有标签，请先移出或删除');
    }
    final group = await (_db.select(_db.tagGroups)..where((g) => g.id.equals(id)))
        .getSingleOrNull();
    if (group == null) return;
    final now = HappenedAt.now();
    final liveName = originalName(group.name, deleted: group.deletedAt != null);
    await (_db.update(_db.tagGroups)..where((g) => g.id.equals(id))).write(
          TagGroupsCompanion(
            name: Value(tombstoneName(id, liveName)),
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<int> create(
    String name, {
    int? groupId,
    String? color,
    double? rangeMin,
    double? rangeMax,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('标签名称不能为空');
    }
    if (await nameTaken(trimmed)) {
      throw StateError('已存在同名标签');
    }
    final gid = groupId ?? await ensureUngroupedFallbackGroupId();
    final group = await (_db.select(_db.tagGroups)
          ..where((g) => g.id.equals(gid))
          ..where((g) => g.deletedAt.isNull()))
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

    final now = HappenedAt.now();
    return _db.into(_db.tags).insert(
          TagsCompanion.insert(
            name: trimmed,
            groupId: gid,
            color: Value(color ?? TagColors.random()),
            rangeMin: Value(min),
            rangeMax: Value(max),
            syncId: _uuid.v4(),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> rename(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('标签名称不能为空');
    }
    if (await nameTaken(trimmed, excludeId: id)) {
      throw StateError('已存在同名标签');
    }
    final now = HappenedAt.now();
    await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
          TagsCompanion(
            name: Value(trimmed),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> updateTag({
    required int id,
    String? name,
    String? color,
    int? groupId,
    double? rangeMin,
    double? rangeMax,
    bool clearRangeMax = false,
  }) async {
    final tag = await (_db.select(_db.tags)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingle();
    final trimmed = name?.trim();
    if (trimmed != null) {
      if (trimmed.isEmpty) {
        throw ArgumentError('标签名称不能为空');
      }
      if (await nameTaken(trimmed, excludeId: id)) {
        throw StateError('已存在同名标签');
      }
    }
    final gid = groupId ?? tag.groupId;
    final group = await (_db.select(_db.tagGroups)
          ..where((g) => g.id.equals(gid))
          ..where((g) => g.deletedAt.isNull()))
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

    final now = HappenedAt.now();
    await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
          TagsCompanion(
            name: trimmed != null ? Value(trimmed) : const Value.absent(),
            color: color != null ? Value(color) : const Value.absent(),
            groupId: Value(gid),
            rangeMin: Value(min),
            rangeMax: Value(max),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> delete(int id) async {
    final now = HappenedAt.now();
    await _db.transaction(() async {
      await (_db.delete(_db.transactionTags)..where((t) => t.tagId.equals(id)))
          .go();
      final tag = await (_db.select(_db.tags)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (tag == null) return;
      final liveName = originalName(tag.name, deleted: tag.deletedAt != null);
      await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
            TagsCompanion(
              name: Value(tombstoneName(id, liveName)),
              deletedAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    });
  }

  /// 删除未挂到任何账单的标签；返回删除条数。
  Future<int> clearUnused() async {
    final all = await getAll();
    final unused = <int>[];
    for (final t in all) {
      final links = await (_db.select(_db.transactionTags)
            ..where((x) => x.tagId.equals(t.id)))
          .get();
      if (links.isEmpty) unused.add(t.id);
    }
    if (unused.isEmpty) return 0;
    for (final id in unused) {
      await delete(id);
    }
    return unused.length;
  }

  /// 合并补缺默认标签组与标签。
  Future<int> restoreDefaults() {
    return DefaultCatalogApplier(_db).ensureTags();
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
          ..where((t) => t.groupId.equals(groupId))
          ..where((t) => t.deletedAt.isNull()))
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
