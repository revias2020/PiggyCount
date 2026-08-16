import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pages/settings/data_manage_page.dart';
import '../../providers/database_provider.dart';
import 'cloud_sync_config.dart';
import 'cloud_sync_service.dart';

final cloudSyncConfigStoreProvider = Provider((_) => CloudSyncConfigStore());

final cloudSyncConfigProvider = FutureProvider<CloudSyncConfig>((ref) {
  return ref.watch(cloudSyncConfigStoreProvider).load();
});

final cloudSyncServiceProvider = Provider(
  (ref) => CloudSyncService(
    csv: ref.watch(csvServiceProvider),
    ledgers: ref.watch(ledgerRepositoryProvider),
  ),
);
