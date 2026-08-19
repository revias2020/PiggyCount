import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import 'default_catalog.dart';

/// 将 [DefaultCatalog] 合并写入库（新库 onCreate、恢复默认共用）。
class DefaultCatalogApplier {
  DefaultCatalogApplier(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// 补缺默认分类。
  Future<({int created, int removedObsolete})> ensureCategories() async {
    var created = 0;
    created += await _ensureKindTree('expense', DefaultCatalog.expenseTree);
    created += await _ensureKindTree('income', DefaultCatalog.incomeMains);
    return (created: created, removedObsolete: 0);
  }

  Future<int> ensureTags() async {
    var created = 0;
    for (final g in DefaultCatalog.tagGroups) {
      created += await _ensureTagGroup(g);
    }
    return created;
  }

  Future<int> _ensureKindTree(
    String kind,
    List<DefaultMainCategory> tree,
  ) async {
    var created = 0;
    final all = await (_db.select(_db.categories)
          ..where((t) => t.kind.equals(kind))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final byName = {for (final c in all) c.name: c};

    for (var i = 0; i < tree.length; i++) {
      final main = tree[i];
      var parent = byName[main.name];
      if (parent == null) {
        final id = await _db.into(_db.categories).insert(
              CategoriesCompanion.insert(
                name: main.name,
                kind: kind,
                syncId: _uuid.v4(),
                icon: Value(main.icon),
                sortOrder: Value(i),
              ),
            );
        parent = await (_db.select(_db.categories)
              ..where((t) => t.id.equals(id)))
            .getSingle();
        byName[main.name] = parent;
        created++;
      } else if (parent.parentId != null) {
        // 同名已在别处：跳过整棵子树
        continue;
      }

      for (var j = 0; j < main.children.length; j++) {
        final child = main.children[j];
        if (byName.containsKey(child.name)) continue;

        await _db.into(_db.categories).insert(
              CategoriesCompanion.insert(
                name: child.name,
                kind: kind,
                syncId: _uuid.v4(),
                icon: Value(child.icon),
                parentId: Value(parent.id),
                sortOrder: Value(j),
              ),
            );
        // 标记名称已占用，避免同批重复
        byName[child.name] = parent;
        created++;
      }
    }
    return created;
  }

  Future<int> _ensureTagGroup(DefaultTagGroup def) async {
    var created = 0;
    final existing = await (_db.select(_db.tagGroups)
          ..where((g) => g.name.equals(def.name))
          ..where((g) => g.deletedAt.isNull()))
        .get();
    late final int groupId;
    if (existing.isEmpty) {
      groupId = await _db.into(_db.tagGroups).insert(
            TagGroupsCompanion.insert(
              name: def.name,
              kind: def.kind,
              scope: Value(def.scope),
              syncId: _uuid.v4(),
            ),
          );
      created++;
    } else {
      groupId = existing.first.id;
      // 若 scope 仍是默认 both 而目录要求更窄，可补写（仅当仍是 both 且目标非 both）
      if (existing.first.scope == TagGroupScope.both &&
          def.scope != TagGroupScope.both) {
        await (_db.update(_db.tagGroups)..where((g) => g.id.equals(groupId)))
            .write(TagGroupsCompanion(scope: Value(def.scope)));
      }
    }

    final tags = await (_db.select(_db.tags)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final names = {for (final t in tags) t.name};

    for (var i = 0; i < def.tags.length; i++) {
      final t = def.tags[i];
      if (names.contains(t.name)) continue;
      await _db.into(_db.tags).insert(
            TagsCompanion.insert(
              name: t.name,
              groupId: groupId,
              color: Value(t.color),
              rangeMin: Value(t.rangeMin),
              rangeMax: Value(t.rangeMax),
              sortOrder: Value(i),
              syncId: _uuid.v4(),
            ),
          );
      names.add(t.name);
      created++;
    }
    return created;
  }
}
