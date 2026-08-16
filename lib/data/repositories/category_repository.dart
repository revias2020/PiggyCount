import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../services/custom_icon_service.dart';
import '../app_database.dart';

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
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .watch();
  }

  Future<List<Category>> listByKind(String kind) {
    return (_db.select(_db.categories)
          ..where((t) => t.kind.equals(kind))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  Future<List<Category>> listAll() {
    return (_db.select(_db.categories)
          ..orderBy([
            (t) => OrderingTerm.asc(t.kind),
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  Future<Category?> getById(int id) {
    return (_db.select(_db.categories)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<Category>> childrenOf(int parentId) {
    return (_db.select(_db.categories)
          ..where((t) => t.parentId.equals(parentId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  Future<int> countTransactions(int categoryId) async {
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.categoryId.equals(categoryId)))
        .get();
    return rows.length;
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
    if (parentId != null) {
      final parent = await getById(parentId);
      if (parent == null || parent.parentId != null) {
        throw StateError('子分类只能挂在主分类下');
      }
    }
    final siblings = await (_db.select(_db.categories)
          ..where((t) => t.kind.equals(kind))
          ..where(
            (t) => parentId == null
                ? t.parentId.isNull()
                : t.parentId.equals(parentId),
          ))
        .get();
    return _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            name: name.trim(),
            kind: kind,
            syncId: _uuid.v4(),
            parentId: Value(parentId),
            icon: Value(icon ?? 'category'),
            iconType: Value(iconType),
            customIconPath: Value(customIconPath),
            sortOrder: Value(sortOrder ?? siblings.length),
          ),
        );
  }

  /// 按 id 批量删除（不校验账单；调用方需自行筛选未使用分类）。
  Future<void> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final paths = <String>[];
    for (final id in ids) {
      final cat = await getById(id);
      if (cat?.customIconPath != null) paths.add(cat!.customIconPath!);
    }
    await _db.transaction(() async {
      for (final id in ids) {
        await (_db.delete(_db.categories)..where((t) => t.id.equals(id))).go();
      }
    });
    final icons = CustomIconService();
    for (final path in paths) {
      await icons.deleteCustomIcon(path);
    }
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

  Future<void> rename(int id, String name) async {
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(name: Value(name.trim())),
        );
  }

  Future<void> update({
    required int id,
    required String name,
    required String icon,
    String iconType = 'material',
    String? customIconPath,
  }) async {
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(
            name: Value(name.trim()),
            icon: Value(icon),
            iconType: Value(iconType),
            customIconPath: Value(customIconPath),
          ),
        );
  }

  Future<void> updateIcon({
    required int id,
    required String iconType,
    String? icon,
    String? customIconPath,
  }) async {
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(
            iconType: Value(iconType),
            icon: icon != null ? Value(icon) : const Value.absent(),
            customIconPath: Value(customIconPath),
          ),
        );
  }

  /// 重排同级分类：[orderedIds] 为同一 parent 下（或主分类列表）的 id 顺序。
  Future<void> reorder(List<int> orderedIds) async {
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.categories)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(CategoriesCompanion(sortOrder: Value(i)));
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
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(
            parentId: Value(newParentId),
            sortOrder: Value(siblings.length),
          ),
        );
  }

  /// 子分类提升为主分类。
  Future<void> promoteToMain(int id) async {
    final cat = await getById(id);
    if (cat == null || cat.parentId == null) return;
    final mains = await (_db.select(_db.categories)
          ..where((t) => t.kind.equals(cat.kind))
          ..where((t) => t.parentId.isNull()))
        .get();
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
          CategoriesCompanion(
            parentId: const Value(null),
            sortOrder: Value(mains.length),
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
