import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/app_database.dart';
import '../../providers/database_provider.dart';
import '../../providers/ledger_session_provider.dart';
import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/category_icon_view.dart';
import '../../widgets/page_status.dart';
import 'amount_keypad.dart';

/// 打开记一笔 / 编辑账单底部弹层。
///
/// [transactionId] 非空时为编辑模式。
/// [initialDate] 新建时预填发生日期（日历「在该日记账」用）。
/// 进出使用略加长的 easeOutCubic，比系统默认更顺一点。
Future<void> showRecordEditorSheet(
  BuildContext context, {
  int? transactionId,
  DateTime? initialDate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PigTokens.surface,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PigTokens.radiusSheet),
      ),
    ),
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 320),
      reverseDuration: Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (_) => RecordEditorSheet(
      transactionId: transactionId,
      initialDate: initialDate,
    ),
  );
}

/// 记一笔表单（对照 fig3；备注旁无相机）。
class RecordEditorSheet extends ConsumerStatefulWidget {
  const RecordEditorSheet({
    super.key,
    this.transactionId,
    this.initialDate,
  });

  final int? transactionId;
  final DateTime? initialDate;

  @override
  ConsumerState<RecordEditorSheet> createState() => _RecordEditorSheetState();
}

class _RecordEditorSheetState extends ConsumerState<RecordEditorSheet> {
  /// 金额表达式原始串，如 `12+3.5`；展示与求值分离。
  String _amountExpr = '';
  String _type = 'expense';
  late DateTime _happenedAt;
  int? _parentId;
  int? _categoryId;
  final Set<int> _tagIds = {};
  final _noteController = TextEditingController();
  bool _loading = false;
  bool _booted = false;

  bool get _isEdit => widget.transactionId != null;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialDate;
    if (seed != null && !_isEdit) {
      // 锁到中午，避免时区边界把自然日算错。
      _happenedAt = DateTime(seed.year, seed.month, seed.day, 12);
    } else {
      _happenedAt = DateTime.now();
    }
    if (_isEdit) {
      Future.microtask(_bootstrapEdit);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapEdit() async {
    if (_booted || !_isEdit) return;
    _booted = true;
    final repo = ref.read(transactionRepositoryProvider);
    final tx = await repo.getById(widget.transactionId!);
    if (tx == null || !mounted) return;
    final tagIds = await repo.getTagIds(tx.id);
    final cat = tx.categoryId == null
        ? null
        : await ref.read(categoryRepositoryProvider).getById(tx.categoryId!);
    setState(() {
      _type = tx.type;
      _amountExpr = _formatAmount(tx.amount);
      _happenedAt = tx.happenedAt;
      _noteController.text = tx.note ?? '';
      _tagIds
        ..clear()
        ..addAll(tagIds);
      if (cat != null) {
        if (cat.parentId == null) {
          _parentId = cat.id;
          _categoryId = cat.id;
        } else {
          _parentId = cat.parentId;
          _categoryId = cat.id;
        }
      }
    });
  }

  String _formatAmount(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// 将 `12+3-1.5` 求值为 double；非法时返回 null。
  double? _evaluateAmount() {
    final raw = _amountExpr.trim();
    if (raw.isEmpty) return null;
    // 末尾运算符视为未完成
    if (raw.endsWith('+') || raw.endsWith('-') || raw.endsWith('.')) {
      return null;
    }
    final parts = RegExp(r'[+\-]').allMatches(raw).isEmpty
        ? <String>[raw]
        : null;
    if (parts != null) {
      return double.tryParse(raw);
    }

    var total = 0.0;
    var sign = 1.0;
    final buf = StringBuffer();
    void flush() {
      final s = buf.toString();
      if (s.isEmpty) return;
      final n = double.tryParse(s);
      if (n == null) return;
      total += sign * n;
      buf.clear();
    }

    // 处理开头的符号
    var i = 0;
    if (raw.startsWith('+')) {
      i = 1;
    } else if (raw.startsWith('-')) {
      sign = -1;
      i = 1;
    }
    for (; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '+' || ch == '-') {
        flush();
        sign = ch == '-' ? -1 : 1;
      } else {
        buf.write(ch);
      }
    }
    flush();
    final abs = total.abs();
    if (abs <= 0) return null;
    return abs;
  }

  void _onKey(String key) {
    setState(() {
      if (key == '+' || key == '-') {
        if (_amountExpr.isEmpty) return;
        final last = _amountExpr[_amountExpr.length - 1];
        if (last == '+' || last == '-' || last == '.') return;
        _amountExpr += key;
        return;
      }
      if (key == '.') {
        // 当前数字段已有小数点则忽略
        final seg = _amountExpr.split(RegExp(r'[+\-]')).last;
        if (seg.contains('.')) return;
        if (seg.isEmpty) {
          _amountExpr += '0.';
        } else {
          _amountExpr += '.';
        }
        return;
      }
      _amountExpr += key;
    });
  }

  void _onBackspace() {
    if (_amountExpr.isEmpty) return;
    setState(() => _amountExpr = _amountExpr.substring(0, _amountExpr.length - 1));
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _happenedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      _happenedAt = DateTime(
        d.year,
        d.month,
        d.day,
        _happenedAt.hour,
        _happenedAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_happenedAt),
    );
    if (t == null) return;
    setState(() {
      _happenedAt = DateTime(
        _happenedAt.year,
        _happenedAt.month,
        _happenedAt.day,
        t.hour,
        t.minute,
      );
    });
  }

  void _toast(String message) {
    // 使用弹层内 Scaffold 的 Messenger，避免提示出现在底层页面、关掉弹层才看见
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool> _persist({required bool keepOpen}) async {
    final amount = _evaluateAmount();
    if (amount == null) {
      _toast('请输入有效金额');
      return false;
    }
    if (_categoryId == null) {
      _toast('请选择分类');
      return false;
    }
    final ledgerId = ref.read(currentLedgerIdProvider);
    if (ledgerId == null) return false;

    setState(() => _loading = true);
    try {
      final repo = ref.read(transactionRepositoryProvider);
      if (_isEdit) {
        await repo.update(
          id: widget.transactionId!,
          type: _type,
          amount: amount,
          categoryId: _categoryId,
          happenedAt: _happenedAt,
          note: _noteController.text,
          tagIds: _tagIds.toList(),
        );
      } else {
        await repo.insert(
          ledgerId: ledgerId,
          type: _type,
          amount: amount,
          categoryId: _categoryId,
          happenedAt: _happenedAt,
          note: _noteController.text,
          tagIds: _tagIds.toList(),
        );
      }
      if (keepOpen) {
        setState(() {
          _amountExpr = '';
          _noteController.clear();
          _tagIds.clear();
          // 分类保留，方便连续记同类
        });
        return true;
      }
      if (mounted) Navigator.of(context).pop();
      return true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dateLabel() {
    final now = DateTime.now();
    final sameDay = now.year == _happenedAt.year &&
        now.month == _happenedAt.month &&
        now.day == _happenedAt.day;
    if (sameDay) return '今天';
    return DateFormat('M月d日').format(_happenedAt);
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = _type == 'expense'
        ? ref.watch(expenseCategoriesProvider)
        : ref.watch(incomeCategoriesProvider);
    final tagBundlesAsync = ref.watch(tagGroupBundlesProvider);

    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    // 自带 Scaffold，保证校验 SnackBar 显示在记一笔弹层内
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Scaffold(
        backgroundColor: PigTokens.surface,
        body: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.92,
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
                    PigTokens.spaceSm,
                    0,
                  ),
                  child: Row(
                    children: [
                      _TypeToggle(
                        type: _type,
                        onChanged: (t) {
                          setState(() {
                            _type = t;
                            _parentId = null;
                            _categoryId = null;
                          });
                        },
                      ),
                      const Spacer(),
                      _MetaChip(
                        icon: Icons.calendar_today_outlined,
                        label: _dateLabel(),
                        onTap: _pickDate,
                      ),
                      const SizedBox(width: PigTokens.spaceSm),
                      _MetaChip(
                        icon: Icons.schedule_outlined,
                        label: DateFormat('HH:mm').format(_happenedAt),
                        onTap: _pickTime,
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PigTokens.spaceXl,
                    PigTokens.spaceMd,
                    PigTokens.spaceXl,
                    PigTokens.spaceMd,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '¥',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: _type == 'expense'
                              ? PigTokens.textPrimary
                              : PigTokens.income,
                        ),
                      ),
                      const SizedBox(width: PigTokens.spaceSm),
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                            color: _amountExpr.isEmpty
                                ? PigTokens.textTertiary
                                : PigTokens.textPrimary,
                          ),
                          child: Text(
                            _amountExpr.isEmpty ? '0' : _amountExpr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: catsAsync.when(
                    loading: () => const AppLoading(message: '加载分类…'),
                    error: (e, _) => AppErrorState(
                      message: '分类加载失败',
                      onRetry: () {
                        ref.invalidate(
                          _type == 'expense'
                              ? expenseCategoriesProvider
                              : incomeCategoriesProvider,
                        );
                      },
                    ),
                    data: (cats) {
                      return _CategoryPicker(
                        categories: cats,
                        parentId: _parentId,
                        categoryId: _categoryId,
                        onParent: (id) {
                          setState(() {
                            _parentId = id;
                            _categoryId = id; // 主分类可直接记账
                          });
                        },
                        onChild: (id) => setState(() => _categoryId = id),
                        onAdd: () => _toast('请到「我的 → 分类管理」添加分类'),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PigTokens.spaceLg,
                    0,
                    PigTokens.spaceLg,
                    PigTokens.spaceSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _noteController,
                        decoration: InputDecoration(
                          hintText: '点击填写备注',
                          filled: true,
                          fillColor: PigTokens.surfaceInput,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(PigTokens.radiusCard),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: PigTokens.spaceMd,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: PigTokens.spaceSm),
                      tagBundlesAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (bundles) {
                          final hasTags =
                              bundles.any((b) => b.tags.isNotEmpty);
                          if (!hasTags) {
                            return const Text(
                              '暂无标签，可在「我的 → 标签管理」添加',
                              style: TextStyle(
                                fontSize: 12,
                                color: PigTokens.textTertiary,
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final bundle in bundles)
                                if (bundle.tags.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: PigTokens.spaceXs,
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
                                          selected:
                                              _tagIds.contains(tag.id),
                                          showCheckmark: false,
                                          selectedColor:
                                              PigTokens.primarySoft,
                                          labelStyle: TextStyle(
                                            color: _tagIds.contains(tag.id)
                                                ? PigTokens.primary
                                                : PigTokens.textSecondary,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 13,
                                          ),
                                          side: BorderSide.none,
                                          onSelected: (sel) {
                                            setState(() {
                                              if (bundle.isNumber) {
                                                for (final t
                                                    in bundle.tags) {
                                                  _tagIds.remove(t.id);
                                                }
                                                if (sel) {
                                                  _tagIds.add(tag.id);
                                                }
                                              } else if (sel) {
                                                _tagIds.add(tag.id);
                                              } else {
                                                _tagIds.remove(tag.id);
                                              }
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PigTokens.spaceSm,
                    0,
                    PigTokens.spaceSm,
                    PigTokens.spaceSm,
                  ),
                  child: AbsorbPointer(
                    absorbing: _loading,
                    child: AmountKeypad(
                      onKey: _onKey,
                      onBackspace: _onBackspace,
                      onSave: () => _persist(keepOpen: false),
                      onSaveAndContinue: () => _persist(keepOpen: true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 日期 / 时间轻量胶囊按钮。
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PigTokens.surfaceSecondary,
      borderRadius: BorderRadius.circular(PigTokens.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PigTokens.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: PigTokens.spaceSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: PigTokens.textSecondary),
              const SizedBox(width: PigTokens.spaceXs),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: PigTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.type, required this.onChanged});

  final String type;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String value, String label) {
      final selected = type == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? PigTokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(PigTokens.radiusPill),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? PigTokens.primary : PigTokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(PigTokens.spaceXs / 2 + 1),
      decoration: BoxDecoration(
        color: PigTokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(PigTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip('expense', '支出'),
          chip('income', '收入'),
        ],
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.parentId,
    required this.categoryId,
    required this.onParent,
    required this.onChild,
    required this.onAdd,
  });

  final List<Category> categories;
  final int? parentId;
  final int? categoryId;
  final ValueChanged<int> onParent;
  final ValueChanged<int> onChild;
  final VoidCallback onAdd;

  static const _chipW = 68.0;
  static const _spacing = PigTokens.spaceSm;

  @override
  Widget build(BuildContext context) {
    final parents =
        categories.where((c) => c.parentId == null).toList(growable: false);
    final children = parentId == null
        ? const <Category>[]
        : categories
            .where((c) => c.parentId == parentId)
            .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = ((constraints.maxWidth + _spacing) / (_chipW + _spacing))
            .floor()
            .clamp(4, 6);
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
                    width: _chipW,
                    child: _CatChip(
                      label: rowItems[j].name,
                      category: rowItems[j],
                      selected: parentId == rowItems[j].id ||
                          categoryId == rowItems[j].id,
                      onTap: () => onParent(rowItems[j].id),
                    ),
                  ),
                ],
              ],
            ),
          );

          final expandedInRow = rowItems.any((c) => c.id == parentId);
          if (expandedInRow && parentId != null) {
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
                    color: PigTokens.surfaceSecondary.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(PigTokens.radiusCard),
                  ),
                  child: Wrap(
                    spacing: _spacing,
                    runSpacing: _spacing,
                    children: [
                      for (final c in children)
                        _CatChip(
                          label: c.name,
                          category: c,
                          selected: categoryId == c.id,
                          compact: true,
                          onTap: () => onChild(c.id),
                        ),
                      _CatChip(
                        label: '添加',
                        icon: Icons.add,
                        iconColor: PigTokens.textTertiary,
                        selected: false,
                        compact: true,
                        onTap: onAdd,
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
            PigTokens.spaceMd,
            PigTokens.spaceSm,
            PigTokens.spaceMd,
            PigTokens.spaceSm,
          ),
          children: rows,
        );
      },
    );
  }
}

class _CatChip extends StatelessWidget {
  const _CatChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.category,
    this.icon,
    this.iconColor,
    this.compact = false,
  });

  final String label;
  final Category? category;
  final IconData? icon;
  final Color? iconColor;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PigTokens.primary : PigTokens.textSecondary;
    final diameter = compact ? 40.0 : 44.0;
    final iconSize = compact ? 20.0 : 22.0;
    final fallbackColor = iconColor ?? PigTokens.textTertiary;

    Widget avatar;
    if (category != null) {
      avatar = CategoryIconCircle(
        name: category!.name,
        icon: category!.icon,
        iconType: category!.iconType,
        customIconPath: category!.customIconPath,
        diameter: diameter,
        iconSize: iconSize,
        backgroundColor: selected ? PigTokens.primarySoft : null,
      );
    } else {
      avatar = Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: selected
              ? PigTokens.primarySoft
              : fallbackColor.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon ?? Icons.category_outlined,
          color: selected ? PigTokens.primary : fallbackColor,
          size: iconSize,
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      child: SizedBox(
        width: compact ? 64 : 68,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: PigTokens.primary, width: 1.5)
                    : null,
              ),
              child: avatar,
            ),
            const SizedBox(height: PigTokens.spaceXs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
