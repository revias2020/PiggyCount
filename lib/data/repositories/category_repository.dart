import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../utils/happened_at.dart';
import '../app_database.dart';
import '../default_catalog_applier.dart';

/// 删除分类的结果（含账单拦截信息）。
sealed class CategoryDeleteResult {
  const CategoryDeleteResult();
}

class CategoryDeleteOk extends CategoryDeleteResult {
  const CategoryDeleteOk();
}

/// 因存在账单而无法删除。
class CategoryDeleteBlocked extends CategoryDeleteResult {
  const CategoryDeleteBlocked({
    this.selfHasBills = false,
    this.childNamesWithBills = const [],
  });

  /// 主分类或子分类自身挂有账单。
  final bool selfHasBills;

  /// 主分类删除时：哪些子分类下有账单。
  final List<String> childNamesWithBills;
}

/// 「改为子类」前置检查结果。
sealed class DemoteCheck {
  const DemoteCheck();
}

class DemoteAllowed extends DemoteCheck {
  const DemoteAllowed();
}

class DemoteBlockedHasChildren extends DemoteCheck {
  const DemoteBlockedHasChildren();
}

/// 分类读写；固定两层：主分类（parentId 空）/ 子分类。
class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Category>> watchByKind(String kind) {
    return (_db.select(_db.categories)
          ..where((t) => t.kind.equals(kind))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .watch();
  }

  Future<List<Category>> listByKind(String kind) {
    return (_db.select(_db.categories)
          ..where((t) => t.kind.equals(kind))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  Future<List<Category>> listAll() {
    return (_db.select(_db.categories)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.kind),
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  Future<Category?> getById(int id) {
    return (_db.select(_db.categories)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<List<Category>> childrenOf(int parentId) {
    return (_db.select(_db.categories)
          ..where((t) => t.parentId.equals(parentId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  Future<int> countTransactions(int categoryId) async {
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.categoryId.equals(categoryId))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    return rows.length;
  }

  /// 同一收支类型内是否已有同名（主+子一起算）。
  Future<bool> nameTaken(
    String kind,
    String name, {
    int? excludeId,
  }) async {
    final trimmed = name.trim();
    final q = _db.select(_db.categories)
      ..where((t) => t.kind.equals(kind))
      ..where((t) => t.name.equals(trimmed))
      ..where((t) => t.deletedAt.isNull());
    if (excludeId != null) {
      q.where((t) => t.id.isNotValue(excludeId));
    }
    return (await q.get()).isNotEmpty;
  }

  Future<int> create({
    required String name,
    required String kind,
    int? parentId,
    String? icon,
    int? sortOrder,
    String iconType = 'material',
    String? customIconPath,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('分类名称不能为空');
    }
    if (await nameTaken(kind, trimmed)) {
      throw StateError('已存在同名分类');
    }
    if (parentId != null) {
      final parent = await getById(parentId);
      if (parent == null || parent.parentId != null) {
        throw StateError('子分类只能挂在主分类下');
      }
    }
    final siblings = await (_db.select(_db.categories)
          ..where((t) => t.kind.equals(kind))
          ..where((t) => t.deletedAt.isNull())
          ..where(
            (t) => parentId == null
                ? t.parentId.isNull()
                : t.parentId.equals(parentId),
          ))
        .get();
    final now = HappenedAt.now();
    return _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            name: trimmed,
            kind: kind,
            syncId: _uuid.v4(),
            parentId: Value(parentId),
            icon: Value(icon ?? 'category'),
            iconType: Value(iconType),
            customIconPath: Value(customIconPath),
            sortOrder: Value(sortOrder ?? siblings.length),
            updatedAt: Value(now),
          ),
        );
  }

  /// 按 id 批量软删（不校验账单；调用方需自行筛选未使用分类）。
  Future<void> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final now = HappenedAt.now();
    await _db.transaction(() async {
      for (final id in ids) {
        await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
              CategoriesCompanion(
                deletedAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  /// 删除无账单分类。主分类会把子分类账单计入占用；返回删除条数。
  Future<int> clearUnused() async {
    final all = await listAll();
    final unused = <int>[];
    for (final c in all) {
      var count = await countTransactions(c.id);
      if (c.parentId == null) {
        for (final child in all.where((x) => x.parentId == c.id)) {
          count += await countTransactions(child.id);
        }
      }
      if (count == 0) unused.add(c.id);
    }
    await deleteByIds(unused);
    return unused.length;
  }

  /// 合并补缺默认分类树（ADR-039：不再按名清理「生活日用」）。
  Future<({int created, int removedObsolete})> restoreDefaults() {
    return DefaultCatalogApplier(_db).ensureCategories();
  }

  Future<void> rename(int id, String name) async {
    final cat = await getById(id);
    if (cat == null) return;
    final trimmed = name.trim();
    if (await nameTaken(cat.kind, trimmed, excludeId: id)) {
      throw StateError('已存在同名分类');
    }
    final now = HappenedAt.now();
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(
            name: Value(trimmed),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> update({
    required int id,
    required String name,
    required String icon,
    String iconType = 'material',
    String? customIconPath,
  }) async {
    final cat = await getById(id);
    if (cat == null) return;
    final trimmed = name.trim();
    if (await nameTaken(cat.kind, trimmed, excludeId: id)) {
      throw StateError('已存在同名分类');
    }
    final now = HappenedAt.now();
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(
            name: Value(trimmed),
            icon: Value(icon),
            iconType: Value(iconType),
            customIconPath: Value(customIconPath),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> updateIcon({
    required int id,
    required String iconType,
    String? icon,
    String? customIconPath,
  }) async {
    final now = HappenedAt.now();
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(
            iconType: Value(iconType),
            icon: icon != null ? Value(icon) : const Value.absent(),
            customIconPath: Value(customIconPath),
            updatedAt: Value(now),
          ),
        );
  }

  /// 重排同级分类：[orderedIds] 为同一 parent 下（或主分类列表）的 id 顺序。
  Future<void> reorder(List<int> orderedIds) async {
    final now = HappenedAt.now();
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.categories)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(
          CategoriesCompanion(
            sortOrder: Value(i),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  Future<DemoteCheck> canDemoteToChild(int id) async {
    final children = await childrenOf(id);
    if (children.isNotEmpty) return const DemoteBlockedHasChildren();
    return const DemoteAllowed();
  }

  /// 将主分类降为 [newParentId] 下的子分类；或将子分类改挂。
  Future<void> moveUnderParent({
    required int id,
    required int newParentId,
  }) async {
    if (id == newParentId) {
      throw StateError('不能挂到自己下面');
    }
    final cat = await getById(id);
    final parent = await getById(newParentId);
    if (cat == null || parent == null) throw StateError('分类不存在');
    if (parent.parentId != null) {
      throw StateError('目标必须是主分类');
    }
    if (cat.parentId == null) {
      final check = await canDemoteToChild(id);
      if (check is DemoteBlockedHasChildren) {
        throw StateError('该分类下存在子分类，无法调整');
      }
    }
    final siblings = await childrenOf(newParentId);
    final now = HappenedAt.now();
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(
            parentId: Value(newParentId),
            sortOrder: Value(siblings.length),
            updatedAt: Value(now),
          ),
        );
  }

  /// 子分类提升为主分类。
  Future<void> promoteToMain(int id) async {
    final cat = await getById(id);
    if (cat == null || cat.parentId == null) return;
    final mains = await (_db.select(_db.categories)
          ..where((t) => t.kind.equals(cat.kind))
          ..where((t) => t.parentId.isNull())
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final now = HappenedAt.now();
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(
            parentId: const Value(null),
            sortOrder: Value(mains.length),
            updatedAt: Value(now),
          ),
        );
  }

  /// 按锁定规则删除；失败返回 [CategoryDeleteBlocked]，成功 [CategoryDeleteOk]。
  Future<CategoryDeleteResult> deleteGuarded(int id) async {
    final cat = await getById(id);
    if (cat == null) return const CategoryDeleteOk();

    if (cat.parentId != null) {
      // 子分类：有账单则禁删
      final n = await countTransactions(id);
      if (n > 0) {
        return const CategoryDeleteBlocked(selfHasBills: true);
      }
      await deleteByIds([id]);
      return const CategoryDeleteOk();
    }

    // 主分类
    final selfCount = await countTransactions(id);
    if (selfCount > 0) {
      return const CategoryDeleteBlocked(selfHasBills: true);
    }

    final children = await childrenOf(id);
    final blockedNames = <String>[];
    for (final c in children) {
      final n = await countTransactions(c.id);
      if (n > 0) blockedNames.add(c.name);
    }
    if (blockedNames.isNotEmpty) {
      return CategoryDeleteBlocked(childNamesWithBills: blockedNames);
    }

    await deleteByIds([
      ...children.map((c) => c.id),
      id,
    ]);
    return const CategoryDeleteOk();
  }
}
