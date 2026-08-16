import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    await notifier.create(name);
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
    );
    if (name == null) return;
    await notifier.rename(item.id, name);
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
        content: Text('确定删除「${item.name}」及其账单？此操作不可恢复。'),
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
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入账本名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
