import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pages/settings/data_manage_page.dart';
import '../../providers/ledger_session_provider.dart';
import 'cloud_sync_config.dart';
import 'cloud_sync_providers.dart';

/// 下载确认：追加导入，可能重复。
Future<bool> confirmCloudDownload(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('使用云端数据'),
      content: const Text(
        '将下载云端 CSV 并导入到本地。\n'
        '不会清空现有账单，可能产生重复。若需干净合并，请先自行清理。\n'
        '确定继续？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('导入云端'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 上传当前账本快照，成功后标记已测通。
Future<String> uploadCloudLedgerSnapshot({
  required WidgetRef ref,
  required CloudSyncConfig config,
}) async {
  final store = ref.read(cloudSyncConfigStoreProvider);
  final ready = config.markedVerified();
  await store.save(ready);
  ref.invalidate(cloudSyncConfigProvider);
  final url = await ref.read(cloudSyncServiceProvider).uploadSnapshot(
        config: ready,
        ledgerId: ref.read(currentLedgerIdProvider),
      );
  return url;
}

/// 下载并导入；成功后标记已测通。返回导入笔数。
Future<int> downloadAndImportCloudSnapshot({
  required WidgetRef ref,
  required CloudSyncConfig config,
}) async {
  final store = ref.read(cloudSyncConfigStoreProvider);
  final ready = config.markedVerified();
  await store.save(ready);
  ref.invalidate(cloudSyncConfigProvider);
  final raw =
      await ref.read(cloudSyncServiceProvider).downloadSnapshot(config: ready);
  final n = await ref.read(csvServiceProvider).importCsv(
        raw,
        defaultLedgerId: ref.read(currentLedgerIdProvider),
      );
  return n;
}

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
