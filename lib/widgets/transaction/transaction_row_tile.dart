import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/transaction_repository.dart';
import '../../pages/transaction/category_detail_page.dart';
import '../../pages/transaction/record_editor_sheet.dart';
import '../../pages/transaction/tag_detail_page.dart';
import '../../providers/database_provider.dart';
import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../../utils/tag_colors.dart';
import '../category_icon_view.dart';
import 'fading_tag_chip_strip.dart';

/// 统一账单行（ADR-029 / ADR-036）：分类圆标可点、全量标签横滑、时间|备注、金额居中。
class TransactionRowTile extends ConsumerWidget {
  const TransactionRowTile({
    super.key,
    required this.item,
    this.onTap,
    this.trailingExtra,
    this.selected = false,
    this.onToggleSelect,
    this.enableLongPressDelete = false,
  });

  final TransactionListItem item;
  final VoidCallback? onTap;
  final Widget? trailingExtra;
  final bool selected;
  final VoidCallback? onToggleSelect;
  /// 明细页：长按确认后删除（ADR-036 修订，原左滑删已退役）。
  final bool enableLongPressDelete;

  void _openCategoryDetail(BuildContext context, WidgetRef ref) {
    final month = ref.read(detailsMonthProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryDetailPage(
          categoryId: item.categoryId,
          categoryName: item.categoryName ?? '未分类',
          initialMonth: month,
          includeChildren: item.categoryId != null && item.categoryParentId == null,
        ),
      ),
    );
  }

  void _openTagDetail(
    BuildContext context,
    WidgetRef ref,
    ListTagLabel tag,
  ) {
    final month = ref.read(detailsMonthProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TagDetailPage(
          tagId: tag.id,
          tagName: tag.name,
          initialMonth: month,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除账单'),
            content: const Text('确定删除这条账单？删除后不可恢复。'),
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
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    await ref.read(transactionRepositoryProvider).delete(item.tx.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = item.tx;
    final isExpense = tx.type == 'expense';
    final amountText =
        '${isExpense ? '-' : '+'}${formatMoneyCompact(tx.amount)}';
    final note = tx.note?.trim();
    final hasNote = note != null && note.isNotEmpty;
    final timeText = DateFormat('HH:mm').format(tx.happenedAt);
    final tags = item.tags;
    final fadeColor =
        selected ? PigTokens.primarySoft : PigTokens.surface;

    return Material(
      color: selected ? PigTokens.primarySoft : Colors.transparent,
      child: InkWell(
        onTap: onToggleSelect ??
            onTap ??
            () => showRecordEditorSheet(context, transactionId: tx.id),
        onLongPress: enableLongPressDelete
            ? () => _confirmDelete(context, ref)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PigTokens.spaceLg,
            vertical: 8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (onToggleSelect != null)
                Padding(
                  padding: const EdgeInsets.only(right: PigTokens.spaceSm),
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelect!(),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
              else
                GestureDetector(
                  onTap: () => _openCategoryDetail(context, ref),
                  behavior: HitTestBehavior.opaque,
                  child: CategoryIconCircle(
                    name: item.categoryName ?? '未分类',
                    icon: item.categoryIcon,
                    iconType: item.categoryIconType,
                    customIconPath: item.categoryCustomIconPath,
                    diameter: 32,
                    iconSize: 16,
                  ),
                ),
              const SizedBox(width: PigTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.categoryName ?? '未分类',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: PigTokens.textPrimary,
                            ),
                          ),
                        ),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: FadingTagChipStrip(
                              fadeColor: fadeColor,
                              children: [
                                for (final tag in tags)
                                  _ListTagChip(
                                    name: tag.name,
                                    color: tag.color,
                                    onTap: () => _openTagDetail(
                                      context,
                                      ref,
                                      tag,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasNote ? '$timeText | $note' : timeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: PigTokens.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PigTokens.spaceSm),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amountText,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isExpense ? PigTokens.expense : PigTokens.income,
                    ),
                  ),
                  ?trailingExtra,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListTagChip extends StatelessWidget {
  const _ListTagChip({
    required this.name,
    required this.color,
    this.onTap,
  });

  final String name;
  final String color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tagColor = TagColors.parse(color);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: tagColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: tagColor.withValues(alpha: 0.35)),
        ),
        alignment: Alignment.center,
        child: Text(
          name,
          style: TextStyle(
            fontSize: 10,
            color: tagColor,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

String formatDayTitle(DateTime day) {
  final weekday = DateFormat('EEE', 'zh_CN').format(day);
  return '${DateFormat('M月d日').format(day)} $weekday';
}
