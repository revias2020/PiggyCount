import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/sync/cloud_sync_actions.dart';
import '../../services/sync/cloud_sync_providers.dart';
import '../../styles/tokens.dart';

/// 同步说明页：确认后拉云、预览、应用；自动同步仅占位。
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  bool _busy = false;

  Future<void> _sync() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await runWorkspaceSync(context: context, ref: ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(cloudSyncConfigProvider).valueOrNull;
    final ready = cfg != null && cfg.isReadyForSync;

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: const Text('同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '把这台设备上的全部账本、分类和标签与网盘上的工作区对齐。'
            '同一条两边都改过时，较晚的那版整条生效。\n'
            '点同步后会先确认是否拉云，再给你看将要新增、更新、删除的数量，确认后才写入。',
            style: TextStyle(fontSize: 13, color: PigTokens.textTertiary),
          ),
          const SizedBox(height: 16),
          Material(
            color: PigTokens.surface,
            borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: ready && !_busy ? _sync : null,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('同步'),
                  ),
                  if (!ready) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '云服务不可用，请确认配置信息',
                      style: TextStyle(color: PigTokens.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: PigTokens.surface,
            borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              title: const Text('自动同步账本'),
              subtitle: const Text('即将推出'),
              value: false,
              onChanged: null,
            ),
          ),
        ],
      ),
    );
  }
}
