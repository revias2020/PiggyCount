import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../providers/ai_providers.dart';
import '../../providers/automation_providers.dart';
import '../../providers/database_provider.dart';
import '../../styles/tokens.dart';

/// 截图自动记账 · 监听目录管理（ADR-070，仅 Android）。
class ScreenshotWatchDirsPage extends ConsumerStatefulWidget {
  const ScreenshotWatchDirsPage({super.key});

  @override
  ConsumerState<ScreenshotWatchDirsPage> createState() =>
      _ScreenshotWatchDirsPageState();
}

class _ScreenshotWatchDirsPageState
    extends ConsumerState<ScreenshotWatchDirsPage> {
  var _busy = false;

  Future<void> _persistAndApply(List<String> dirs) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setScreenshotWatchDirectories(dirs);
    final enabled = await settings.screenshotAutoBilling();
    if (!enabled) return;
    final monitor = ref.read(screenshotMonitorServiceProvider);
    try {
      if (dirs.isEmpty) {
        await monitor.stop();
      } else if (monitor.isListening) {
        await monitor.applyDirectories(dirs);
      } else {
        await monitor.start(directories: dirs);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _addDirectory() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.getDirectoryPath(
        dialogTitle: '选择监听目录',
      );
      if (picked == null || !mounted) return;
      final normalized = await ref
          .read(screenshotMonitorServiceProvider)
          .normalizeDirectory(picked);
      if (normalized == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法解析为可读路径，请选择内部存储下的相册文件夹'),
          ),
        );
        return;
      }
      final current =
          await ref.read(settingsRepositoryProvider).screenshotWatchDirectories();
      if (current.any((d) => d.toLowerCase() == normalized.toLowerCase())) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该目录已在列表中')),
        );
        return;
      }
      await _persistAndApply([...current, normalized]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeDirectory(String dir) async {
    final current =
        await ref.read(settingsRepositoryProvider).screenshotWatchDirectories();
    await _persistAndApply(
      current.where((d) => d.toLowerCase() != dir.toLowerCase()).toList(),
    );
  }

  Future<void> _rescan() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新扫描？'),
        content: const Text(
          '将用相册中的截图目录整表替换当前列表，你手动添加或删除的目录都会丢失。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('替换'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final dirs =
          await ref.read(screenshotMonitorServiceProvider).discoverDirectories();
      await _persistAndApply(dirs);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dirs.isEmpty ? '未发现截图目录' : '已更新为 ${dirs.length} 个目录',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirsAsync = ref.watch(screenshotWatchDirectoriesProvider);
    final dirs = dirsAsync.valueOrNull ?? const <String>[];

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: const Text('自动记账监听目录'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _rescan,
            child: const Text('重新扫描'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _addDirectory,
        backgroundColor: PigTokens.primary,
        foregroundColor: PigTokens.textOnPrimary,
        child: const Icon(Icons.create_new_folder_outlined),
      ),
      body: dirsAsync.isLoading && dirs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                PigTokens.spaceLg,
                PigTokens.spaceMd,
                PigTokens.spaceLg,
                88,
              ),
              children: [
                const Text(
                  '仅监听下列目录中、且文件名/路径含截图关键词的新图。'
                  '删除只移出本列表，不会删相册文件。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: PigTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: PigTokens.spaceMd),
                if (dirs.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(PigTokens.spaceLg),
                    decoration: BoxDecoration(
                      color: PigTokens.surface,
                      borderRadius: BorderRadius.circular(PigTokens.radiusCard),
                    ),
                    child: const Text(
                      '暂无监听目录。可点右下角添加，或点右上角重新扫描。',
                      style: TextStyle(
                        color: PigTokens.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  )
                else
                  Material(
                    color: PigTokens.surface,
                    borderRadius: BorderRadius.circular(PigTokens.radiusCard),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < dirs.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            title: Text(
                              dirs[i],
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: '移出列表',
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: PigTokens.danger,
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _removeDirectory(dirs[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_busy) ...[
                  const SizedBox(height: PigTokens.spaceLg),
                  const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
