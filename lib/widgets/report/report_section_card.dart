import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 报表区块白底卡片外壳（趋势 / 构成 / 对比 / 排行共用）。
class ReportSectionCard extends StatelessWidget {
  const ReportSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        PigTokens.spaceMd,
        PigTokens.spaceMd,
        PigTokens.spaceMd,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(
        PigTokens.spaceLg,
        PigTokens.spaceMd,
        PigTokens.spaceLg,
        PigTokens.spaceLg,
      ),
      decoration: BoxDecoration(
        color: PigTokens.surface,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: PigTokens.textPrimary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: PigTokens.spaceMd),
          child,
        ],
      ),
    );
  }
}
