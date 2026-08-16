import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../styles/tokens.dart';

/// 「关于」页：展示版本与产品说明。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '…';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: const Text('关于小猪记账')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: PigTokens.surface,
              borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: PigTokens.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.savings_outlined,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '小猪记账',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '版本 $_version',
                  style: const TextStyle(
                    fontSize: 13,
                    color: PigTokens.textTertiary,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '本机优先的个人记账工具：手动记账、报表分析、'
                  '可选 AI 智能记账与云同步。数据默认仅保存在本机。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: PigTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PigTokens.surface,
              borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            ),
            child: const Text(
              '不做：多币种、账户体系、预算、暗色模式、多语言。\n'
              'AI Key 与云凭证仅存本机，不会上传到小猪记账服务器。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: PigTokens.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
