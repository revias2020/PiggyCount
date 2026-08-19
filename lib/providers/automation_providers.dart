import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/automation/auto_billing_service.dart';
import '../services/automation/billing_notification_service.dart';
import '../services/automation/screenshot_monitor_service.dart';
import 'ai_providers.dart';
import 'ledger_session_provider.dart';

final billingNotificationServiceProvider = Provider(
  (_) => BillingNotificationService(),
);

final autoBillingServiceProvider = Provider(
  (ref) => AutoBillingService(
    bookkeeper: ref.watch(aiBookkeeperProvider),
    resolveLedgerId: () async => ref.read(currentLedgerIdProvider),
    notifications: ref.watch(billingNotificationServiceProvider),
    providerStore: ref.watch(aiProviderStoreProvider),
  ),
);

final screenshotMonitorServiceProvider = Provider(
  (ref) => ScreenshotMonitorService(ref.watch(autoBillingServiceProvider)),
);
