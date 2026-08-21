import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/automation/auto_billing_service.dart';
import '../services/automation/billing_notification_service.dart';
import '../services/automation/screenshot_monitor_service.dart';
import 'ai_providers.dart';
import 'database_provider.dart';
import 'ledger_session_provider.dart';
import 'pending_review_providers.dart';

final billingNotificationServiceProvider = Provider(
  (_) => BillingNotificationService(),
);

final autoBillingServiceProvider = Provider(
  (ref) => AutoBillingService(
    bookkeeper: ref.watch(aiBookkeeperProvider),
    resolveLedgerId: () async => ref.read(currentLedgerIdProvider),
    notifications: ref.watch(billingNotificationServiceProvider),
    providerStore: ref.watch(aiProviderStoreProvider),
    onAutoSaved: (ids, source, ledgerId) async {
      if (source != 'screenshot' && source != 'share') return;
      if (ids.isEmpty) return;
      final repo = ref.read(transactionRepositoryProvider);
      final pending = ref.read(pendingReviewProvider.notifier);
      final notifications = ref.read(billingNotificationServiceProvider);
      String? lastSyncId;
      for (final id in ids) {
        final tx = await repo.getById(id);
        if (tx == null) continue;
        await pending.addFromTransaction(tx);
        lastSyncId = tx.syncId;
      }
      if (lastSyncId != null) {
        notifications.lastSuccessSyncId = lastSyncId;
      }
    },
  ),
);

final screenshotMonitorServiceProvider = Provider(
  (ref) => ScreenshotMonitorService(ref.watch(autoBillingServiceProvider)),
);
