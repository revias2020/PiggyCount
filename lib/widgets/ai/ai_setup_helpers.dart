import 'package:flutter/material.dart';

import '../../pages/ai/ai_settings_page.dart';
import '../../styles/tokens.dart';

/// 打开 AI 设置页（能力未就绪 / 错误引导共用）。
void openAiSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AiSettingsPage()),
  );
}

bool looksLikeAiSetupError(String message) {
  return message.contains('AI 设置') ||
      message.contains('API Key') ||
      message.contains('服务商');
}

/// 错误文案旁的「去设置」按钮；非配置类错误返回 null。
///
/// 前台确认弹层（语音/图片）能力未就绪时只用弹层内引导（ADR-057），
/// 不再叠 SnackBar，避免跳到 AI 设置后重复通知。
Widget? aiSetupTextButton(BuildContext context, String? error) {
  if (error == null || !looksLikeAiSetupError(error)) return null;
  return TextButton(
    onPressed: () => openAiSettings(context),
    child: const Text('去设置'),
  );
}

/// 统一卡片容器（AI 设置相关页）。
///
/// 使用 [Material] 而非带色 [DecoratedBox]，避免内部 [ListTile] 水波纹被遮挡。
Widget aiSectionCard({required Widget child}) {
  return Material(
    color: PigTokens.surface,
    borderRadius: BorderRadius.circular(PigTokens.radiusCard),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(PigTokens.spaceLg - 2),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
