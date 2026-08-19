import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/bill_info.dart';
import '../../data/app_database.dart';
import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../category_icon_view.dart';
import 'bill_display.dart';

/// 识别确认弹层用的紧凑复选行（只读展示；ADR-029）。
class BillSelectTile extends ConsumerWidget {
  const BillSelectTile({
    super.key,
    required this.bill,
    required this.selected,
    required this.onChanged,
  });

  final BillInfo bill;
  final bool selected;
  final ValueChanged<bool?>? onChanged;

  Category? _matchDisplay(List<Category> cats) {
    final needle = (bill.category ?? '').trim();
    if (needle.isEmpty || cats.isEmpty) return null;
    final exact = cats.where((c) => c.name == needle);
    if (exact.isNotEmpty) return exact.first;
    final contains = cats.where(
      (c) => c.name.contains(needle) || needle.contains(c.name),
    );
    if (contains.isNotEmpty) return contains.first;
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpense = billIsExpense(bill);
    final catsAsync = isExpense
        ? ref.watch(expenseCategoriesProvider)
        : ref.watch(incomeCategoriesProvider);
    final matched = catsAsync.maybeWhen(
      data: _matchDisplay,
      orElse: () => null,
    );
    final categoryName = matched?.name ??
        ((bill.category ?? '').trim().isNotEmpty
            ? (bill.category ?? '').trim()
            : '未分类');
    final note = (bill.note ?? '').trim();
    final time = formatBillTime(bill);
    final amountColor = isExpense ? PigTokens.expense : PigTokens.income;

    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PigTokens.spaceSm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: selected,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: PigTokens.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CategoryIconCircle(
                        name: categoryName,
                        icon: matched?.icon,
                        iconType: matched?.iconType ?? 'material',
                        customIconPath: matched?.customIconPath,
                        diameter: 28,
                        iconSize: 14,
                      ),
                      const SizedBox(width: PigTokens.spaceSm),
                      Expanded(
                        child: Text(
                          categoryName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: PigTokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: PigTokens.spaceSm),
                      Text(
                        formatSignedMoney(bill.amount ?? 0, asExpense: isExpense),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: amountColor,
                        ),
                      ),
                    ],
                  ),
                  if (note.isNotEmpty || time.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                              fontSize: 12,
                              color: PigTokens.textTertiary,
                            ),
                          ),
                        ),
                        if (time.isNotEmpty)
                          Text(
                            time,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12,
                              color: PigTokens.textTertiary,
                            ),
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
