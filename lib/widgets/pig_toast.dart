import 'dart:async';

import 'package:flutter/material.dart';

import '../styles/tokens.dart';

/// 应用内轻提示（ADR-071）：root Overlay 胶囊，盖过模态底栏。
abstract final class PigToast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  /// 展示轻提示。会立刻解析 [context] 的 root Overlay（可在 `Navigator.pop` 前调用后立刻 pop）。
  static void show(BuildContext context, String message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null || message.isEmpty) return;
    showOn(overlay, message);
  }

  /// 已持有 Overlay 时使用（例如关层后 context 可能已卸载）。
  static void showOn(OverlayState overlay, String message) {
    if (message.isEmpty) return;
    dismiss();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final maxW = MediaQuery.sizeOf(ctx).width * 0.8;
        return IgnorePointer(
          ignoring: false,
          child: Align(
            alignment: const Alignment(0, 0.35),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: dismiss,
                  behavior: HitTestBehavior.opaque,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: PigTokens.surface,
                      borderRadius: BorderRadius.circular(PigTokens.radiusPill),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PigTokens.spaceLg,
                        vertical: PigTokens.spaceMd,
                      ),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: PigTokens.textPrimary,
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(const Duration(seconds: 2), dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

/// 需要「去设置」等操作时的引导 Dialog（ADR-071），不用 SnackBar Action。
Future<void> showActionHintDialog(
  BuildContext context, {
  required String message,
  String title = '提示',
  String actionLabel = '去设置',
  required VoidCallback onAction,
  String dismissLabel = '知道了',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(dismissLabel),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            onAction();
          },
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}
