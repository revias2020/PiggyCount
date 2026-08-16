import 'package:flutter/material.dart';

import '../styles/tokens.dart';

/// 页面级加载占位（明细 / 报表等高频页共用）。
class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PigTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            if (message != null) ...[
              const SizedBox(height: PigTokens.spaceMd),
              Text(
                message!,
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

/// 页面级错误态：简要说明 + 可选重试。
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PigTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: PigTokens.textTertiary,
            ),
            const SizedBox(height: PigTokens.spaceMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: PigTokens.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: PigTokens.spaceLg),
              TextButton(
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
