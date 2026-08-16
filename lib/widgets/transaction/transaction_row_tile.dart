import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/transaction_repository.dart';
import '../../styles/tokens.dart';
import '../../pages/transaction/record_editor_sheet.dart';
import '../category_icon_view.dart';

/// 账单行：分类图标 + 名称/备注 + 金额 + 标签芯片（对齐参考图账户位）。
class TransactionRowTile extends StatelessWidget {
  const TransactionRowTile({
    super.key,
    required this.item,
    this.onTap,
    this.trailingExtra,
    this.selected = false,
    this.onToggleSelect,
  });

  final TransactionListItem item;
  final VoidCallback? onTap;
  final Widget? trailingExtra;
  final bool selected;
  final VoidCallback? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final tx = item.tx;
    final isExpense = tx.type == 'expense';
    final amountText =
        '${isExpense ? '-' : '+'}${_fmt(tx.amount)}';
    final note = tx.note?.trim();

    return ListTile(
      onTap: onToggleSelect ??
          onTap ??
          () => showRecordEditorSheet(context, transactionId: tx.id),
      selected: selected,
      selectedTileColor: PigTokens.primarySoft,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PigTokens.spaceLg,
        vertical: PigTokens.spaceXs,
      ),
      leading: onToggleSelect != null
          ? Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelect!(),
            )
          : CircleAvatar(
              backgroundColor: PigTokens.primarySoft,
              child: CategoryIconView(
                name: item.categoryName ?? '未分类',
                icon: item.categoryIcon,
                iconType: item.categoryIconType,
                customIconPath: item.categoryCustomIconPath,
                color: PigTokens.primary,
                size: 20,
              ),
            ),
      title: Text(
        item.categoryName ?? '未分类',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: note != null && note.isNotEmpty
          ? Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: PigTokens.textTertiary,
              ),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            amountText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isExpense ? PigTokens.expense : PigTokens.income,
            ),
          ),
          if (item.tagNames.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              item.tagNames.first,
              style: const TextStyle(
                fontSize: 11,
                color: PigTokens.primary,
              ),
            ),
          ],
          ?trailingExtra,
        ],
      ),
    );
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
    final parts = s.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }
}

String formatDayTitle(DateTime day) {
  final weekday = DateFormat('EEE', 'zh_CN').format(day);
  return '${DateFormat('M月d日').format(day)} $weekday';
}
