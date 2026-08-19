import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/statistics_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../../utils/report_period.dart';
import '../../utils/tag_colors.dart';
import '../category_icon_view.dart';
import '../transaction/fading_tag_chip_strip.dart';

/// 单笔排行行（卡内 / 全页共用布局，ADR-033 / ADR-036）。
class ReportRankTile extends StatelessWidget {
  const ReportRankTile({
    super.key,
    required this.categoryName,
    required this.amount,
    required this.happenedAt,
    required this.moneyType,
    this.categoryIcon,
    this.categoryIconType = 'material',
    this.categoryCustomIconPath,
    this.tags = const [],
    this.note,
    this.onTap,
    this.selected = false,
    this.showCheckbox = false,
    this.onToggleSelect,
    this.cardStyle = false,
  });

  factory ReportRankTile.fromRanked({
    required RankedTransaction item,
    required ReportMoneyType moneyType,
    VoidCallback? onTap,
    bool cardStyle = false,
  }) {
    return ReportRankTile(
      categoryName: item.categoryName ?? '未分类',
      categoryIcon: item.categoryIcon,
      categoryIconType: item.categoryIconType,
      categoryCustomIconPath: item.categoryCustomIconPath,
      amount: item.amount,
      happenedAt: item.happenedAt,
      moneyType: moneyType,
      tags: item.tags,
      note: item.note,
      onTap: onTap,
      cardStyle: cardStyle,
    );
  }

  factory ReportRankTile.fromListItem({
    required TransactionListItem item,
    required ReportMoneyType moneyType,
    VoidCallback? onTap,
    bool selected = false,
    bool showCheckbox = false,
    VoidCallback? onToggleSelect,
    bool cardStyle = true,
  }) {
    return ReportRankTile(
      categoryName: item.categoryName ?? '未分类',
      categoryIcon: item.categoryIcon,
      categoryIconType: item.categoryIconType,
      categoryCustomIconPath: item.categoryCustomIconPath,
      amount: item.tx.amount,
      happenedAt: item.tx.happenedAt,
      moneyType: moneyType,
      tags: [
        for (final t in item.tags)
          RankTagLabel(name: t.name, color: t.color),
      ],
      note: item.tx.note,
      onTap: onTap,
      selected: selected,
      showCheckbox: showCheckbox,
      onToggleSelect: onToggleSelect,
      cardStyle: cardStyle,
    );
  }

  final String categoryName;
  final String? categoryIcon;
  final String categoryIconType;
  final String? categoryCustomIconPath;
  final double amount;
  final DateTime happenedAt;
  final ReportMoneyType moneyType;
  final List<RankTagLabel> tags;
  final String? note;
  final VoidCallback? onTap;
  final bool selected;
  final bool showCheckbox;
  final VoidCallback? onToggleSelect;
  final bool cardStyle;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('yyyy/M/d HH:mm').format(happenedAt);
    final noteText = note?.trim();
    final asExpense = moneyType == ReportMoneyType.expense;
    final fadeColor = cardStyle
        ? PigTokens.surface
        : PigTokens.scaffoldBackground;

    final row = InkWell(
      onTap: showCheckbox ? onToggleSelect : onTap,
      borderRadius: cardStyle ? BorderRadius.circular(12) : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: cardStyle ? PigTokens.spaceMd : 0,
          vertical: PigTokens.spaceSm + 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showCheckbox) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Icon(
                  selected
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 22,
                  color: selected
                      ? PigTokens.primary
                      : PigTokens.textTertiary,
                ),
              ),
            ],
            CategoryIconCircle(
              name: categoryName,
              icon: categoryIcon,
              iconType: categoryIconType,
              customIconPath: categoryCustomIconPath,
              diameter: 40,
              iconSize: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          categoryName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: FadingTagChipStrip(
                            fadeColor: fadeColor,
                            height: 20,
                            children: [
                              for (final tag in tags)
                                _TagChip(
                                  name: tag.name,
                                  colorHex: tag.color,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PigTokens.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatSignedMoney(amount, asExpense: asExpense),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (noteText != null && noteText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      noteText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        color: PigTokens.textTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    if (!cardStyle) return row;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: PigTokens.spaceMd,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: PigTokens.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: row,
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.name, this.colorHex});

  final String name;
  final String? colorHex;

  @override
  Widget build(BuildContext context) {
    final color = TagColors.parse(colorHex, fallback: PigTokens.textTertiary);
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        color: color.withValues(alpha: 0.08),
      ),
      child: Text(
        name,
        maxLines: 1,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
          height: 1.1,
        ),
      ),
    );
  }
}
