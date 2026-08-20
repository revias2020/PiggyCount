import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_category_match.dart';
import '../../ai/bill_info.dart';
import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import 'bill_display.dart';

/// 待确认账单卡片：用户确认后才落库。
class BillConfirmCard extends ConsumerWidget {
  const BillConfirmCard({
    super.key,
    required this.bill,
    required this.onConfirm,
    required this.onDiscard,
    this.busy = false,
  });

  final BillInfo bill;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpense = billIsExpense(bill);
    final time = formatBillTime(bill);
    final catsAsync = isExpense
        ? ref.watch(expenseCategoriesProvider)
        : ref.watch(incomeCategoriesProvider);
    final categoryName = catsAsync.maybeWhen(
      data: (cats) => AiCategoryMatch.displayName(bill.category, cats),
      orElse: () => (bill.category ?? '').trim().isNotEmpty
          ? (bill.category ?? '').trim()
          : '未分类',
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PigTokens.surface,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isExpense
                      ? PigTokens.primarySoft
                      : PigTokens.income.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isExpense ? '支出' : '收入',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isExpense ? PigTokens.primary : PigTokens.income,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                formatSignedMoney(bill.amount ?? 0, asExpense: isExpense),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            categoryName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (bill.note != null && bill.note!.isNotEmpty)
            Text(
              bill.note!,
              style: const TextStyle(
                fontSize: 13,
                color: PigTokens.textSecondary,
              ),
            ),
          if (time.isNotEmpty)
            Text(
              time,
              style: const TextStyle(
                fontSize: 12,
                color: PigTokens.textTertiary,
              ),
            ),
          if (bill.tags != null && bill.tags!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final t in bill.tags!)
                  Chip(
                    label: Text(
                      formatBillTagLabel(t),
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(onPressed: busy ? null : onDiscard, child: const Text('丢弃')),
              const Spacer(),
              FilledButton(
                onPressed: busy ? null : onConfirm,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('确认记账'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
