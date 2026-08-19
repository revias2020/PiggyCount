import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../styles/tokens.dart';
import '../../utils/tag_colors.dart';
import '../../widgets/category_icon_view.dart';

/// 分类 / 标签映射弹层的选择结果（ADR-043）。
sealed class ImportIdPick {
  const ImportIdPick();
}

class ImportIdPickAuto extends ImportIdPick {
  const ImportIdPickAuto();
}

class ImportIdPickIgnore extends ImportIdPick {
  const ImportIdPickIgnore();
}

class ImportIdPickMapped extends ImportIdPick {
  const ImportIdPickMapped(this.id);
  final int id;
}

/// 列名映射弹层结果；下滑关闭为 null，与「不映射」区分。
sealed class ImportColumnPick {
  const ImportColumnPick();
}

class ImportColumnPickUnmapped extends ImportColumnPick {
  const ImportColumnPickUnmapped();
}

class ImportColumnPickHeader extends ImportColumnPick {
  const ImportColumnPickHeader(this.header);
  final String header;
}

/// 列名映射弹层：可选字段含「不映射」；点选即关。
Future<ImportColumnPick?> showImportColumnPickerSheet({
  required BuildContext context,
  required String title,
  required List<String> headers,
  required String? current,
  required bool allowUnmapped,
}) {
  return showModalBottomSheet<ImportColumnPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PigTokens.surface,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PigTokens.radiusSheet),
      ),
    ),
    builder: (ctx) {
      return _ImportColumnPickerSheet(
        title: title,
        headers: headers,
        current: current,
        allowUnmapped: allowUnmapped,
      );
    },
  );
}

Future<ImportIdPick?> showImportCategoryPickerSheet({
  required BuildContext context,
  required String title,
  required List<Category> catalog,
  required int? selectedId,
  required bool isIgnore,
}) {
  return showModalBottomSheet<ImportIdPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PigTokens.surface,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PigTokens.radiusSheet),
      ),
    ),
    builder: (ctx) {
      return _ImportCategoryPickerSheet(
        title: title,
        catalog: catalog,
        initialSelectedId: selectedId,
        initialIgnore: isIgnore,
      );
    },
  );
}

Future<ImportIdPick?> showImportTagPickerSheet({
  required BuildContext context,
  required String title,
  required List<TagGroupBundle> bundles,
  required int? selectedId,
  required bool isIgnore,
}) {
  return showModalBottomSheet<ImportIdPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PigTokens.surface,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PigTokens.radiusSheet),
      ),
    ),
    builder: (ctx) {
      return _ImportTagPickerSheet(
        title: title,
        bundles: bundles,
        selectedId: selectedId,
        isIgnore: isIgnore,
      );
    },
  );
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.heightFraction,
    required this.title,
    required this.child,
    this.header,
  });

  final double heightFraction;
  final String title;
  final Widget child;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * heightFraction;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: maxH,
        child: Column(
          children: [
            const SizedBox(height: PigTokens.spaceSm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: PigTokens.textTertiary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PigTokens.spaceLg,
                PigTokens.spaceMd,
                PigTokens.spaceLg,
                PigTokens.spaceSm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: PigTokens.textPrimary,
                  ),
                ),
              ),
            ),
            ?header,
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: PigTokens.primarySoft,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected ? PigTokens.primary : PigTokens.textSecondary,
      ),
      side: BorderSide(
        color: selected ? PigTokens.primary : Colors.transparent,
        width: 1.5,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PigTokens.spaceLg),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          color: PigTokens.textTertiary,
          height: 1.35,
        ),
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  const _HeaderDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: PigTokens.spaceLg,
        vertical: PigTokens.spaceSm,
      ),
      child: Divider(height: 1, thickness: 1),
    );
  }
}

/// 自动 / 不映射顶栏：动作左对齐 → 居中含义 → 横线 → 可选居中手势提示。
class _AutoIgnoreHeader extends StatelessWidget {
  const _AutoIgnoreHeader({
    required this.autoSelected,
    required this.ignoreSelected,
    required this.onAuto,
    required this.onIgnore,
    required this.meaningHint,
    this.gestureHint,
  });

  final bool autoSelected;
  final bool ignoreSelected;
  final VoidCallback onAuto;
  final VoidCallback onIgnore;
  final String meaningHint;
  final String? gestureHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PigTokens.spaceLg,
            0,
            PigTokens.spaceLg,
            PigTokens.spaceSm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: PigTokens.spaceSm,
              runSpacing: PigTokens.spaceXs,
              children: [
                _ActionChip(
                  label: '自动',
                  selected: autoSelected,
                  onTap: onAuto,
                ),
                _ActionChip(
                  label: '不映射',
                  selected: ignoreSelected,
                  onTap: onIgnore,
                ),
              ],
            ),
          ),
        ),
        _CenteredHint(meaningHint),
        const _HeaderDivider(),
        if (gestureHint != null) ...[
          _CenteredHint(gestureHint!),
          const SizedBox(height: PigTokens.spaceSm),
        ],
      ],
    );
  }
}

class _ImportColumnPickerSheet extends StatelessWidget {
  const _ImportColumnPickerSheet({
    required this.title,
    required this.headers,
    required this.current,
    required this.allowUnmapped,
  });

  final String title;
  final List<String> headers;
  final String? current;
  final bool allowUnmapped;

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      heightFraction: 0.40,
      title: title,
      header: allowUnmapped
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PigTokens.spaceLg,
                    0,
                    PigTokens.spaceLg,
                    0,
                  ),
                  child: Row(
                    children: [
                      _ActionChip(
                        label: '不映射',
                        selected: current == null,
                        onTap: () => Navigator.pop(
                          context,
                          const ImportColumnPickUnmapped(),
                        ),
                      ),
                      const SizedBox(width: PigTokens.spaceSm),
                      const Expanded(
                        child: Text(
                          '使用默认值',
                          style: TextStyle(
                            fontSize: 12,
                            color: PigTokens.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const _HeaderDivider(),
              ],
            )
          : null,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          PigTokens.spaceLg,
          0,
          PigTokens.spaceLg,
          PigTokens.spaceLg,
        ),
        children: [
          Wrap(
            spacing: PigTokens.spaceSm,
            runSpacing: PigTokens.spaceSm,
            children: [
              for (final h in headers)
                FilterChip(
                  label: Text(h),
                  selected: current == h,
                  showCheckmark: false,
                  selectedColor: PigTokens.primarySoft,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        current == h ? FontWeight.w600 : FontWeight.w500,
                    color: current == h
                        ? PigTokens.primary
                        : PigTokens.textPrimary,
                  ),
                  side: BorderSide(
                    color:
                        current == h ? PigTokens.primary : Colors.transparent,
                    width: 1.5,
                  ),
                  onSelected: (_) => Navigator.pop(
                    context,
                    ImportColumnPickHeader(h),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImportCategoryPickerSheet extends StatefulWidget {
  const _ImportCategoryPickerSheet({
    required this.title,
    required this.catalog,
    required this.initialSelectedId,
    required this.initialIgnore,
  });

  final String title;
  final List<Category> catalog;
  final int? initialSelectedId;
  final bool initialIgnore;

  @override
  State<_ImportCategoryPickerSheet> createState() =>
      _ImportCategoryPickerSheetState();
}

class _ImportCategoryPickerSheetState extends State<_ImportCategoryPickerSheet> {
  late int? _parentId;
  late int? _categoryId;
  late bool _ignore;

  static const _refChipW = 68.0;
  static const _spacing = PigTokens.spaceSm;

  @override
  void initState() {
    super.initState();
    _ignore = widget.initialIgnore;
    _categoryId = widget.initialIgnore ? null : widget.initialSelectedId;
    _parentId = _resolveParent(_categoryId);
  }

  int? _resolveParent(int? id) {
    if (id == null) return null;
    Category? hit;
    for (final c in widget.catalog) {
      if (c.id == id) {
        hit = c;
        break;
      }
    }
    if (hit == null) return null;
    return hit.parentId ?? hit.id;
  }

  Set<int> get _parentsWithChildren => {
        for (final c in widget.catalog)
          if (c.parentId != null) c.parentId!,
      };

  void _pickAuto() => Navigator.pop(context, const ImportIdPickAuto());

  void _pickIgnore() => Navigator.pop(context, const ImportIdPickIgnore());

  void _onParent(Category parent) {
    final children =
        widget.catalog.where((c) => c.parentId == parent.id).toList();
    if (_categoryId == parent.id && children.isNotEmpty) {
      Navigator.pop(context, ImportIdPickMapped(parent.id));
      return;
    }
    setState(() {
      _ignore = false;
      _parentId = parent.id;
      _categoryId = parent.id;
    });
    if (children.isEmpty) {
      Navigator.pop(context, ImportIdPickMapped(parent.id));
    }
  }

  void _onChild(Category child) {
    Navigator.pop(context, ImportIdPickMapped(child.id));
  }

  @override
  Widget build(BuildContext context) {
    final parents =
        widget.catalog.where((c) => c.parentId == null).toList(growable: false);
    final children = _parentId == null
        ? const <Category>[]
        : widget.catalog
            .where((c) => c.parentId == _parentId)
            .toList(growable: false);
    final withChildren = _parentsWithChildren;

    return _SheetScaffold(
      heightFraction: 0.70,
      title: widget.title,
      header: _AutoIgnoreHeader(
        autoSelected: !_ignore && _categoryId == null,
        ignoreSelected: _ignore,
        onAuto: _pickAuto,
        onIgnore: _pickIgnore,
        meaningHint: '自动：精准匹配，没有则新建；不映射：不指定账单分类类别',
        gestureHint: '点子分类直接选定；有子类的主分类再点一次确认',
      ),
      child: parents.isEmpty
          ? const Center(
              child: Text(
                '暂无分类，可在「我的 → 分类管理」添加',
                style: TextStyle(fontSize: 13, color: PigTokens.textTertiary),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                const inset = PigTokens.spaceSm;
                final contentW = constraints.maxWidth - inset * 2;
                final cols = ((contentW + _spacing) / (_refChipW + _spacing))
                    .floor()
                    .clamp(4, 6);
                final chipW = (contentW - _spacing * (cols - 1)) / cols;
                final rows = <Widget>[];
                for (var i = 0; i < parents.length; i += cols) {
                  final end = (i + cols).clamp(0, parents.length);
                  final rowItems = parents.sublist(i, end);
                  rows.add(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var j = 0; j < rowItems.length; j++) ...[
                          if (j > 0) const SizedBox(width: _spacing),
                          SizedBox(
                            width: chipW,
                            child: _ImportCatChip(
                              label: rowItems[j].name,
                              category: rowItems[j],
                              selected: !_ignore &&
                                  (_parentId == rowItems[j].id ||
                                      _categoryId == rowItems[j].id),
                              showSubBadge:
                                  withChildren.contains(rowItems[j].id),
                              onTap: () => _onParent(rowItems[j]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );

                  final expandedInRow =
                      rowItems.any((c) => c.id == _parentId);
                  if (expandedInRow && _parentId != null) {
                    rows.add(const SizedBox(height: 10));
                    rows.add(
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(
                            PigTokens.spaceSm,
                            10,
                            PigTokens.spaceSm,
                            10,
                          ),
                          decoration: BoxDecoration(
                            color: PigTokens.surfaceSecondary
                                .withValues(alpha: 0.65),
                            borderRadius:
                                BorderRadius.circular(PigTokens.radiusCard),
                          ),
                          child: children.isEmpty
                              ? const SizedBox.shrink()
                              : Wrap(
                                  spacing: _spacing,
                                  runSpacing: _spacing,
                                  children: [
                                    for (final c in children)
                                      _ImportCatChip(
                                        label: c.name,
                                        category: c,
                                        selected:
                                            !_ignore && _categoryId == c.id,
                                        compact: true,
                                        onTap: () => _onChild(c),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                    );
                  }

                  if (end < parents.length) {
                    rows.add(const SizedBox(height: PigTokens.spaceMd));
                  }
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    inset,
                    PigTokens.spaceSm,
                    inset,
                    PigTokens.spaceLg,
                  ),
                  children: rows,
                );
              },
            ),
    );
  }
}

class _ImportCatChip extends StatelessWidget {
  const _ImportCatChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.category,
    this.compact = false,
    this.showSubBadge = false,
  });

  final String label;
  final Category? category;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final bool showSubBadge;

  @override
  Widget build(BuildContext context) {
    // 与记一笔一致：未选灰显，选中全彩。
    final color =
        selected ? PigTokens.textPrimary : PigTokens.textTertiary;
    final diameter = compact ? 40.0 : 44.0;
    final iconSize = compact ? 20.0 : 22.0;

    Widget avatar;
    if (category != null) {
      avatar = CategoryIconCircle(
        name: category!.name,
        icon: category!.icon,
        iconType: category!.iconType,
        customIconPath: category!.customIconPath,
        diameter: diameter,
        iconSize: iconSize,
      );
    } else {
      avatar = Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: PigTokens.textTertiary.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      child: SizedBox(
        width: compact ? 64 : double.infinity,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: selected ? 1 : 0.45,
                  child: avatar,
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
            const SizedBox(height: PigTokens.spaceXs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: compact ? 10 : 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportTagPickerSheet extends StatelessWidget {
  const _ImportTagPickerSheet({
    required this.title,
    required this.bundles,
    required this.selectedId,
    required this.isIgnore,
  });

  final String title;
  final List<TagGroupBundle> bundles;
  final int? selectedId;
  final bool isIgnore;

  @override
  Widget build(BuildContext context) {
    final hasTags = bundles.any((b) => b.tags.isNotEmpty);
    final isAuto = !isIgnore && selectedId == null;

    return _SheetScaffold(
      heightFraction: 0.55,
      title: title,
      header: _AutoIgnoreHeader(
        autoSelected: isAuto,
        ignoreSelected: isIgnore,
        onAuto: () => Navigator.pop(context, const ImportIdPickAuto()),
        onIgnore: () => Navigator.pop(context, const ImportIdPickIgnore()),
        meaningHint: '自动：精准匹配，没有则新建；不映射：不挂该标签',
      ),
      child: !hasTags
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(PigTokens.spaceLg),
                child: Text(
                  '暂无可用标签，可在「我的 → 标签管理」添加',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: PigTokens.textTertiary,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                PigTokens.spaceLg,
                0,
                PigTokens.spaceLg,
                PigTokens.spaceLg,
              ),
              children: [
                for (final bundle in bundles)
                  if (bundle.tags.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        top: PigTokens.spaceSm,
                        bottom: PigTokens.spaceXs,
                      ),
                      child: Text(
                        bundle.group.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: PigTokens.textTertiary,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: PigTokens.spaceSm,
                      runSpacing: PigTokens.spaceXs,
                      children: [
                        for (final tag in bundle.tags)
                          FilterChip(
                            label: Text(tag.name),
                            selected: !isIgnore && selectedId == tag.id,
                            showCheckmark: false,
                            selectedColor: TagColors.parse(tag.color)
                                .withValues(alpha: 0.18),
                            backgroundColor: TagColors.parse(tag.color)
                                .withValues(alpha: 0.08),
                            labelStyle: TextStyle(
                              color: TagColors.parse(tag.color),
                              fontWeight: selectedId == tag.id
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              fontSize: 13,
                            ),
                            side: BorderSide(
                              color: !isIgnore && selectedId == tag.id
                                  ? TagColors.parse(tag.color)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                            onSelected: (_) => Navigator.pop(
                              context,
                              ImportIdPickMapped(tag.id),
                            ),
                          ),
                      ],
                    ),
                  ],
              ],
            ),
    );
  }
}
