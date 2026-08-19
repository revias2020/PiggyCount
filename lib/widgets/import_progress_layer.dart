import 'dart:async';

import 'package:flutter/material.dart';

import '../styles/tokens.dart';

/// 数据导入 / 分类导入写入阶段的全屏遮罩。不可取消。
Future<T> showImportProgressLayer<T>({
  required BuildContext context,
  required String title,
  required Future<T> Function(void Function(int current, int total) report)
      task,
}) async {
  final progress = ValueNotifier<(int, int)>((0, 1));
  final shown = Completer<void>();
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) {
      if (!shown.isCompleted) shown.complete();
      return PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, value, _) {
              final current = value.$1;
              final total = value.$2 <= 0 ? 1 : value.$2;
              final ratio = (current / total).clamp(0.0, 1.0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: PigTokens.spaceLg),
                  LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    color: PigTokens.primary,
                    backgroundColor: PigTokens.primarySoft,
                  ),
                  const SizedBox(height: PigTokens.spaceMd),
                  Text(
                    '$current / $total',
                    style: const TextStyle(
                      fontSize: 13,
                      color: PigTokens.textSecondary,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
  await shown.future;
  try {
    return await task((current, total) {
      progress.value = (current, total);
    });
  } finally {
    if (navigator.canPop()) navigator.pop();
    progress.dispose();
  }
}
