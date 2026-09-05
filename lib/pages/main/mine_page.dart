import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../providers/ai_providers.dart';
import '../../providers/automation_providers.dart';
import '../../providers/database_provider.dart';
import '../../services/sync/cloud_sync_providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/pig_toast.dart';
import '../ai/ai_settings_page.dart';
import '../category/category_manage_page.dart';
import '../settings/about_page.dart';
import '../settings/cloud_sync_page.dart' show CloudSyncPage;
import '../settings/data_manage_page.dart';
import '../settings/ios_screenshot_guide_page.dart';
import '../settings/screenshot_watch_dirs_page.dart';
import '../settings/sync_page.dart';
import '../settings/widget_management_page.dart';
import '../tag/tag_manage_page.dart';

/// 「我的」设置入口页。
///
/// 账本管理不在此页（仅顶栏账本列表；见 docs/framework.md）。
class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoTags = ref.watch(autoGenerateTagsProvider).valueOrNull ?? true;
    final screenshot =
        ref.watch(screenshotAutoBillingProvider).valueOrNull ?? false;
    final watchDirs =
        ref.watch(screenshotWatchDirectoriesProvider).valueOrNull ??
            const <String>[];
    final aiSubtitle =
        ref.watch(aiMineSubtitleProvider).valueOrNull ?? '服务商与能力绑定';
    final cloudCfg = ref.watch(cloudSyncConfigProvider).valueOrNull;

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
              title: 'AI 设置',
              subtitle: aiSubtitle,
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiSettingsPage(),
                  ),
                );
                ref.invalidate(aiMineSubtitleProvider);
                ref.invalidate(aiProvidersListProvider);
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
            const _SectionDivider(),
            _MineTile(
              icon: Icons.sync_outlined,
              title: '同步',
              subtitle: (cloudCfg?.isReadyForSync ?? false)
                  ? null
                  : '云服务不可用，请确认配置信息',
              enabled: cloudCfg?.isReadyForSync ?? false,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SyncPage(),
                  ),
                );
              },
            ),
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
              secondary: const _MineIcon(Icons.screenshot_monitor_outlined),
              title: const Text('截图自动记账'),
              activeThumbColor: PigTokens.primary,
              value: screenshot,
              onChanged: (v) async {
                final settings = ref.read(settingsRepositoryProvider);
                if (v) {
                  var openWatchDirsAfterDiscover = false;
                  if (Platform.isAndroid) {
                    try {
                      final monitor =
                          ref.read(screenshotMonitorServiceProvider);
                      await monitor.ensurePermissionOrThrow();
                      final configured = await settings
                          .hasScreenshotWatchDirectoriesSetting();
                      late final List<String> dirs;
                      if (!configured) {
                        dirs = await monitor.discoverDirectories();
                        await settings.setScreenshotWatchDirectories(dirs);
                        openWatchDirsAfterDiscover = true;
                      } else {
                        dirs = await settings.screenshotWatchDirectories();
                      }
                      if (dirs.isNotEmpty) {
                        await monitor.start(directories: dirs);
                      } else {
                        await monitor.stop();
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      final msg = '$e'.replaceFirst('Bad state: ', '');
                      if (msg.contains('系统设置')) {
                        await showActionHintDialog(
                          context,
                          message: msg,
                          onAction: openAppSettings,
                        );
                      } else {
                        PigToast.show(context, msg);
                      }
                      return;
                    }
                  }
                  await settings.setScreenshotAutoBilling(true);
                  if (!context.mounted) return;
                  if (Platform.isAndroid && openWatchDirsAfterDiscover) {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ScreenshotWatchDirsPage(),
                      ),
                    );
                  } else if (Platform.isIOS) {
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
            if (Platform.isAndroid && screenshot) ...[
              const _SectionDivider(),
              _MineTile(
                icon: Icons.folder_outlined,
                title: '自动记账监听目录',
                subtitle: watchDirs.isEmpty
                    ? '不可用，未配置监听目录'
                    : '${watchDirs.length} 个目录',
                subtitleColor:
                    watchDirs.isEmpty ? PigTokens.danger : null,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ScreenshotWatchDirsPage(),
                    ),
                  );
                },
              ),
            ],
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
              icon: Icons.widgets_outlined,
              title: '桌面小组件',
              subtitle: '收支速览预览与添加说明',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WidgetManagementPage(),
                  ),
                );
              },
            ),
            const _SectionDivider(),
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
    this.subtitleColor,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      minVerticalPadding: 0,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PigTokens.spaceLg,
      ),
      leading: _MineIcon(icon),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                height: 1.15,
                color: subtitleColor ?? PigTokens.textTertiary,
              ),
            ),
      trailing: const Icon(Icons.chevron_right, color: PigTokens.textTertiary),
      onTap: enabled ? onTap : null,
    );
  }
}
