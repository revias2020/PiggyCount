import 'package:flutter/material.dart';

import '../styles/tokens.dart';

/// 通用空态：图标 + 主文案 + 可选次要说明。
///
/// 明细「暂无数据」等场景复用，避免各页各自拼一套灰色占位。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.detail,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final String? detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PigTokens.spaceXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: PigTokens.textTertiary),
            const SizedBox(height: PigTokens.spaceMd),
            Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                color: PigTokens.textSecondary,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: PigTokens.spaceSm),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: PigTokens.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
