import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/app_database.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/category_icon_view.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_status.dart';
import '../../widgets/transaction/transaction_row_tile.dart';
import '../../widgets/pig_toast.dart';

/// 账单搜索页：关键词 + 金额/日期/分类筛选 + 批量改备注/分类/删除。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _keywordController = TextEditingController();
  String _keyword = '';
  double? _minAmount;
  double? _maxAmount;
  DateTime? _startDate;
  DateTime? _endDate;
  Category? _category;

  bool _batchMode = false;
  final Set<int> _selectedIds = {};

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  bool get _hasFilter =>
      _keyword.isNotEmpty ||
      _minAmount != null ||
      _maxAmount != null ||
      _startDate != null ||
      _endDate != null ||
      _category != null;

  List<TransactionListItem> _filter(List<TransactionListItem> all) {
    if (!_hasFilter) return const [];

    final kw = _keyword.toLowerCase();
    return all.where((item) {
      final tx = item.tx;

      if (kw.isNotEmpty) {
        final note = tx.note?.toLowerCase() ?? '';
        final cat = item.categoryName?.toLowerCase() ?? '';
        final amountStr = tx.amount.toString();
        final tags = item.tagNames.map((e) => e.toLowerCase()).join(' ');
        final hit = note.contains(kw) ||
            cat.contains(kw) ||
            amountStr.contains(kw) ||
            tags.contains(kw);
        if (!hit) return false;
      }

      if (_category != null) {
        final id = tx.categoryId;
        final match = id == _category!.id ||
            item.categoryParentId == _category!.id;
        if (!match) return false;
      }

      if (_minAmount != null || _maxAmount != null) {
        final abs = tx.amount.abs();
        if (_minAmount != null && abs < _minAmount!) return false;
        if (_maxAmount != null && abs > _maxAmount!) return false;
      }

      if (_startDate != null) {
        final start = DateTime(
          _startDate!.year,
          _startDate!.month,
          _startDate!.day,
        );
        if (tx.happenedAt.isBefore(start)) return false;
      }
      if (_endDate != null) {
        final end = DateTime(
          _endDate!.year,
          _endDate!.month,
          _endDate!.day,
        ).add(const Duration(days: 1));
        if (!tx.happenedAt.isBefore(end)) return false;
      }

      return true;
    }).toList();
  }

  Future<void> _openFilter() async {
    double? minA = _minAmount;
    double? maxA = _maxAmount;
    DateTime? start = _startDate;
    DateTime? end = _endDate;
    Category? cat = _category;

    final minCtrl = TextEditingController(
      text: minA?.toStringAsFixed(2) ?? '',
    );
    final maxCtrl = TextEditingController(
      text: maxA?.toStringAsFixed(2) ?? '',
    );

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PigTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PigTokens.radiusSheet),
        ),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: PigTokens.spaceLg,
                right: PigTokens.spaceLg,
                top: PigTokens.spaceLg,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + PigTokens.spaceLg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '筛选',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: PigTokens.spaceMd),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('分类'),
                      subtitle: Text(cat?.name ?? '全部'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (cat != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setModal(() => cat = null),
                            ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () async {
                        final picked = await _pickCategory(ctx);
                        if (picked != null) {
                          setModal(() => cat = picked);
                        }
                      },
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '最小金额',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('~'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: maxCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '最大金额',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: PigTokens.spaceMd),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开始日期'),
                      subtitle: Text(
                        start == null
                            ? '不限'
                            : DateFormat('y-MM-dd').format(start!),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (start != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setModal(() => start = null),
                            ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: start ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setModal(() => start = d);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('结束日期'),
                      subtitle: Text(
                        end == null
                            ? '不限'
                            : DateFormat('y-MM-dd').format(end!),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (end != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setModal(() => end = null),
                            ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: end ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setModal(() => end = d);
                      },
                    ),
                    const SizedBox(height: PigTokens.spaceLg),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            minCtrl.clear();
                            maxCtrl.clear();
                            setModal(() {
                              cat = null;
                              start = null;
                              end = null;
                            });
                          },
                          child: const Text('清空'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () {
                            minA = double.tryParse(minCtrl.text.trim());
                            maxA = double.tryParse(maxCtrl.text.trim());
                            Navigator.pop(ctx, true);
                          },
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    minCtrl.dispose();
    maxCtrl.dispose();

    if (confirmed == true && mounted) {
      setState(() {
        _minAmount = minA;
        _maxAmount = maxA;
        _startDate = start;
        _endDate = end;
        _category = cat;
      });
    }
  }

  Future<Category?> _pickCategory(BuildContext context) async {
    final expense = await ref.read(categoryRepositoryProvider).listByKind('expense');
    final income = await ref.read(categoryRepositoryProvider).listByKind('income');
    if (!context.mounted) return null;

    return showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PigTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PigTokens.radiusSheet),
        ),
      ),
      builder: (ctx) {
        final parents = [
          ...expense.where((c) => c.parentId == null),
          ...income.where((c) => c.parentId == null),
        ];
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return ListView(
              controller: controller,
              children: [
                const ListTile(title: Text('选择分类')),
                for (final p in parents) ...[
                  ListTile(
                    leading: CategoryIconCircle(
                      name: p.name,
                      icon: p.icon,
                      iconType: p.iconType,
                      customIconPath: p.customIconPath,
                      diameter: 36,
                      iconSize: 18,
                    ),
                    title: Text(p.name),
                    subtitle: Text(p.kind == 'expense' ? '支出' : '收入'),
                    onTap: () => Navigator.pop(ctx, p),
                  ),
                  for (final child in [
                    ...expense.where((c) => c.parentId == p.id),
                    ...income.where((c) => c.parentId == p.id),
                  ])
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 48, right: 16),
                      leading: CategoryIconCircle(
                        name: child.name,
                        icon: child.icon,
                        iconType: child.iconType,
                        customIconPath: child.customIconPath,
                        diameter: 32,
                        iconSize: 16,
                      ),
                      title: Text(child.name),
                      onTap: () => Navigator.pop(ctx, child),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _batchSetNote(List<TransactionListItem> results) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量设置备注'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '备注（可留空清空）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    final note = ctrl.text.trim();
    ctrl.dispose();
    final repo = ref.read(transactionRepositoryProvider);
    final byId = {for (final e in results) e.tx.id: e};
    for (final id in _selectedIds) {
      final item = byId[id];
      if (item == null) continue;
      final tagIds = await repo.getTagIds(id);
      await repo.update(
        id: id,
        type: item.tx.type,
        amount: item.tx.amount,
        categoryId: item.tx.categoryId,
        happenedAt: item.tx.happenedAt,
        note: note.isEmpty ? null : note,
        tagIds: tagIds,
      );
    }
    if (mounted) {
      setState(() {
        _batchMode = false;
        _selectedIds.clear();
      });
      PigToast.show(context, '已更新备注');
    }
  }

  Future<void> _batchChangeCategory(List<TransactionListItem> results) async {
    final selected = results.where((e) => _selectedIds.contains(e.tx.id)).toList();
    if (selected.isEmpty) return;
    final types = selected.map((e) => e.tx.type).toSet();
    if (types.length > 1) {
      PigToast.show(context, '请选择同一类型（支出或收入）的账单');
      return;
    }
    final kind = types.first;
    final cats = await ref.read(categoryRepositoryProvider).listByKind(kind);
    if (!mounted) return;
    final picked = await showModalBottomSheet<Category>(
      context: context,
      backgroundColor: PigTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PigTokens.radiusSheet),
        ),
      ),
      builder: (ctx) {
        final parents = cats.where((c) => c.parentId == null).toList();
        return ListView(
          children: [
            const ListTile(title: Text('改为分类')),
            for (final p in parents) ...[
              ListTile(
                leading: CategoryIconCircle(
                  name: p.name,
                  icon: p.icon,
                  iconType: p.iconType,
                  customIconPath: p.customIconPath,
                  diameter: 36,
                  iconSize: 18,
                ),
                title: Text(p.name),
                onTap: () => Navigator.pop(ctx, p),
              ),
              for (final child in cats.where((c) => c.parentId == p.id))
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 48, right: 16),
                  leading: CategoryIconCircle(
                    name: child.name,
                    icon: child.icon,
                    iconType: child.iconType,
                    customIconPath: child.customIconPath,
                    diameter: 32,
                    iconSize: 16,
                  ),
                  title: Text(child.name),
                  onTap: () => Navigator.pop(ctx, child),
                ),
            ],
          ],
        );
      },
    );
    if (picked == null) return;
    final repo = ref.read(transactionRepositoryProvider);
    for (final item in selected) {
      final tagIds = await repo.getTagIds(item.tx.id);
      await repo.update(
        id: item.tx.id,
        type: item.tx.type,
        amount: item.tx.amount,
        categoryId: picked.id,
        happenedAt: item.tx.happenedAt,
        note: item.tx.note,
        tagIds: tagIds,
      );
    }
    if (mounted) {
      setState(() {
        _batchMode = false;
        _selectedIds.clear();
      });
      PigToast.show(context, '已更改分类');
    }
  }

  Future<void> _batchDelete() async {
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 $count 笔账单？删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(transactionRepositoryProvider);
    for (final id in _selectedIds.toList()) {
      await repo.delete(id);
    }
    if (mounted) {
      setState(() {
        _batchMode = false;
        _selectedIds.clear();
      });
      PigToast.show(context, '已删除 $count 笔');
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncAll = ref.watch(ledgerTransactionsProvider);

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: Text(_batchMode ? '已选 ${_selectedIds.length}' : '搜索'),
        leading: _batchMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _batchMode = false;
                  _selectedIds.clear();
                }),
              )
            : null,
        actions: [
          if (_batchMode && asyncAll.hasValue)
            TextButton(
              onPressed: () {
                final results = _filter(asyncAll.requireValue);
                setState(() {
                  if (_selectedIds.length == results.length) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds
                      ..clear()
                      ..addAll(results.map((e) => e.tx.id));
                  }
                });
              },
              child: const Text('全选'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_batchMode)
            Material(
              color: PigTokens.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  PigTokens.spaceLg,
                  PigTokens.spaceSm,
                  PigTokens.spaceSm,
                  PigTokens.spaceSm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keywordController,
                        decoration: InputDecoration(
                          hintText: '备注、分类、标签、金额',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: PigTokens.surfaceInput,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(PigTokens.radiusPill),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: PigTokens.spaceMd,
                          ),
                        ),
                        onChanged: (v) => setState(() => _keyword = v.trim()),
                      ),
                    ),
                    IconButton(
                      tooltip: '筛选',
                      onPressed: _openFilter,
                      icon: Icon(
                        Icons.filter_list,
                        color: (_minAmount != null ||
                                _maxAmount != null ||
                                _startDate != null ||
                                _endDate != null ||
                                _category != null)
                            ? PigTokens.primary
                            : PigTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_hasFilter &&
              (_minAmount != null ||
                  _maxAmount != null ||
                  _startDate != null ||
                  _endDate != null ||
                  _category != null))
            Material(
              color: PigTokens.surface,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                  PigTokens.spaceLg,
                  0,
                  PigTokens.spaceLg,
                  PigTokens.spaceSm,
                ),
                child: Row(
                  children: [
                    if (_category != null)
                      _FilterChip(
                        label: '分类:${_category!.name}',
                        onClear: () => setState(() => _category = null),
                      ),
                    if (_minAmount != null || _maxAmount != null)
                      _FilterChip(
                        label:
                            '金额:${_minAmount?.toStringAsFixed(0) ?? '0'}~${_maxAmount?.toStringAsFixed(0) ?? '∞'}',
                        onClear: () => setState(() {
                          _minAmount = null;
                          _maxAmount = null;
                        }),
                      ),
                    if (_startDate != null || _endDate != null)
                      _FilterChip(
                        label:
                            '日期:${_startDate != null ? DateFormat('MM/dd').format(_startDate!) : '…'}-${_endDate != null ? DateFormat('MM/dd').format(_endDate!) : '…'}',
                        onClear: () => setState(() {
                          _startDate = null;
                          _endDate = null;
                        }),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: asyncAll.when(
              loading: () => const AppLoading(message: '加载账单…'),
              error: (e, _) => AppErrorState(
                message: '加载失败',
                onRetry: () => ref.invalidate(ledgerTransactionsProvider),
              ),
              data: (all) {
                if (!_hasFilter) {
                  return const EmptyState(
                    icon: Icons.search,
                    message: '输入关键词或设置筛选开始搜索',
                  );
                }
                final results = _filter(all);
                if (results.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_off,
                    message: '没有匹配的账单',
                  );
                }

                var expense = 0.0;
                var income = 0.0;
                for (final i in results) {
                  if (i.tx.type == 'expense') {
                    expense += i.tx.amount;
                  } else {
                    income += i.tx.amount;
                  }
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PigTokens.spaceLg,
                        vertical: PigTokens.spaceSm,
                      ),
                      child: Row(
                        children: [
                          Text(
                            '共 ${results.length} 笔',
                            style: const TextStyle(
                              fontSize: 13,
                              color: PigTokens.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '支 ¥${expense.toStringAsFixed(2)}  收 ¥${income.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: PigTokens.textTertiary,
                            ),
                          ),
                          if (!_batchMode)
                            TextButton(
                              onPressed: () => setState(() => _batchMode = true),
                              child: const Text('批量'),
                            ),
                        ],
                      ),
                    ),
                    if (_batchMode)
                      Material(
                        color: PigTokens.surface,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: PigTokens.spaceSm,
                            vertical: PigTokens.spaceXs,
                          ),
                          child: Row(
                            children: [
                              TextButton(
                                onPressed: _selectedIds.isEmpty
                                    ? null
                                    : () => _batchSetNote(results),
                                child: const Text('改备注'),
                              ),
                              TextButton(
                                onPressed: _selectedIds.isEmpty
                                    ? null
                                    : () => _batchChangeCategory(results),
                                child: const Text('改分类'),
                              ),
                              TextButton(
                                onPressed:
                                    _selectedIds.isEmpty ? null : _batchDelete,
                                child: const Text(
                                  '删除',
                                  style: TextStyle(color: PigTokens.danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: PigTokens.spaceXl),
                        itemCount: results.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          final item = results[index];
                          final selected = _selectedIds.contains(item.tx.id);
                          return Material(
                            color: PigTokens.surface,
                            child: TransactionRowTile(
                              item: item,
                              selected: selected,
                              onToggleSelect: _batchMode
                                  ? () => setState(() {
                                        if (selected) {
                                          _selectedIds.remove(item.tx.id);
                                        } else {
                                          _selectedIds.add(item.tx.id);
                                        }
                                      })
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: PigTokens.spaceSm),
      child: InputChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onDeleted: onClear,
        backgroundColor: PigTokens.primarySoft,
        side: BorderSide.none,
      ),
    );
  }
}
