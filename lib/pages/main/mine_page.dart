import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../ai/ai_config.dart';
import '../../providers/ai_providers.dart';
import '../../providers/automation_providers.dart';
import '../../providers/database_provider.dart';
import '../../services/sync/cloud_sync_actions.dart';
import '../../services/sync/cloud_sync_config.dart';
import '../../services/sync/cloud_sync_providers.dart';
import '../../styles/tokens.dart';
import '../ai/ai_settings_page.dart';
import '../category/category_manage_page.dart';
import '../settings/about_page.dart';
import '../settings/cloud_sync_page.dart' show CloudSyncPage;
import '../settings/data_manage_page.dart';
import '../settings/ios_screenshot_guide_page.dart';
import '../tag/tag_manage_page.dart';

/// 「我的」设置入口页。
///
/// 账本管理不在此页（见开发文档 §4.1.1）。
class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoTags = ref.watch(autoGenerateTagsProvider).valueOrNull ?? true;
    final screenshot =
        ref.watch(screenshotAutoBillingProvider).valueOrNull ?? false;
    final aiAssistant =
        ref.watch(aiAssistantEnabledProvider).valueOrNull ?? true;
    final aiCfg = ref.watch(aiConfigProvider).valueOrNull;
    final cloudCfg = ref.watch(cloudSyncConfigProvider).valueOrNull;
    final aiSubtitle = () {
      if (aiCfg == null) return '默认智谱，支持 OpenAI 兼容';
      final name =
          aiCfg.kind == AiProviderKind.zhipu ? '智谱' : 'OpenAI 兼容';
      return aiCfg.isConfigured ? '$name · 已配置' : '$name · 未配置 Key';
    }();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        PigTokens.spaceLg,
        PigTokens.spaceMd,
        PigTokens.spaceLg,
        PigTokens.spaceXl,
      ),
      children: [
        _SectionCard(
          children: [
            _MineTile(
              icon: Icons.psychology_outlined,
              title: 'AI 模型配置',
              subtitle: aiSubtitle,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiSettingsPage(),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: PigTokens.spaceMd),
        _SectionCard(
          children: [
            _MineTile(
              icon: Icons.cloud_outlined,
              title: '云服务',
              subtitle: cloudCfg?.mineSubtitle ?? '默认仅本机',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CloudSyncPage(),
                  ),
                );
              },
            ),
            if (cloudCfg != null && cloudCfg.isReadyForSync) ...[
              const _SectionDivider(),
              const _CloudQuickSyncStrip(),
            ],
            const _SectionDivider(),
            _MineTile(
              icon: Icons.import_export,
              title: '数据管理',
              subtitle: '本地 CSV 文件导入导出',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DataManagePage(),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: PigTokens.spaceMd),
        _SectionCard(
          children: [
            _MineTile(
              icon: Icons.category_outlined,
              title: '分类管理',
              subtitle: '增删改排序 · CSV 导入导出',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CategoryManagePage(),
                  ),
                );
              },
            ),
            const _SectionDivider(),
            _MineTile(
              icon: Icons.local_offer_outlined,
              title: '标签管理',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TagManagePage(),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: PigTokens.spaceMd),
        _SectionCard(
          children: [
            SwitchListTile(
              secondary: const _MineIcon(Icons.smart_toy_outlined),
              title: const Text('AI 智能助手'),
              subtitle: Text(
                aiAssistant ? '报表页显示 AI 入口' : '已关闭：报表页隐藏 AI 入口',
              ),
              activeThumbColor: PigTokens.primary,
              value: aiAssistant,
              onChanged: (v) {
                ref.read(settingsRepositoryProvider).setAiAssistantEnabled(v);
              },
            ),
            const _SectionDivider(),
            SwitchListTile(
              secondary: const _MineIcon(Icons.screenshot_monitor_outlined),
              title: const Text('截图自动记账'),
              subtitle: Text(
                screenshot
                    ? (Platform.isIOS
                        ? '已开启：请配合快捷指令自动识别入账'
                        : '已开启：监听系统截图并自动识别入账')
                    : (Platform.isIOS
                        ? '开启后查看快捷指令引导'
                        : '开启后监听相册截图（需媒体与通知权限）'),
              ),
              activeThumbColor: PigTokens.primary,
              value: screenshot,
              onChanged: (v) async {
                final settings = ref.read(settingsRepositoryProvider);
                if (v) {
                  if (Platform.isAndroid) {
                    try {
                      await ref.read(screenshotMonitorServiceProvider).start();
                    } catch (e) {
                      if (!context.mounted) return;
                      final msg = '$e';
                      final forever = msg.contains('系统设置');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg.replaceFirst('Bad state: ', '')),
                          action: forever
                              ? SnackBarAction(
                                  label: '去设置',
                                  onPressed: openAppSettings,
                                )
                              : null,
                        ),
                      );
                      return;
                    }
                  }
                  await settings.setScreenshotAutoBilling(true);
                  if (Platform.isIOS && context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const IosScreenshotGuidePage(),
                      ),
                    );
                  }
                } else {
                  if (Platform.isAndroid) {
                    await ref.read(screenshotMonitorServiceProvider).stop();
                  }
                  await settings.setScreenshotAutoBilling(false);
                }
              },
            ),
            if (Platform.isIOS) ...[
              const _SectionDivider(),
              _MineTile(
                icon: Icons.tips_and_updates_outlined,
                title: 'iOS 快捷指令引导',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const IosScreenshotGuidePage(),
                    ),
                  );
                },
              ),
            ],
            const _SectionDivider(),
            SwitchListTile(
              secondary: const _MineIcon(Icons.new_label_outlined),
              title: const Text('自动生成标签'),
              subtitle: const Text('智能记账时允许创建新标签'),
              activeThumbColor: PigTokens.primary,
              value: autoTags,
              onChanged: (v) {
                ref.read(settingsRepositoryProvider).setAutoGenerateTags(v);
              },
            ),
          ],
        ),
        const SizedBox(height: PigTokens.spaceMd),
        _SectionCard(
          children: [
            _MineTile(
              icon: Icons.info_outline,
              title: '关于小猪记账',
              subtitle: '版本与产品说明',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AboutPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// 已测通时的快捷上传 / 下载。
class _CloudQuickSyncStrip extends ConsumerStatefulWidget {
  const _CloudQuickSyncStrip();

  @override
  ConsumerState<_CloudQuickSyncStrip> createState() =>
      _CloudQuickSyncStripState();
}

class _CloudQuickSyncStripState extends ConsumerState<_CloudQuickSyncStrip> {
  bool _busy = false;

  Future<void> _upload(CloudSyncConfig cfg) async {
    setState(() => _busy = true);
    try {
      final url = await uploadCloudLedgerSnapshot(ref: ref, config: cfg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传成功：$url')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(CloudSyncConfig cfg) async {
    if (!await confirmCloudDownload(context)) return;
    setState(() => _busy = true);
    try {
      final n = await downloadAndImportCloudSnapshot(ref: ref, config: cfg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已从云端导入 $n 笔')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(cloudSyncConfigProvider).valueOrNull;
    if (cfg == null || !cfg.isReadyForSync) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PigTokens.spaceLg,
        PigTokens.spaceSm,
        PigTokens.spaceLg,
        PigTokens.spaceMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _download(cfg),
              child: const Text('下载并导入'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => _upload(cfg),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('上传当前账本'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PigTokens.surface,
      borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: 56,
      endIndent: PigTokens.spaceLg,
    );
  }
}

class _MineIcon extends StatelessWidget {
  const _MineIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: PigTokens.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: PigTokens.primary, size: 20),
    );
  }
}

class _MineTile extends StatelessWidget {
  const _MineTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PigTokens.spaceLg,
        vertical: PigTokens.spaceXs,
      ),
      leading: _MineIcon(icon),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12,
                color: PigTokens.textTertiary,
              ),
            ),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right, color: PigTokens.textTertiary),
      onTap: onTap,
    );
  }
}
