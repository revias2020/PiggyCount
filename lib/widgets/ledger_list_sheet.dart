import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_provider.dart';
import '../providers/ledger_session_provider.dart';
import '../styles/tokens.dart';

/// 弹出账本列表（切换 + 管理唯一入口）。
Future<void> showLedgerListSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PigTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const LedgerListSheet(),
  );
}

/// 账本列表 BottomSheet：选中切换、新建、重命名、删除。
class LedgerListSheet extends ConsumerWidget {
  const LedgerListSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ledgerSessionProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: async.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('加载失败：$e'),
          data: (session) {
            final notifier = ref.read(ledgerSessionProvider.notifier);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: PigTokens.surfaceSecondary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '账本',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _promptCreate(context, notifier),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新建'),
                    ),
                  ],
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: session.ledgers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = session.ledgers[index];
                      final selected = item.id == session.currentId;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.name,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected
                                ? PigTokens.primary
                                : PigTokens.textPrimary,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (selected)
                              const Icon(
                                Icons.check_circle,
                                color: PigTokens.primary,
                                size: 20,
                              ),
                            IconButton(
                              tooltip: '重命名',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () =>
                                  _promptRename(context, notifier, item),
                            ),
                            IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () =>
                                  _confirmDelete(context, notifier, item),
                            ),
                          ],
                        ),
                        onTap: () async {
                          await notifier.select(item.id);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _promptCreate(
    BuildContext context,
    LedgerSessionNotifier notifier,
  ) async {
    final name = await _askName(context, title: '新建账本', initial: '');
    if (name == null) return;
    try {
      await notifier.create(name);
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _promptRename(
    BuildContext context,
    LedgerSessionNotifier notifier,
    LedgerItem item,
  ) async {
    final name = await _askName(
      context,
      title: '重命名账本',
      initial: item.name,
      excludeId: item.id,
    );
    if (name == null) return;
    try {
      await notifier.rename(item.id, name);
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    LedgerSessionNotifier notifier,
    LedgerItem item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账本'),
        content: Text(
          '确定删除「${item.name}」及其账单？'
          '其它设备若还有未同步的记账，同步后可能恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: PigTokens.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final deleted = await notifier.delete(item.id);
    if (!deleted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要保留一个账本')),
      );
    }
  }

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    required String initial,
    int? excludeId,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _LedgerNameDialog(
        title: title,
        initial: initial,
        excludeId: excludeId,
      ),
    );
  }
}

class _LedgerNameDialog extends ConsumerStatefulWidget {
  const _LedgerNameDialog({
    required this.title,
    required this.initial,
    this.excludeId,
  });

  final String title;
  final String initial;
  final int? excludeId;

  @override
  ConsumerState<_LedgerNameDialog> createState() => _LedgerNameDialogState();
}

class _LedgerNameDialogState extends ConsumerState<_LedgerNameDialog> {
  late final TextEditingController _controller;
  bool _taken = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _recheck(String raw) async {
    final taken = await ref.read(ledgerRepositoryProvider).nameTaken(
          raw,
          excludeId: widget.excludeId,
        );
    if (mounted) setState(() => _taken = taken);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || _taken) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '请输入账本名称'),
            onChanged: _recheck,
            onSubmitted: (_) => _submit(),
          ),
          if (_taken) ...[
            const SizedBox(height: 8),
            const Text(
              '已存在同名账本',
              style: TextStyle(color: PigTokens.danger, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _taken ? null : _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
