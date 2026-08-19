import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_provider.dart';
import '../../providers/ledger_session_provider.dart';
import '../../styles/tokens.dart';
import '../../sync/workspace_codec.dart';
import '../../sync/workspace_merge.dart';
import '../../sync/workspace_models.dart';
import '../../sync/workspace_store.dart';
import '../system/logger_service.dart';
import 'cloud_sync_config.dart';
import 'cloud_sync_providers.dart';
import 'cloud_sync_service.dart';

/// 测连成功后写入已测通：表单与已保存字段一致则整份标记；否则只记指纹供随后「保存」保留。
Future<void> persistCloudVerifiedAfterTest({
  required WidgetRef ref,
  required CloudSyncConfig draft,
}) async {
  final store = ref.read(cloudSyncConfigStoreProvider);
  final saved = await store.load();
  final fp = draft.connectionFingerprint();
  if (draft.hasRequiredFields &&
      saved.connectionFingerprint() == fp &&
      saved.hasRequiredFields) {
    await store.save(saved.markedVerified());
  } else {
    await store.markVerifiedFingerprint(fp);
  }
  ref.invalidate(cloudSyncConfigProvider);
}

/// 同步确认：是否允许拉云。取消则完全不联网。
Future<bool> confirmStartSync(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('是否开始同步'),
      content: const Text(
        '将对齐全部账本以及分类、标签。耗时取决于网盘。\n'
        '建议先到「数据管理」导出一份，以免同步损坏数据。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确认'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 入口共用：确认 → 拉云合并 → 预览 → 应用并写回云。明细顶栏不先打开同步页。
Future<void> runWorkspaceSync({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final cfg = ref.read(cloudSyncConfigProvider).valueOrNull;
  if (cfg == null || !cfg.isReadyForSync) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('云服务不可用，请确认配置信息')),
      );
    }
    return;
  }
  if (!await confirmStartSync(context)) return;
  if (!context.mounted) return;

  final service = ref.read(cloudSyncServiceProvider);
  final store = WorkspaceStore(ref.read(databaseProvider));

  late CloudRemoteDocument remote;
  late WorkspaceMergeResult merged;
  try {
    await _withBusy(context, '正在拉取云端…', () async {
      remote = await service.downloadWorkspace(cfg);
      final local = await store.capture();
      merged = WorkspaceMerge.merge(
        local: local,
        remote: _decodeRemote(remote.body),
      );
    });
  } catch (_) {
    return;
  }
  if (!context.mounted) return;

  final apply = await showSyncPreviewDialog(context, merged.preview);
  if (apply != true || !context.mounted) return;

  try {
    await _withBusy(context, '正在写入…', () async {
      var snapshot = merged.merged;
      var etag = remote.etag;
      const maxAttempts = 3;
      for (var i = 0; i < maxAttempts; i++) {
        try {
          await service.uploadWorkspace(
            config: cfg,
            body: jsonEncode(WorkspaceCodec.encode(snapshot)),
            ifMatch: etag,
          );
          break;
        } on CloudPreconditionFailed {
          if (i == maxAttempts - 1) rethrow;
          remote = await service.downloadWorkspace(cfg);
          final local = await store.capture();
          snapshot = WorkspaceMerge.merge(
            local: local,
            remote: _decodeRemote(remote.body),
          ).merged;
          etag = remote.etag;
        }
      }
      await store.apply(snapshot);
      ref.read(transactionRepositoryProvider).notifyChanged();
      ref.invalidate(ledgerSessionProvider);
      await persistCloudVerifiedAfterTest(ref: ref, draft: cfg);
      logger.info('Sync', '工作区同步完成');
    });
  } catch (_) {
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('同步完成')),
    );
  }
}

WorkspaceSnapshot _decodeRemote(String? body) {
  if (body == null || body.trim().isEmpty) {
    return const WorkspaceSnapshot();
  }
  final json = jsonDecode(body);
  if (json is! Map) return const WorkspaceSnapshot();
  return WorkspaceCodec.decode(Map<String, Object?>.from(json));
}

Future<bool?> showSyncPreviewDialog(
  BuildContext context,
  SyncPreview preview,
) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('同步预览'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _previewRow('分类与标签', preview.catalog),
          const SizedBox(height: 8),
          _previewRow('账本', preview.ledgers),
          const SizedBox(height: 8),
          _previewRow('账单', preview.bills),
          if (preview.categoryTreeConflict != null) ...[
            const SizedBox(height: 12),
            Text(
              preview.categoryTreeConflict!,
              style: const TextStyle(color: PigTokens.danger, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('应用'),
        ),
      ],
    ),
  );
}

Widget _previewRow(String label, SyncPreviewCounts counts) {
  return Text(
    '$label  新增 ${counts.added}　更新 ${counts.updated}　删除 ${counts.deleted}',
    style: const TextStyle(fontSize: 14),
  );
}

Future<void> _withBusy(
  BuildContext context,
  String message,
  Future<void> Function() body,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    await body();
  } catch (e, st) {
    logger.error('Sync', '同步失败', e, st);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('同步失败'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
    rethrow;
  }
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}
