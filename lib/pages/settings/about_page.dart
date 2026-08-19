import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../styles/tokens.dart';
import 'program_log_page.dart';
import 'usage_tutorial_page.dart';

/// 「关于」页：版本信息 + 使用教程入口。
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
          Material(
            color: PigTokens.surface,
            borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Column(
                children: [
                  // 正式品牌整图（重绘白猪）；圆裁贴近启动页。明细顶栏仍用 piggyCount。
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      color: PigTokens.primary,
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/brand/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.savings_outlined,
                        color: Colors.white,
                        size: 44,
                      ),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: PigTokens.surface,
            borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  title: const Text(
                    '使用教程',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: PigTokens.textTertiary,
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const UsageTutorialPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: const Text(
                    '程序日志',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '查看应用运行记录',
                    style: TextStyle(
                      fontSize: 12,
                      color: PigTokens.textTertiary,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: PigTokens.textTertiary,
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProgramLogPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
