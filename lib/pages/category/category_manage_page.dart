import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../data/app_database.dart';
import '../../data/repositories/category_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/transaction_providers.dart';
import '../../services/csv/category_csv_service.dart';
import '../../services/custom_icon_service.dart';
import '../../services/system/local_export_service.dart';
import '../../styles/tokens.dart';
import '../../utils/category_icons.dart';
import '../../widgets/category_icon_view.dart';
import '../../widgets/import_progress_layer.dart';
import '../../widgets/page_status.dart';
import '../../widgets/workspace_sheet.dart';
import '../../widgets/pig_toast.dart';

/// 记账分类管理：主分类网格 + 详情弹层管子分类（固定两层）。
class CategoryManagePage extends ConsumerStatefulWidget {
  const CategoryManagePage({super.key});

  @override
  ConsumerState<CategoryManagePage> createState() => _CategoryManagePageState();
}

class _CategoryManagePageState extends ConsumerState<CategoryManagePage> {
  bool _busy = false;

  CategoryCsvService get _csv =>
      CategoryCsvService(ref.read(categoryRepositoryProvider));

  Future<void> _exportCategories() async {
    final scope = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出分类'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('仅支出分类'),
              onTap: () => Navigator.pop(ctx, 'expense'),
            ),
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('仅收入分类'),
              onTap: () => Navigator.pop(ctx, 'income'),
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('全部分类'),
              onTap: () => Navigator.pop(ctx, 'all'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final filterKind = scope == 'all' ? null : scope;
      final stamp = LocalExportService.fileStamp();
      final name = filterKind == null
          ? 'piggy_categories_$stamp.zip'
          : 'piggy_categories_${filterKind}_$stamp.zip';
      final dir = await LocalExportService.resolveDirectory();
      final path = p.join(dir.path, name);
      await _csv.exportZip(outputPath: path, filterKind: filterKind);
      final result = await LocalExportService.finalize(
        path: path,
        mimeType: 'application/zip',
        shareSubject: '小猪记账分类',
      );
      if (!mounted) return;
      PigToast.show(context, result.successMessage);
    } catch (e) {
      if (!mounted) return;
      PigToast.show(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importCategories() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt', 'yaml', 'yml', 'zip'],
    );
    if (file == null || !mounted) return;

    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择导入模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.merge_type),
              title: const Text('合并'),
              subtitle: const Text('保留现有分类，新增不存在的'),
              onTap: () => Navigator.pop(ctx, 'merge'),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('覆盖'),
              subtitle: const Text('清空未使用分类后导入'),
              onTap: () => Navigator.pop(ctx, 'overwrite'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    try {
      final result = await showImportProgressLayer(
        context: context,
        title: '正在导入分类',
        task: (report) {
          return _csv.importBytes(
            bytes,
            fileName: file.name,
            mode: mode,
            onProgress: report,
          );
        },
      );
      ref.invalidate(expenseCategoriesProvider);
      ref.invalidate(incomeCategoriesProvider);
      if (!mounted) return;
      PigToast.show(context, result.iconsImported > 0
                ? '导入完成：新增 ${result.imported} 个，跳过 ${result.skipped} 个，图标 ${result.iconsImported} 个'
                : '导入完成：新增 ${result.imported} 个，跳过 ${result.skipped} 个');
    } catch (e) {
      if (!mounted) return;
      PigToast.show(context, '导入失败：$e');
    }
  }

  Future<void> _clearUnused() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除未使用的分类'),
        content: const Text('将删除当前没有任何账单的分类（主分类须其下子分类也均无账单）。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await ref.read(categoryRepositoryProvider).clearUnused();
      ref.invalidate(expenseCategoriesProvider);
      ref.invalidate(incomeCategoriesProvider);
      if (!mounted) return;
      PigToast.show(context, '已清除 $n 个未使用分类');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认分类'),
        content: const Text('将按出厂清单补齐缺失的主分类与子分类，不会删除你自建的分类。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(categoryRepositoryProvider).restoreDefaults();
      ref.invalidate(expenseCategoriesProvider);
      ref.invalidate(incomeCategoriesProvider);
      if (!mounted) return;
      PigToast.show(context, '已补缺 ${r.created} 项'
            '${r.removedObsolete > 0 ? '，清理闲置旧分类 ${r.removedObsolete} 项' : ''}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenseAsync = ref.watch(expenseCategoriesProvider);
    final incomeAsync = ref.watch(incomeCategoriesProvider);
    final repo = ref.read(categoryRepositoryProvider);

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: const Text('记账分类管理'),
        actions: [
          IconButton(
            tooltip: '导入分类',
            onPressed: _busy ? null : _importCategories,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 48),
            visualDensity: VisualDensity.compact,
            icon: Image.asset(
              'assets/icons/category_import.png',
              width: 28,
              height: 28,
              color: IconTheme.of(context).color,
            ),
          ),
          IconButton(
            tooltip: '导出分类',
            onPressed: _busy ? null : _exportCategories,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 48),
            visualDensity: VisualDensity.compact,
            icon: Image.asset(
              'assets/icons/category_export.png',
              width: 28,
              height: 28,
              color: IconTheme.of(context).color,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            enabled: !_busy,
            onSelected: (v) {
              if (v == 'clear') {
                _clearUnused();
              } else if (v == 'restore') {
                _restoreDefaults();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('清除未使用的分类')),
              PopupMenuItem(value: 'restore', child: Text('恢复默认分类')),
            ],
          ),
        ],
      ),
      body: expenseAsync.when(
        loading: () => const AppLoading(message: '加载分类…'),
        error: (e, _) => AppErrorState(
          message: '分类加载失败',
          onRetry: () {
            ref.invalidate(expenseCategoriesProvider);
            ref.invalidate(incomeCategoriesProvider);
          },
        ),
        data: (expense) {
          return incomeAsync.when(
            loading: () => const AppLoading(message: '加载分类…'),
            error: (e, _) => AppErrorState(
              message: '分类加载失败',
              onRetry: () => ref.invalidate(incomeCategoriesProvider),
            ),
            data: (income) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  const Text(
                    '支出管理',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: PigTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MainCategorySection(
                    kind: 'expense',
                    all: expense,
                    repo: repo,
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    '收入管理',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: PigTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MainCategorySection(
                    kind: 'income',
                    all: income,
                    repo: repo,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _MainCategorySection extends StatefulWidget {
  const _MainCategorySection({
    required this.kind,
    required this.all,
    required this.repo,
  });

  final String kind;
  final List<Category> all;
  final CategoryRepository repo;

  @override
  State<_MainCategorySection> createState() => _MainCategorySectionState();
}

class _MainCategorySectionState extends State<_MainCategorySection> {
  late List<Category> _mains;

  Set<int> get _parentIdsWithChildren => widget.all
      .where((c) => c.parentId != null)
      .map((c) => c.parentId!)
      .toSet();

  @override
  void initState() {
    super.initState();
    _mains = _parentsOf(widget.all);
  }

  @override
  void didUpdateWidget(covariant _MainCategorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.all != widget.all) {
      _mains = _parentsOf(widget.all);
    }
  }

  List<Category> _parentsOf(List<Category> all) =>
      all.where((c) => c.parentId == null).toList(growable: false);

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= _mains.length ||
        newIndex >= _mains.length) {
      return;
    }
    setState(() {
      final item = _mains.removeAt(oldIndex);
      _mains.insert(newIndex, item);
    });
    await widget.repo.reorder(_mains.map((c) => c.id).toList(growable: false));
  }

  Future<void> _addMain() async {
    final result = await showCategoryEditSheet(
      context,
      title: '添加分类',
      kind: widget.kind,
    );
    if (result == null) return;
    final id = await widget.repo.create(
      name: result.name,
      kind: widget.kind,
      icon: result.icon,
      iconType: result.iconType,
      customIconPath: result.customIconPath,
    );
    await _finalizeCustomIcon(
      repo: widget.repo,
      categoryId: id,
      result: result,
    );
  }

  Future<void> _openDetail(Category main) async {
    await showWorkspaceSheet<void>(
      context,
      builder: (ctx) => _MainCategoryDetailSheet(
        main: main,
        kind: widget.kind,
        all: widget.all,
        repo: widget.repo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final withChildren = _parentIdsWithChildren;
    return Material(
      color: PigTokens.surface,
      borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: ReorderableGridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          dragEnabled: true,
          crossAxisCount: 5,
          crossAxisSpacing: 4,
          mainAxisSpacing: 12,
          childAspectRatio: 0.78,
          dragStartDelay: const Duration(milliseconds: 180),
          onReorder: _onReorder,
          footer: [
            _AddTile(key: const ValueKey('add'), onTap: _addMain),
          ],
          children: [
            for (final cat in _mains)
              _CategoryTile(
                key: ValueKey(cat.id),
                category: cat,
                showSubBadge: withChildren.contains(cat.id),
                onTap: () => _openDetail(cat),
              ),
          ],
        ),
      ),
    );
  }
}

class _MainCategoryDetailSheet extends StatefulWidget {
  const _MainCategoryDetailSheet({
    required this.main,
    required this.kind,
    required this.all,
    required this.repo,
  });

  final Category main;
  final String kind;
  final List<Category> all;
  final CategoryRepository repo;

  @override
  State<_MainCategoryDetailSheet> createState() =>
      _MainCategoryDetailSheetState();
}

class _MainCategoryDetailSheetState extends State<_MainCategoryDetailSheet> {
  late Category _main;
  late List<Category> _children;

  @override
  void initState() {
    super.initState();
    _main = widget.main;
    _syncChildren(widget.all);
  }

  @override
  void didUpdateWidget(covariant _MainCategoryDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.all != widget.all) {
      _syncChildren(widget.all);
      final refreshed =
          widget.all.where((c) => c.id == _main.id).firstOrNull;
      if (refreshed != null) _main = refreshed;
    }
  }

  void _syncChildren(List<Category> all) {
    _children = all
        .where((c) => c.parentId == _main.id)
        .toList(growable: false);
  }

  Future<void> _reload() async {
    final all = await widget.repo.listByKind(widget.kind);
    if (!mounted) return;
    setState(() {
      final refreshed = all.where((c) => c.id == _main.id).firstOrNull;
      if (refreshed != null) _main = refreshed;
      _syncChildren(all);
    });
  }

  Future<void> _editMain() async {
    final result = await showCategoryEditSheet(
      context,
      title: '编辑分类',
      kind: widget.kind,
      categoryId: _main.id,
      initialName: _main.name,
      initialIcon: _main.icon ?? 'category',
      initialIconType: _main.iconType,
      initialCustomIconPath: _main.customIconPath,
    );
    if (result == null) return;
    final oldPath = _main.customIconPath;
    await widget.repo.update(
      id: _main.id,
      name: result.name,
      icon: result.icon,
      iconType: result.iconType,
      customIconPath: result.customIconPath,
    );
    await _finalizeCustomIcon(
      repo: widget.repo,
      categoryId: _main.id,
      result: result,
      previousCustomPath: oldPath,
    );
    await _reload();
  }

  Future<void> _demoteMain() async {
    final check = await widget.repo.canDemoteToChild(_main.id);
    if (check is DemoteBlockedHasChildren) {
      if (!mounted) return;
      PigToast.show(context, '该分类下存在子分类，无法调整');
      return;
    }
    final parents = (await widget.repo.listByKind(widget.kind))
        .where((c) => c.parentId == null && c.id != _main.id)
        .toList(growable: false);
    if (!mounted) return;
    final target = await showSelectMainCategorySheet(
      context,
      titleName: _main.name,
      candidates: parents,
    );
    if (target == null) return;
    await widget.repo.moveUnderParent(id: _main.id, newParentId: target.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteMain() async {
    final result = await widget.repo.deleteGuarded(_main.id);
    if (!mounted) return;
    if (result is CategoryDeleteBlocked) {
      if (result.selfHasBills) {
        await _alert(context, '无法删除', '「${_main.name}」下存在账单，请先处理相关账单。');
      } else {
        final names = result.childNamesWithBills.join('、');
        await _alert(
          context,
          '无法删除',
          '以下子分类存在账单，请先处理：$names',
        );
      }
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _addChild() async {
    final result = await showCategoryEditSheet(
      context,
      title: '添加子分类',
      kind: widget.kind,
    );
    if (result == null) return;
    final id = await widget.repo.create(
      name: result.name,
      kind: widget.kind,
      parentId: _main.id,
      icon: result.icon,
      iconType: result.iconType,
      customIconPath: result.customIconPath,
    );
    await _finalizeCustomIcon(
      repo: widget.repo,
      categoryId: id,
      result: result,
    );
    await _reload();
  }

  Future<void> _onChildTap(Category child, Offset globalPos) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx + 1,
        globalPos.dy + 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('编辑')),
        PopupMenuItem(value: 'promote', child: Text('改为主分类')),
        PopupMenuItem(value: 'move', child: Text('移至其他主分类')),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text('删除', style: TextStyle(color: PigTokens.danger)),
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        final result = await showCategoryEditSheet(
          context,
          title: '编辑子分类',
          kind: widget.kind,
          categoryId: child.id,
          initialName: child.name,
          initialIcon: child.icon ?? 'category',
          initialIconType: child.iconType,
          initialCustomIconPath: child.customIconPath,
        );
        if (result == null) return;
        final oldPath = child.customIconPath;
        await widget.repo.update(
          id: child.id,
          name: result.name,
          icon: result.icon,
          iconType: result.iconType,
          customIconPath: result.customIconPath,
        );
        await _finalizeCustomIcon(
          repo: widget.repo,
          categoryId: child.id,
          result: result,
          previousCustomPath: oldPath,
        );
        await _reload();
      case 'promote':
        await widget.repo.promoteToMain(child.id);
        await _reload();
      case 'move':
        final parents = (await widget.repo.listByKind(widget.kind))
            .where((c) => c.parentId == null && c.id != _main.id)
            .toList(growable: false);
        if (!mounted) return;
        final target = await showSelectMainCategorySheet(
          context,
          titleName: child.name,
          candidates: parents,
        );
        if (target == null) return;
        await widget.repo
            .moveUnderParent(id: child.id, newParentId: target.id);
        await _reload();
      case 'delete':
        final del = await widget.repo.deleteGuarded(child.id);
        if (!mounted) return;
        if (del is CategoryDeleteBlocked) {
          await _alert(context, '无法删除', '「${child.name}」下存在账单，请先处理相关账单。');
          return;
        }
        await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WorkspaceSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: PigTokens.textTertiary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CategoryIconCircle(
                name: _main.name,
                icon: _main.icon,
                iconType: _main.iconType,
                customIconPath: _main.customIconPath,
                diameter: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _main.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _LinkAction(label: '编辑', onTap: _editMain),
              _vDivider(),
              _LinkAction(label: '改为子类', onTap: _demoteMain),
              _vDivider(),
              _LinkAction(label: '删除', onTap: _deleteMain),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '子分类',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: WorkspaceSheetScroll(
              child: _children.isEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '暂无子分类，点击下方按钮添加',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: PigTokens.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: _addChild,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: PigTokens.primary,
                              side: const BorderSide(color: PigTokens.primary),
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 12,
                      children: [
                        for (final c in _children)
                          Builder(
                            builder: (ctx) {
                              return SizedBox(
                                width: 68,
                                child: _CategoryTile(
                                  category: c,
                                  onTap: () {
                                    final box =
                                        ctx.findRenderObject() as RenderBox?;
                                    final pos = box?.localToGlobal(
                                          Offset.zero,
                                        ) ??
                                        Offset.zero;
                                    _onChildTap(
                                      c,
                                      Offset(
                                        pos.dx,
                                        pos.dy + (box?.size.height ?? 0),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        SizedBox(
                          width: 68,
                          child: _AddTile(onTap: _addChild),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: PigTokens.textTertiary.withValues(alpha: 0.35),
      );
}

class _LinkAction extends StatelessWidget {
  const _LinkAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Text(
          label,
          style: const TextStyle(
            color: PigTokens.primary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    super.key,
    required this.category,
    required this.onTap,
    this.showSubBadge = false,
  });

  final Category category;
  final VoidCallback onTap;
  final bool showSubBadge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CategoryIconCircle(
                name: category.name,
                icon: category.icon,
                iconType: category.iconType,
                customIconPath: category.customIconPath,
                diameter: 44,
                iconSize: 22,
              ),
              if (showSubBadge)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Color(0xFFBDBDBD),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.more_horiz,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: PigTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: PigTokens.textTertiary, width: 1.2),
                ),
              ),
              child: Icon(Icons.add, color: PigTokens.textTertiary, size: 22),
            ),
          ),
          SizedBox(height: 6),
          Text(
            '添加',
            style: TextStyle(fontSize: 12, color: PigTokens.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _EditResult {
  const _EditResult({
    required this.name,
    required this.icon,
    this.iconType = 'material',
    this.customIconPath,
    this.pendingCustomFile,
  });

  final String name;
  final String icon;
  final String iconType;
  final String? customIconPath;
  final File? pendingCustomFile;
}

Future<void> _finalizeCustomIcon({
  required CategoryRepository repo,
  required int categoryId,
  required _EditResult result,
  String? previousCustomPath,
}) async {
  final icons = CustomIconService();
  if (result.pendingCustomFile != null) {
    final relative =
        await icons.saveCustomIcon(result.pendingCustomFile!, categoryId);
    await repo.updateIcon(
      id: categoryId,
      iconType: 'custom',
      icon: result.icon,
      customIconPath: relative,
    );
    if (previousCustomPath != null && previousCustomPath != relative) {
      await icons.deleteCustomIcon(previousCustomPath);
    }
    return;
  }
  if (result.iconType == 'material' && previousCustomPath != null) {
    await icons.deleteCustomIcon(previousCustomPath);
  } else if (result.iconType == 'custom' &&
      result.customIconPath != null &&
      previousCustomPath != null &&
      previousCustomPath != result.customIconPath) {
    await icons.deleteCustomIcon(previousCustomPath);
  }
}

Future<_EditResult?> showCategoryEditSheet(
  BuildContext context, {
  required String title,
  required String kind,
  int? categoryId,
  String initialName = '',
  String initialIcon = 'category',
  String initialIconType = 'material',
  String? initialCustomIconPath,
}) {
  return showWorkspaceSheet<_EditResult>(
    context,
    fixedHeight: true,
    heightFraction: PigTokens.categoryEditSheetFraction,
    builder: (ctx) => _CategoryEditSheet(
      title: title,
      kind: kind,
      categoryId: categoryId,
      initialName: initialName,
      initialIcon: initialIcon,
      initialIconType: initialIconType,
      initialCustomIconPath: initialCustomIconPath,
    ),
  );
}

class _CategoryEditSheet extends ConsumerStatefulWidget {
  const _CategoryEditSheet({
    required this.title,
    required this.kind,
    this.categoryId,
    required this.initialName,
    required this.initialIcon,
    required this.initialIconType,
    this.initialCustomIconPath,
  });

  final String title;
  final String kind;
  final int? categoryId;
  final String initialName;
  final String initialIcon;
  final String initialIconType;
  final String? initialCustomIconPath;

  @override
  ConsumerState<_CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends ConsumerState<_CategoryEditSheet> {
  late final TextEditingController _name;
  late String _icon;
  late String _iconType;
  String? _customIconPath;
  File? _pendingCustomFile;
  bool _picking = false;
  bool _taken = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _icon = widget.initialIcon;
    _iconType = widget.initialIconType;
    _customIconPath = widget.initialCustomIconPath;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _recheck(String raw) async {
    final taken = await ref.read(categoryRepositoryProvider).nameTaken(
          widget.kind,
          raw,
          excludeId: widget.categoryId,
        );
    if (mounted) setState(() => _taken = taken);
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _taken) return;
    Navigator.pop(
      context,
      _EditResult(
        name: name,
        icon: _icon,
        iconType: _iconType,
        customIconPath: _customIconPath,
        pendingCustomFile: _pendingCustomFile,
      ),
    );
  }

  Future<void> _pickCustom() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final service = CustomIconService();
      final picked = await service.pickFromGallery();
      if (picked == null || !mounted) return;
      final cropped = await service.cropSquare(
        picked,
        toolbarColor: PigTokens.primary,
      );
      if (cropped == null || !mounted) return;
      await service.validateImage(cropped);
      setState(() {
        _iconType = 'custom';
        _pendingCustomFile = cropped;
        // 保存前仍可预览旧图；确认保存时再落盘并替换路径
      });
    } catch (e) {
      if (!mounted) return;
      PigToast.show(context, '选择图标失败：$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _previewAvatar() {
    final displayName = _name.text.isEmpty ? '分类' : _name.text;
    if (_pendingCustomFile != null) {
      return Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: PigTokens.surfaceSecondary,
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(
          _pendingCustomFile!,
          fit: BoxFit.cover,
        ),
      );
    }
    return CategoryIconCircle(
      name: displayName,
      icon: _icon,
      iconType: _iconType,
      customIconPath: _customIconPath,
      diameter: 52,
      iconSize: 26,
    );
  }

  @override
  Widget build(BuildContext context) {
    final customSelected = _iconType == 'custom';

    return WorkspaceSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: PigTokens.textTertiary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _previewAvatar(),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '分类名称',
                      filled: true,
                      fillColor: PigTokens.surfaceInput,
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.all(
                          Radius.circular(PigTokens.radiusCard),
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {});
                      _recheck(v);
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ],
            ),
            if (_taken) ...[
              const SizedBox(height: 8),
              const Text(
                '已存在同名分类',
                style: TextStyle(color: PigTokens.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              '选择图标',
              style: TextStyle(
                fontSize: 13,
                color: PigTokens.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: categoryIconKeys.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return InkWell(
                      onTap: _picking ? null : _pickCustom,
                      borderRadius: BorderRadius.circular(8),
                      child: customSelected &&
                              (_pendingCustomFile != null ||
                                  _customIconPath != null)
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                color: PigTokens.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: PigTokens.primary,
                                  width: 1.5,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: _pendingCustomFile != null
                                      ? Image.file(
                                          _pendingCustomFile!,
                                          fit: BoxFit.cover,
                                        )
                                      : CategoryIconView(
                                          name: _name.text.isEmpty
                                              ? '分类'
                                              : _name.text,
                                          icon: _icon,
                                          iconType: 'custom',
                                          customIconPath: _customIconPath,
                                          size: 28,
                                        ),
                                ),
                              ),
                            )
                          : CustomPaint(
                              painter: _DashedRRectPainter(
                                color: PigTokens.textTertiary,
                                radius: 8,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.add,
                                  color: PigTokens.textTertiary,
                                  size: 22,
                                ),
                              ),
                            ),
                    );
                  }
                  final key = categoryIconKeys[i - 1];
                  final selected = !customSelected && key == _icon;
                  final c = categoryIconColor(key);
                  return InkWell(
                    onTap: () => setState(() {
                      _icon = key;
                      _iconType = 'material';
                      _customIconPath = null;
                      _pendingCustomFile = null;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected
                            ? c.withValues(alpha: 0.18)
                            : PigTokens.surfaceSecondary,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            selected ? Border.all(color: c, width: 1.5) : null,
                      ),
                      child: Icon(categoryIconData(key), color: c, size: 22),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _taken || _name.text.trim().isEmpty ? null : _submit,
              child: const Text('保存'),
            ),
          ],
        ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// 选择主分类弹层：未选灰显，选中恢复彩色。
Future<Category?> showSelectMainCategorySheet(
  BuildContext context, {
  required String titleName,
  required List<Category> candidates,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PigTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PigTokens.radiusSheet),
      ),
    ),
    builder: (ctx) => _SelectMainCategorySheet(
      titleName: titleName,
      candidates: candidates,
    ),
  );
}

class _SelectMainCategorySheet extends StatefulWidget {
  const _SelectMainCategorySheet({
    required this.titleName,
    required this.candidates,
  });

  final String titleName;
  final List<Category> candidates;

  @override
  State<_SelectMainCategorySheet> createState() =>
      _SelectMainCategorySheetState();
}

class _SelectMainCategorySheetState extends State<_SelectMainCategorySheet> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '请选择“${widget.titleName}”的主分类',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '修改后支持再次调整',
                      style: TextStyle(
                        fontSize: 12,
                        color: PigTokens.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 4,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: widget.candidates.length,
              itemBuilder: (context, i) {
                final cat = widget.candidates[i];
                final selected = cat.id == _selectedId;
                return InkWell(
                  onTap: () => setState(() => _selectedId = cat.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(
                        opacity: selected ? 1 : 0.45,
                        child: CategoryIconCircle(
                          name: cat.name,
                          icon: cat.icon,
                          iconType: cat.iconType,
                          customIconPath: cat.customIconPath,
                          diameter: 44,
                          iconSize: 22,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        cat.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected
                              ? PigTokens.textPrimary
                              : PigTokens.textTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _selectedId == null
                  ? null
                  : () {
                      final hit = widget.candidates
                          .firstWhere((c) => c.id == _selectedId);
                      Navigator.pop(context, hit);
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: PigTokens.primary,
                side: const BorderSide(color: PigTokens.primary),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('确认'),
            ),
          ),
        ],
      ),
    );
  }
}


Future<void> _alert(BuildContext context, String title, String body) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
