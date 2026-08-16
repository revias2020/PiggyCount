import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';

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
                onRenameGroup: () => _renameGroup(context, repo, bundle.group),
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

  Future<void> _addGroup(BuildContext context, TagRepository repo) async {
    final result = await showDialog<_GroupDraft>(
      context: context,
      builder: (ctx) => const _GroupEditorDialog(),
    );
    if (result == null) return;
    try {
      await repo.createGroup(name: result.name, kind: result.kind);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败，可能组名重复')),
        );
      }
    }
  }

  Future<void> _renameGroup(
    BuildContext context,
    TagRepository repo,
    TagGroup group,
  ) async {
    final name = await _askText(
      context,
      title: '重命名组',
      initial: group.name,
      hint: '组名',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await repo.renameGroup(group.id, name);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重命名失败，可能组名重复')),
        );
      }
    }
  }

  Future<void> _deleteGroup(
    BuildContext context,
    TagRepository repo,
    TagGroupBundle bundle,
  ) async {
    if (bundle.tags.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('组内仍有标签，请先移出或删除')),
      );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e')),
          );
        }
      }
    }
  }

  Future<void> _addTag(
    BuildContext context,
    TagRepository repo,
    TagGroupBundle bundle,
  ) async {
    final draft = await showDialog<_TagDraft>(
      context: context,
      builder: (ctx) => _TagEditorDialog(
        group: bundle.group,
        title: '新建标签',
      ),
    );
    if (draft == null) return;
    try {
      await repo.create(
        draft.name,
        groupId: bundle.group.id,
        rangeMin: draft.rangeMin,
        rangeMax: draft.rangeMax,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败：${_errMsg(e)}')),
        );
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
    final draft = await showDialog<_TagDraft>(
      context: context,
      builder: (ctx) => _TagEditorDialog(
        group: bundle.group,
        title: '编辑标签',
        initial: tag,
        moveTargets: sameKind,
      ),
    );
    if (draft == null) return;
    try {
      await repo.updateTag(
        id: tag.id,
        name: draft.name,
        groupId: draft.groupId,
        rangeMin: draft.rangeMin,
        rangeMax: draft.rangeMax,
        clearRangeMax: bundle.isNumber && draft.rangeMax == null,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：${_errMsg(e)}')),
        );
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

  Future<String?> _askText(
    BuildContext context, {
    required String title,
    String initial = '',
    String hint = '',
  }) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.bundle,
    required this.onAddTag,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  final TagGroupBundle bundle;
  final VoidCallback onAddTag;
  final VoidCallback onRenameGroup;
  final VoidCallback onDeleteGroup;
  final void Function(Tag tag) onEditTag;
  final void Function(Tag tag) onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final kindLabel = bundle.isNumber ? '数值组' : '字符串组';
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
                          kindLabel,
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
                    tooltip: '重命名组',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onRenameGroup,
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
                for (final tag in bundle.tags)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(right: 0),
                    leading: const Icon(Icons.local_offer_outlined, size: 20),
                    title: Text(tag.name),
                    subtitle: bundle.isNumber
                        ? Text(_rangeText(tag))
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => onEditTag(tag),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => onDeleteTag(tag),
                        ),
                      ],
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

class _GroupDraft {
  const _GroupDraft({required this.name, required this.kind});
  final String name;
  final String kind;
}

class _GroupEditorDialog extends StatefulWidget {
  const _GroupEditorDialog();

  @override
  State<_GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<_GroupEditorDialog> {
  final _name = TextEditingController();
  String _kind = TagGroupKind.string;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建标签组'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(hintText: '组名'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: TagGroupKind.string,
                  label: Text('字符串组'),
                ),
                ButtonSegment(
                  value: TagGroupKind.number,
                  label: Text('数值组'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, _GroupDraft(name: name, kind: _kind));
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _TagDraft {
  const _TagDraft({
    required this.name,
    this.groupId,
    this.rangeMin,
    this.rangeMax,
  });

  final String name;
  final int? groupId;
  final double? rangeMin;
  final double? rangeMax;
}

class _TagEditorDialog extends StatefulWidget {
  const _TagEditorDialog({
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
  State<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<_TagEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late bool _noMax;
  late int _groupId;

  bool get _isNumber => widget.group.kind == TagGroupKind.number;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _groupId = t?.groupId ?? widget.group.id;
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

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(hintText: '标签名称'),
            ),
            if (widget.initial != null && widget.moveTargets.length > 1) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: '所属组'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _groupId,
                    items: [
                      for (final g in widget.moveTargets)
                        DropdownMenuItem(value: g.id, child: Text(g.name)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _groupId = v);
                    },
                  ),
                ),
              ),
            ],
            if (_isNumber) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _min,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '下限（含）',
                  hintText: '如 0',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('无上限'),
                value: _noMax,
                onChanged: (v) => setState(() => _noMax = v),
              ),
              if (!_noMax)
                TextField(
                  controller: _max,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '上限（不含）',
                    hintText: '如 100',
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (!_isNumber) {
      Navigator.pop(
        context,
        _TagDraft(name: name, groupId: _groupId),
      );
      return;
    }
    final min = double.tryParse(_min.text.trim());
    if (min == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写有效下限')),
      );
      return;
    }
    double? max;
    if (!_noMax) {
      max = double.tryParse(_max.text.trim());
      if (max == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写有效上限，或勾选无上限')),
        );
        return;
      }
    }
    Navigator.pop(
      context,
      _TagDraft(
        name: name,
        groupId: _groupId,
        rangeMin: min,
        rangeMax: max,
      ),
    );
  }
}
