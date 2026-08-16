import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/statistics_repository.dart';
import '../../styles/tokens.dart';
import '../../utils/category_icons.dart';
import '../../utils/money_format.dart';
import '../../utils/report_period.dart';
import 'report_section_card.dart';

/// 单笔金额排行；次要信息展示备注（无备注则省略）。
class ReportRankList extends StatelessWidget {
  const ReportRankList({
    super.key,
    required this.title,
    required this.items,
    required this.moneyType,
    this.onTap,
  });

  final String title;
  final List<RankedTransaction> items;
  final ReportMoneyType moneyType;
  final ValueChanged<RankedTransaction>? onTap;

  @override
  Widget build(BuildContext context) {
    return ReportSectionCard(
      title: title,
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '暂无排行数据',
                  style: TextStyle(color: PigTokens.textTertiary),
                ),
              ),
            )
          : Column(
              children: [
                for (final item in items)
                  InkWell(
                    onTap: onTap == null ? null : () => onTap!(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: PigTokens.spaceSm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: PigTokens.primarySoft,
                              borderRadius: BorderRadius.circular(
                                PigTokens.radiusCard,
                              ),
                            ),
                            child: Icon(
                              categoryIconData(item.categoryIcon),
                              color: PigTokens.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.categoryName ?? '未分类',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _subtitle(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: PigTokens.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatSignedMoney(
                              item.amount,
                              asExpense:
                                  moneyType == ReportMoneyType.expense,
                            ),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _subtitle(RankedTransaction item) {
    final time = DateFormat('M月d日 HH:mm').format(item.happenedAt);
    final note = item.note?.trim();
    if (note == null || note.isEmpty) return time;
    return '$note · $time';
  }
}
