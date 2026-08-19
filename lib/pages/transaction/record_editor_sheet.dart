import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/app_database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/ledger_session_provider.dart';
import '../../providers/transaction_providers.dart';
import '../../providers/widget_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/happened_at.dart';
import '../../utils/tag_colors.dart';
import '../../widgets/category_icon_view.dart';
import '../../widgets/page_status.dart';
import '../../widgets/workspace_sheet.dart';
import 'amount_keypad.dart';
import 'image_billing_sheet.dart';

/// 打开记一笔 / 编辑账单底部弹层。
///
/// [transactionId] 非空时为编辑模式。
/// [initialDate] 新建时预填发生日期（日历「在该日记账」用）。
/// [initialType] 新建时预填 `expense` / `income`（桌面小组件深链用）。
/// 进出使用略加长的 easeOutCubic，比系统默认更顺一点。
Future<void> showRecordEditorSheet(
  BuildContext context, {
  int? transactionId,
  DateTime? initialDate,
  String? initialType,
}) {
  return showWorkspaceSheet<void>(
    context,
    fixedHeight: true,
    ignoreKeyboard: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 320),
      reverseDuration: Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (_) => RecordEditorSheet(
      transactionId: transactionId,
      initialDate: initialDate,
      initialType: initialType,
    ),
  );
}

/// 记一笔表单（对照 fig3；新建时备注旁有相机入口，ADR-016）。
class RecordEditorSheet extends ConsumerStatefulWidget {
  const RecordEditorSheet({
    super.key,
    this.transactionId,
    this.initialDate,
    this.initialType,
  });

  final int? transactionId;
  final DateTime? initialDate;
  /// 新建时：`expense` / `income`。
  final String? initialType;

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
      _happenedAt = HappenedAt.onCalendarDay(seed);
    } else {
      _happenedAt = HappenedAt.now();
    }
    final t = widget.initialType;
    if (!_isEdit && (t == 'expense' || t == 'income')) {
      _type = t!;
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

  void _pruneTagsForType(String type) {
    final bundles = ref.read(tagGroupBundlesProvider).valueOrNull;
    if (bundles == null) return;
    final allowed = <int>{
      for (final b in bundles)
        if (TagGroupScope.matchesType(b.group.scope, type))
          for (final t in b.tags) t.id,
    };
    _tagIds.removeWhere((id) => !allowed.contains(id));
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
      _happenedAt = HappenedAt.withDate(_happenedAt, d);
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_happenedAt),
    );
    if (t == null) return;
    setState(() {
      _happenedAt = HappenedAt.withHourMinute(
        _happenedAt,
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

  /// 备注旁相机：先选拍照/相册，关本弹层丢草稿，再走 Vision（ADR-016）。
  Future<void> _onNoteCamera() async {
    final choice = await showModalBottomSheet<_NoteCameraChoice>(
      context: context,
      backgroundColor: PigTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PigTokens.radiusSheet),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照'),
                onTap: () => Navigator.pop(ctx, _NoteCameraChoice.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: const Text('从相册'),
                onTap: () => Navigator.pop(ctx, _NoteCameraChoice.gallery),
              ),
              ListTile(
                title: const Text('取消', textAlign: TextAlign.center),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;

    final navigator = Navigator.of(context);
    navigator.pop(); // 关闭记一笔，丢弃未保存草稿

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!navigator.mounted) return;
    final host = navigator.context;
    if (!host.mounted) return;
    switch (choice) {
      case _NoteCameraChoice.camera:
        await takePhotoForBilling(host);
      case _NoteCameraChoice.gallery:
        await pickImageForBilling(host, source: 'screenshot');
    }
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
      // 桌面小组件：保存成功后尽快刷新数字
      unawaited(updateAppWidget(ref));
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
    } on StateError catch (e) {
      _toast(e.message);
      return false;
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

  /// 主界面标签摘要：已选名；过多则「A、B +N」；空则未选择 / 暂无可用。
  String _tagSummary(List<TagGroupBundle> visible) {
    final names = <String>[];
    for (final b in visible) {
      for (final t in b.tags) {
        if (_tagIds.contains(t.id)) names.add(t.name);
      }
    }
    if (names.isEmpty) {
      final hasTags = visible.any((b) => b.tags.isNotEmpty);
      return hasTags ? '未选择' : '暂无可用标签';
    }
    if (names.length <= 2) return names.join('、');
    return '${names.take(2).join('、')} +${names.length - 2}';
  }

  void _toggleTag(TagGroupBundle bundle, Tag tag, bool selected) {
    setState(() {
      if (bundle.isNumber) {
        for (final t in bundle.tags) {
          _tagIds.remove(t.id);
        }
        if (selected) _tagIds.add(tag.id);
      } else if (selected) {
        _tagIds.add(tag.id);
      } else {
        _tagIds.remove(tag.id);
      }
    });
  }

  Future<void> _openTagPicker(List<TagGroupBundle> visible) {
    return showModalBottomSheet<void>(
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
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _TagPickerSheet(
              bundles: visible,
              selectedIds: _tagIds,
              onToggle: (bundle, tag, selected) {
                _toggleTag(bundle, tag, selected);
                setModalState(() {});
              },
            );
          },
        );
      },
    );
  }

  /// 备注另开较矮弹层调系统键盘；主层始终保留金额键盘（ADR-039）。
  Future<void> _openNoteEditor() async {
    final result = await showWorkspaceSheet<String>(
      context,
      fixedHeight: true,
      ignoreKeyboard: false,
      useRootNavigator: true,
      heightFraction: PigTokens.noteSheetFraction,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => _NoteEditorSheet(initialText: _noteController.text),
    );
    if (result == null || !mounted) return;
    setState(() => _noteController.text = result);
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = _type == 'expense'
        ? ref.watch(expenseCategoriesProvider)
        : ref.watch(incomeCategoriesProvider);
    final tagBundlesAsync = ref.watch(tagGroupBundlesProvider);

    // 自带 Scaffold，保证校验 SnackBar 显示在记一笔弹层内。
    // 高度由 showWorkspaceSheet(fixedHeight) 钉死；Scaffold 本身会吃满最大约束。
    return Scaffold(
      backgroundColor: PigTokens.surface,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
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
                            _pruneTagsForType(t);
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
                    PigTokens.spaceSm,
                    PigTokens.spaceMd,
                    PigTokens.spaceSm,
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
                    PigTokens.spaceSm,
                    0,
                    PigTokens.spaceSm,
                    PigTokens.spaceSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _NoteEntryRow(
                              text: _noteController.text,
                              onTap: _loading ? null : _openNoteEditor,
                            ),
                          ),
                          if (!_isEdit) ...[
                            const SizedBox(width: PigTokens.spaceSm),
                            IconButton(
                              onPressed: _loading ? null : _onNoteCamera,
                              tooltip: '图片记账',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                color: PigTokens.textTertiary,
                                size: 26,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: PigTokens.spaceSm),
                      tagBundlesAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (bundles) {
                          final visible = bundles
                              .where(
                                (b) => TagGroupScope.matchesType(
                                  b.group.scope,
                                  _type,
                                ),
                              )
                              .toList();
                          return _TagEntryRow(
                            summary: _tagSummary(visible),
                            onTap: () => _openTagPicker(visible),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // 主层固定金额键盘；备注在独立弹层用系统键盘（ADR-039）。
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
      );
  }
}

/// 主层备注入口：只展示摘要，点开记一笔备注弹层（ADR-039）。
class _NoteEntryRow extends StatelessWidget {
  const _NoteEntryRow({
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final empty = text.trim().isEmpty;
    return Material(
      color: PigTokens.surfaceInput,
      borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PigTokens.spaceMd,
            vertical: 10,
          ),
          child: Text(
            empty ? '点击填写备注' : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: empty ? PigTokens.textTertiary : PigTokens.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 记一笔备注弹层：较矮、自动聚焦系统键盘；点「完成」才写回（ADR-039）。
class _NoteEditorSheet extends StatefulWidget {
  const _NoteEditorSheet({required this.initialText});

  final String initialText;

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _complete() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
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
                  PigTokens.spaceSm,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '备注',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: PigTokens.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _complete,
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PigTokens.spaceSm,
                    0,
                    PigTokens.spaceSm,
                    PigTokens.spaceSm,
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: true,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: '填写备注',
                      hintStyle: const TextStyle(
                        color: PigTokens.textTertiary,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: PigTokens.surfaceInput,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          PigTokens.radiusCard,
                        ),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          PigTokens.radiusCard,
                        ),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          PigTokens.radiusCard,
                        ),
                        borderSide: const BorderSide(
                          color: PigTokens.primarySoft,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(PigTokens.spaceMd),
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      color: PigTokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

/// 备注下方「标签」入口行：摘要 + 打开选标弹层。
class _TagEntryRow extends StatelessWidget {
  const _TagEntryRow({
    required this.summary,
    required this.onTap,
  });

  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PigTokens.surfaceInput,
      borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PigTokens.spaceMd,
            vertical: PigTokens.spaceSm,
          ),
          child: Row(
            children: [
              const Text(
                '标签',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PigTokens.textPrimary,
                ),
              ),
              const SizedBox(width: PigTokens.spaceMd),
              Expanded(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: summary == '未选择' || summary == '暂无可用标签'
                        ? PigTokens.textTertiary
                        : PigTokens.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: PigTokens.spaceXs),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: PigTokens.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 记一笔选标弹层：按组展示 chip，点选即时生效。
class _TagPickerSheet extends StatelessWidget {
  const _TagPickerSheet({
    required this.bundles,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<TagGroupBundle> bundles;
  final Set<int> selectedIds;
  final void Function(TagGroupBundle bundle, Tag tag, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    final hasTags = bundles.any((b) => b.tags.isNotEmpty);
    final maxH = MediaQuery.sizeOf(context).height * 0.55;

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
            const Padding(
              padding: EdgeInsets.fromLTRB(
                PigTokens.spaceLg,
                PigTokens.spaceMd,
                PigTokens.spaceLg,
                PigTokens.spaceSm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择标签',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: PigTokens.textPrimary,
                  ),
                ),
              ),
            ),
            Expanded(
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
                                    selected: selectedIds.contains(tag.id),
                                    showCheckmark: false,
                                    selectedColor: TagColors.parse(tag.color)
                                        .withValues(alpha: 0.18),
                                    backgroundColor: TagColors.parse(tag.color)
                                        .withValues(alpha: 0.08),
                                    labelStyle: TextStyle(
                                      color: TagColors.parse(tag.color),
                                      fontWeight: selectedIds.contains(tag.id)
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                    side: BorderSide(
                                      color: selectedIds.contains(tag.id)
                                          ? TagColors.parse(tag.color)
                                          : Colors.transparent,
                                      width: 1.5,
                                    ),
                                    onSelected: (sel) =>
                                        onToggle(bundle, tag, sel),
                                  ),
                              ],
                            ),
                          ],
                      ],
                    ),
            ),
          ],
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

  /// 均分列宽时的参考芯片宽，用于估算列数。
  static const _refChipW = 68.0;
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
        // 与备注/键盘同一内容区：左右 spaceSm，列宽按扣边距后均分。
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
            inset,
            PigTokens.spaceSm,
            inset,
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
    // 与分类管理「改为子类」一致：未选灰显，选中全彩。
    final color =
        selected ? PigTokens.textPrimary : PigTokens.textTertiary;
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
          icon ?? Icons.category,
          color: selected ? PigTokens.primary : fallbackColor,
          size: iconSize,
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
            Opacity(
              opacity: selected ? 1 : 0.45,
              child: avatar,
            ),
            const SizedBox(height: PigTokens.spaceXs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

enum _NoteCameraChoice { camera, gallery }
