import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/database_provider.dart';
import '../../providers/ledger_session_provider.dart';
import '../../providers/pending_review_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../workspace_sheet.dart';

/// 核对信封底部弹层（ADR-050）。
Future<void> showPendingReviewSheet(BuildContext context) {
  return showWorkspaceSheet<void>(
    context,
    fixedHeight: true,
    heightFraction: 0.55,
    builder: (ctx) => const _PendingReviewSheetBody(),
  );
}

class _PendingReviewSheetBody extends ConsumerStatefulWidget {
  const _PendingReviewSheetBody();

  @override
  ConsumerState<_PendingReviewSheetBody> createState() =>
      _PendingReviewSheetBodyState();
}

class _PendingReviewSheetBodyState
    extends ConsumerState<_PendingReviewSheetBody> {
  late Future<List<_SheetRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_SheetRow>> _load() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    if (ledgerId == null) return const [];
    final entries = ref.read(pendingReviewProvider).forLedger(ledgerId);
    final repo = ref.read(transactionRepositoryProvider);
    final out = <_SheetRow>[];
    for (final e in entries) {
      final tx = await repo.getBySyncId(e.syncId);
      if (tx == null) {
        await ref
            .read(pendingReviewProvider.notifier)
            .removeIfPresent(e.syncId);
        continue;
      }
      final isExpense = tx.type == 'expense';
      final note = tx.note?.trim();
      out.add(
        _SheetRow(
          syncId: e.syncId,
          title: isExpense ? '支出' : '收入',
          subtitle: DateFormat('M月d日 HH:mm').format(tx.happenedAt) +
              ((note != null && note.isNotEmpty) ? ' · $note' : ''),
          amountText:
              '${isExpense ? '-' : '+'}${formatMoneyCompact(tx.amount)}',
          isExpense: isExpense,
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final pending = ref.watch(pendingReviewProvider);
    final count = ledgerId == null
        ? 0
        : pending.forLedger(ledgerId).length;

    return WorkspaceSheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '待核对账单${count > 0 ? '（$count）' : ''}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: PigTokens.textPrimary,
                  ),
                ),
              ),
              if (count > 0)
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(pendingReviewProvider.notifier)
                        .markAllReadForLedger(ledgerId!);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('一键已读'),
                ),
            ],
          ),
          const SizedBox(height: PigTokens.spaceSm),
          Expanded(
            child: FutureBuilder<List<_SheetRow>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final rows = snap.data ?? const <_SheetRow>[];
                if (rows.isEmpty) {
                  return const Center(
                    child: Text(
                      '暂无待核对账单',
                      style: TextStyle(color: PigTokens.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row.title),
                      subtitle: Text(
                        row.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        row.amountText,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: row.isExpense
                              ? PigTokens.expense
                              : PigTokens.income,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        ref
                            .read(pendingReviewProvider.notifier)
                            .requestJump(row.syncId);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetRow {
  const _SheetRow({
    required this.syncId,
    required this.title,
    required this.subtitle,
    required this.amountText,
    required this.isExpense,
  });

  final String syncId;
  final String title;
  final String subtitle;
  final String amountText;
  final bool isExpense;
}
