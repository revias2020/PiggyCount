import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// iOS 截图自动记账无法像 Android 静默监听，需快捷指令引导。
class IosScreenshotGuidePage extends StatelessWidget {
  const IosScreenshotGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: const Text('iOS 截图记账引导')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PigTokens.surface,
              borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '为什么需要快捷指令？',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'iOS 不允许第三方 App 静默监听系统截图。'
                  '请用「快捷指令」在截图后打开小猪记账，再选择该截图识别入账。',
                  style: TextStyle(height: 1.45, color: PigTokens.textSecondary),
                ),
                SizedBox(height: 16),
                Text(
                  '推荐步骤',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  '1. 打开系统「快捷指令」App\n'
                  '2. 新建个人自动化：当「截屏」时\n'
                  '3. 添加操作「打开 App」→ 选择「小猪记账」\n'
                  '4. 回到本 App：「我的」→ 关闭「截图自动记账」旁可点「选择截图识别」\n'
                  '5. 选中刚才的支付截图，确认后入账\n\n'
                  '注意：系统截图不会被 App 删除，请自行清理相册。',
                  style: TextStyle(height: 1.5, color: PigTokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
