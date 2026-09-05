import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/tag_colors.dart';
import '../../widgets/capsule_switcher.dart';
import '../../widgets/workspace_sheet.dart';
import '../../widgets/pig_toast.dart';

/// 标签管理：按组维护字符串组 / 数值组。
class TagManagePage extends ConsumerWidget {
  const TagManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundlesAsync = ref.watch(tagGroupBundlesProvider);
    final repo = ref.read(tagRepositoryProvider);

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: const Text('标签管理'),
        actions: [
          TextButton.icon(
            onPressed: () => _addGroup(context, repo),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('新建组'),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) {
              if (v == 'clear') {
                _clearUnused(context, ref, repo);
              } else if (v == 'restore') {
                _restoreDefaults(context, ref, repo);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('清除未使用的标签')),
              PopupMenuItem(value: 'restore', child: Text('恢复默认标签')),
            ],
          ),
        ],
      ),
      body: bundlesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (bundles) {
          if (bundles.isEmpty) {
            return const Center(
              child: Text(
                '暂无标签组',
                style: TextStyle(color: PigTokens.textSecondary),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(PigTokens.spaceLg),
            itemCount: bundles.length,
            itemBuilder: (context, index) {
              final bundle = bundles[index];
              return _GroupCard(
                bundle: bundle,
                onAddTag: () => _addTag(context, repo, bundle),
                onEditGroup: () => _editGroup(context, repo, bundle.group),
                onDeleteGroup: () => _deleteGroup(context, repo, bundle),
                onEditTag: (tag) => _editTag(context, repo, bundle, tag),
                onDeleteTag: (tag) => _deleteTag(context, repo, tag),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _clearUnused(
    BuildContext context,
    WidgetRef ref,
    TagRepository repo,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除未使用的标签'),
        content: const Text('将删除未挂到任何账单的标签。确定继续？'),
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
    if (ok != true || !context.mounted) return;
    final n = await repo.clearUnused();
    ref.invalidate(tagGroupBundlesProvider);
    if (!context.mounted) return;
    PigToast.show(context, '已清除 $n 个未使用标签');
  }

  Future<void> _restoreDefaults(
    BuildContext context,
    WidgetRef ref,
    TagRepository repo,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认标签'),
        content: const Text('将按出厂清单补齐「支付/渠道」「额度」等默认组与标签，不会删除你自建的内容。确定继续？'),
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
    if (ok != true || !context.mounted) return;
    final n = await repo.restoreDefaults();
    ref.invalidate(tagGroupBundlesProvider);
    if (!context.mounted) return;
    PigToast.show(context, '已补缺 $n 项');
  }

  Future<void> _addGroup(BuildContext context, TagRepository repo) async {
    final result = await _showGroupEditSheet(context);
    if (result == null) return;
    try {
      await repo.createGroup(
        name: result.name,
        kind: result.kind,
        scope: result.scope,
      );
    } catch (e) {
      if (context.mounted) {
        PigToast.show(context, '创建失败：${_errMsg(e)}');
      }
    }
  }

  Future<void> _editGroup(
    BuildContext context,
    TagRepository repo,
    TagGroup group,
  ) async {
    final result = await _showGroupEditSheet(
      context,
      initialName: group.name,
      initialKind: group.kind,
      initialScope: group.scope,
      kindLocked: true,
      excludeId: group.id,
    );
    if (result == null) return;
    try {
      await repo.updateGroup(
        id: group.id,
        name: result.name,
        scope: result.scope,
      );
    } catch (e) {
      if (context.mounted) {
        PigToast.show(context, '保存失败：${_errMsg(e)}');
      }
    }
  }

  Future<void> _deleteGroup(
    BuildContext context,
    TagRepository repo,
    TagGroupBundle bundle,
  ) async {
    if (bundle.tags.isNotEmpty) {
      PigToast.show(context, '组内仍有标签，请先移出或删除');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签组'),
        content: Text('确定删除空组「${bundle.group.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await repo.deleteGroup(bundle.group.id);
      } catch (e) {
        if (context.mounted) {
          PigToast.show(context, '$e');
        }
      }
    }
  }

  Future<void> _addTag(
    BuildContext context,
    TagRepository repo,
    TagGroupBundle bundle,
  ) async {
    final draft = await _showTagEditSheet(
      context,
      group: bundle.group,
      title: '新建标签',
    );
    if (draft == null) return;
    try {
      await repo.create(
        draft.name,
        groupId: bundle.group.id,
        color: draft.color,
        rangeMin: draft.rangeMin,
        rangeMax: draft.rangeMax,
      );
    } catch (e) {
      if (context.mounted) {
        PigToast.show(context, '创建失败：${_errMsg(e)}');
      }
    }
  }

  Future<void> _editTag(
    BuildContext context,
    TagRepository repo,
    TagGroupBundle bundle,
    Tag tag,
  ) async {
    final allGroups = await repo.getGroups();
    if (!context.mounted) return;
    final sameKind =
        allGroups.where((g) => g.kind == bundle.group.kind).toList();
    final draft = await _showTagEditSheet(
      context,
      group: bundle.group,
      title: '编辑标签',
      initial: tag,
      moveTargets: sameKind,
    );
    if (draft == null) return;
    try {
      await repo.updateTag(
        id: tag.id,
        name: draft.name,
        color: draft.color,
        groupId: draft.groupId,
        rangeMin: draft.rangeMin,
        rangeMax: draft.rangeMax,
        clearRangeMax: bundle.isNumber && draft.rangeMax == null,
      );
    } catch (e) {
      if (context.mounted) {
        PigToast.show(context, '保存失败：${_errMsg(e)}');
      }
    }
  }

  String _errMsg(Object e) {
    if (e is StateError) return e.message;
    if (e is ArgumentError) return e.message?.toString() ?? '$e';
    return '$e';
  }

  Future<void> _deleteTag(
    BuildContext context,
    TagRepository repo,
    Tag tag,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定删除「${tag.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await repo.delete(tag.id);
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.bundle,
    required this.onAddTag,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  final TagGroupBundle bundle;
  final VoidCallback onAddTag;
  final VoidCallback onEditGroup;
  final VoidCallback onDeleteGroup;
  final void Function(Tag tag) onEditTag;
  final void Function(Tag tag) onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final kindLabel = bundle.isNumber ? '数值组' : '字符串组';
    final scopeLabel = TagGroupScope.label(bundle.group.scope);
    return Padding(
      padding: const EdgeInsets.only(bottom: PigTokens.spaceMd),
      child: Material(
        color: PigTokens.surface,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bundle.group.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: PigTokens.textPrimary,
                          ),
                        ),
                        Text(
                          '$kindLabel · $scopeLabel',
                          style: const TextStyle(
                            fontSize: 12,
                            color: PigTokens.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '添加标签',
                    icon: const Icon(Icons.add),
                    onPressed: onAddTag,
                  ),
                  IconButton(
                    tooltip: '编辑组',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEditGroup,
                  ),
                  IconButton(
                    tooltip: '删除组',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDeleteGroup,
                  ),
                ],
              ),
              if (bundle.tags.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 12, 8),
                  child: Text(
                    '暂无标签',
                    style: TextStyle(
                      fontSize: 13,
                      color: PigTokens.textTertiary,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: bundle.tags.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.35,
                    ),
                    itemBuilder: (context, index) {
                      final tag = bundle.tags[index];
                      return _TagGridTile(
                        tag: tag,
                        rangeText: bundle.isNumber ? _rangeText(tag) : null,
                        onEdit: () => onEditTag(tag),
                        onDelete: () => onDeleteTag(tag),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _rangeText(Tag tag) {
    final min = tag.rangeMin;
    final max = tag.rangeMax;
    if (min == null) return '未设置区间';
    if (max == null) return '≥ ${_num(min)}';
    return '${_num(min)} ≤ 金额 < ${_num(max)}';
  }

  String _num(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
}

class _TagGridTile extends StatelessWidget {
  const _TagGridTile({
    required this.tag,
    required this.onEdit,
    required this.onDelete,
    this.rangeText,
  });

  final Tag tag;
  final String? rangeText;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = TagColors.parse(tag.color);
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(PigTokens.radiusCard - 4),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard - 4),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PigTokens.radiusCard - 4),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tag.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PigTokens.textPrimary,
                      ),
                    ),
                    if (rangeText != null)
                      Text(
                        rangeText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: PigTokens.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.delete_outline, size: 18),
                color: PigTokens.textTertiary,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupDraft {
  const _GroupDraft({
    required this.name,
    required this.kind,
    required this.scope,
  });
  final String name;
  final String kind;
  final String scope;
}

/// 新建 / 编辑标签组：与标签 / 分类编辑同款底部弹层。
Future<_GroupDraft?> _showGroupEditSheet(
  BuildContext context, {
  String? initialName,
  String? initialKind,
  String? initialScope,
  bool kindLocked = false,
  int? excludeId,
}) {
  return showWorkspaceSheet<_GroupDraft>(
    context,
    fixedHeight: true,
    heightFraction: PigTokens.tagEditSheetFraction,
    builder: (ctx) => _GroupEditSheet(
      initialName: initialName,
      initialKind: initialKind,
      initialScope: initialScope,
      kindLocked: kindLocked,
      excludeId: excludeId,
    ),
  );
}

class _GroupEditSheet extends ConsumerStatefulWidget {
  const _GroupEditSheet({
    this.initialName,
    this.initialKind,
    this.initialScope,
    this.kindLocked = false,
    this.excludeId,
  });

  final String? initialName;
  final String? initialKind;
  final String? initialScope;
  final bool kindLocked;
  final int? excludeId;

  @override
  ConsumerState<_GroupEditSheet> createState() => _GroupEditSheetState();
}

class _GroupEditSheetState extends ConsumerState<_GroupEditSheet> {
  late final TextEditingController _name;
  late String _kind;
  late String _scope;
  bool _taken = false;

  static const _fieldBorder = OutlineInputBorder(
    borderSide: BorderSide.none,
    borderRadius: BorderRadius.all(Radius.circular(PigTokens.radiusCard)),
  );

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _kind = widget.initialKind ?? TagGroupKind.string;
    _scope = widget.initialScope ?? TagGroupScope.both;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _recheck(String raw) async {
    final taken = await ref.read(tagRepositoryProvider).groupNameTaken(
          raw,
          excludeId: widget.excludeId,
        );
    if (mounted) setState(() => _taken = taken);
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _taken) return;
    Navigator.pop(
      context,
      _GroupDraft(name: name, kind: _kind, scope: _scope),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialName != null;

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
          const SizedBox(height: 12),
          Text(
            editing ? '编辑标签组' : '新建标签组',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: WorkspaceSheetScroll(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '组名',
                      filled: true,
                      fillColor: PigTokens.surfaceInput,
                      border: _fieldBorder,
                    ),
                    onChanged: _recheck,
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_taken) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '已存在同名标签组',
                      style: TextStyle(color: PigTokens.danger, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    '组类型',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: PigTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CapsuleSwitcher<String>(
                    selectedValue: _kind,
                    enabled: !widget.kindLocked,
                    options: const [
                      CapsuleOption(value: TagGroupKind.string, label: '字符串组'),
                      CapsuleOption(value: TagGroupKind.number, label: '数值组'),
                    ],
                    onChanged: (v) => setState(() => _kind = v),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '生效范围',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: PigTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CapsuleSwitcher<String>(
                    selectedValue: _scope,
                    options: const [
                      CapsuleOption(value: TagGroupScope.both, label: '全部'),
                      CapsuleOption(value: TagGroupScope.expense, label: '仅支出'),
                      CapsuleOption(value: TagGroupScope.income, label: '仅收入'),
                    ],
                    onChanged: (v) => setState(() => _scope = v),
                  ),
                ],
              ),
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

class _TagDraft {
  const _TagDraft({
    required this.name,
    required this.color,
    this.groupId,
    this.rangeMin,
    this.rangeMax,
  });

  final String name;
  final String color;
  final int? groupId;
  final double? rangeMin;
  final double? rangeMax;
}

/// 新建 / 编辑标签：与分类管理同款底部弹层。
Future<_TagDraft?> _showTagEditSheet(
  BuildContext context, {
  required TagGroup group,
  required String title,
  Tag? initial,
  List<TagGroup> moveTargets = const [],
}) {
  return showWorkspaceSheet<_TagDraft>(
    context,
    fixedHeight: true,
    heightFraction: PigTokens.tagEditSheetFraction,
    builder: (ctx) => _TagEditSheet(
      group: group,
      title: title,
      initial: initial,
      moveTargets: moveTargets,
    ),
  );
}

class _TagEditSheet extends ConsumerStatefulWidget {
  const _TagEditSheet({
    required this.group,
    required this.title,
    this.initial,
    this.moveTargets = const [],
  });

  final TagGroup group;
  final String title;
  final Tag? initial;
  final List<TagGroup> moveTargets;

  @override
  ConsumerState<_TagEditSheet> createState() => _TagEditSheetState();
}

class _TagEditSheetState extends ConsumerState<_TagEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late bool _noMax;
  late int _groupId;
  late String _color;
  bool _taken = false;
  bool _groupMenuOpen = false;
  double _groupFieldWidth = 0;
  final _groupLink = LayerLink();
  final _groupFieldKey = GlobalKey();
  final _groupScroll = ScrollController();

  static const _groupRowHeight = 44.0;
  static const _groupMenuMaxHeight = 198.0;

  bool get _isNumber => widget.group.kind == TagGroupKind.number;
  bool get _isEdit => widget.initial != null;
  bool get _canMove => _isEdit && widget.moveTargets.length > 1;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _groupId = t?.groupId ?? widget.group.id;
    _color = t?.color ?? TagColors.random();
    _name = TextEditingController(text: t?.name ?? '');
    _min = TextEditingController(
      text: t?.rangeMin == null ? '' : _fmt(t!.rangeMin!),
    );
    _max = TextEditingController(
      text: t?.rangeMax == null ? '' : _fmt(t!.rangeMax!),
    );
    _noMax = t != null && t.rangeMin != null && t.rangeMax == null;
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  String get _currentGroupName {
    for (final g in widget.moveTargets) {
      if (g.id == _groupId) return g.name;
    }
    return widget.group.name;
  }

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    _groupScroll.dispose();
    super.dispose();
  }

  Future<void> _recheck(String raw) async {
    if (raw.trim().isEmpty) {
      if (mounted) setState(() => _taken = false);
      return;
    }
    final taken = await ref.read(tagRepositoryProvider).nameTaken(
          raw,
          excludeId: widget.initial?.id,
        );
    if (mounted) setState(() => _taken = taken);
  }

  @override
  Widget build(BuildContext context) {
    final previewColor = TagColors.parse(_color);

    return WorkspaceSheetFrame(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
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
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: WorkspaceSheetScroll(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: previewColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _name,
                              autofocus: true,
                              decoration: const InputDecoration(
                                hintText: '标签名称',
                                filled: true,
                                fillColor: PigTokens.surfaceInput,
                                border: OutlineInputBorder(
                                  borderSide: BorderSide.none,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(PigTokens.radiusCard),
                                  ),
                                ),
                              ),
                              onChanged: _recheck,
                              onSubmitted: (_) => _submit(),
                            ),
                          ),
                        ],
                      ),
                      if (_taken) ...[
                        const SizedBox(height: 8),
                        const Text(
                          '已存在同名标签',
                          style: TextStyle(
                            color: PigTokens.danger,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (_isEdit) ...[
                        const SizedBox(height: 12),
                        _buildGroupField(),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                        '标签颜色',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: PigTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final hex in TagColors.palette)
                            GestureDetector(
                              onTap: () => setState(() => _color = hex),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: TagColors.parse(hex),
                                  shape: BoxShape.circle,
                                  border: _color == hex
                                      ? Border.all(
                                          color: PigTokens.textPrimary,
                                          width: 2.5,
                                        )
                                      : null,
                                ),
                                child: _color == hex
                                    ? Icon(
                                        Icons.check,
                                        size: 14,
                                        color: TagColors.isLight(
                                          TagColors.parse(hex),
                                        )
                                            ? Colors.black
                                            : Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                      if (_isNumber) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _min,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: '下限（含）',
                            hintText: '如 0',
                            isDense: true,
                            filled: true,
                            fillColor: PigTokens.surfaceInput,
                            border: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.all(
                                Radius.circular(PigTokens.radiusCard),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            '无上限',
                            style: TextStyle(fontSize: 14),
                          ),
                          value: _noMax,
                          onChanged: (v) => setState(() => _noMax = v),
                        ),
                        if (!_noMax)
                          TextField(
                            controller: _max,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '上限（不含）',
                              hintText: '如 100',
                              isDense: true,
                              filled: true,
                              fillColor: PigTokens.surfaceInput,
                              border: OutlineInputBorder(
                                borderSide: BorderSide.none,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(PigTokens.radiusCard),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _taken || _name.text.trim().isEmpty ? null : _submit,
                child: const Text('保存'),
              ),
            ],
          ),
          if (_canMove && _groupMenuOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _groupMenuOpen = false),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _groupLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                child: SizedBox(
                  width: _groupFieldWidth,
                  child: _buildGroupMenu(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupField() {
    const radius = BorderRadius.all(Radius.circular(PigTokens.radiusCard));
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _currentGroupName,
              style: const TextStyle(fontSize: 15),
            ),
          ),
          if (_canMove)
            Icon(
              _groupMenuOpen ? Icons.expand_less : Icons.expand_more,
              color: PigTokens.textTertiary,
            ),
        ],
      ),
    );

    return CompositedTransformTarget(
      link: _groupLink,
      child: KeyedSubtree(
        key: _groupFieldKey,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: '所属组',
            isDense: true,
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: PigTokens.surfaceInput,
            border: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: radius,
            ),
          ),
          child: _canMove
              ? InkWell(
                  onTap: _toggleGroupMenu,
                  borderRadius: radius,
                  child: header,
                )
              : header,
        ),
      ),
    );
  }

  void _toggleGroupMenu() {
    if (_groupMenuOpen) {
      setState(() => _groupMenuOpen = false);
      return;
    }
    final box = _groupFieldKey.currentContext?.findRenderObject() as RenderBox?;
    setState(() {
      _groupFieldWidth = box?.size.width ?? 0;
      _groupMenuOpen = true;
    });
    if (_groupFieldWidth <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final lateBox =
            _groupFieldKey.currentContext?.findRenderObject() as RenderBox?;
        if (lateBox != null && lateBox.size.width != _groupFieldWidth) {
          setState(() => _groupFieldWidth = lateBox.size.width);
        }
      });
    }
  }

  Widget _buildGroupMenu() {
    const radius = BorderRadius.all(Radius.circular(PigTokens.radiusCard));
    final n = widget.moveTargets.length;
    final height =
        (n * _groupRowHeight).clamp(0.0, _groupMenuMaxHeight).toDouble();
    final overflowing = n * _groupRowHeight > _groupMenuMaxHeight;

    return Material(
      elevation: 6,
      color: PigTokens.surface,
      shadowColor: Colors.black26,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Scrollbar(
          controller: _groupScroll,
          thumbVisibility: overflowing,
          child: ListView.builder(
            controller: _groupScroll,
            padding: EdgeInsets.zero,
            itemExtent: _groupRowHeight,
            itemCount: n,
            physics: overflowing
                ? null
                : const NeverScrollableScrollPhysics(),
            itemBuilder: (context, i) {
              final g = widget.moveTargets[i];
              final selected = g.id == _groupId;
              return InkWell(
                onTap: () => setState(() {
                  _groupId = g.id;
                  _groupMenuOpen = false;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          g.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (selected)
                        const Icon(
                          Icons.check,
                          size: 18,
                          color: PigTokens.primary,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _taken) return;
    if (!_isNumber) {
      Navigator.pop(
        context,
        _TagDraft(name: name, color: _color, groupId: _groupId),
      );
      return;
    }
    final min = double.tryParse(_min.text.trim());
    if (min == null) {
      PigToast.show(context, '请填写有效下限');
      return;
    }
    double? max;
    if (!_noMax) {
      max = double.tryParse(_max.text.trim());
      if (max == null) {
        PigToast.show(context, '请填写有效上限，或勾选无上限');
        return;
      }
    }
    Navigator.pop(
      context,
      _TagDraft(
        name: name,
        color: _color,
        groupId: _groupId,
        rangeMin: min,
        rangeMax: max,
      ),
    );
  }
}
