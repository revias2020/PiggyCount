import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_provider_config.dart';
import '../ai/ai_provider_store.dart';
import '../ai/extraction_engine.dart';
import '../services/ai/ai_bookkeeper.dart';
import '../services/ai/ai_chat_service.dart';
import '../services/ai/bill_creation_service.dart';
import '../services/ai/speech_asr_service.dart';
import 'database_provider.dart';

final aiProviderStoreProvider = Provider((ref) => AiProviderStore());

final aiProvidersListProvider =
    FutureProvider<List<AiServiceProvider>>((ref) {
  return ref.watch(aiProviderStoreProvider).loadProviders();
});

final aiCapabilityBindingProvider =
    FutureProvider<AiCapabilityBinding>((ref) {
  return ref.watch(aiProviderStoreProvider).loadBinding();
});

/// 「我的 · AI 设置」副标题。
final aiMineSubtitleProvider = FutureProvider<String>((ref) {
  ref.watch(aiProvidersListProvider);
  return ref.watch(aiProviderStoreProvider).mineSubtitle();
});

final textCapabilityReadyProvider = FutureProvider<bool>((ref) {
  return ref.watch(aiProviderStoreProvider).isTextReady();
});

final extractionEngineProvider = Provider((ref) {
  return AiExtractionEngine(
    providerStore: ref.watch(aiProviderStoreProvider),
  );
});

final billCreationServiceProvider = Provider(
  (ref) => BillCreationService(
    categories: ref.watch(categoryRepositoryProvider),
    tags: ref.watch(tagRepositoryProvider),
    transactions: ref.watch(transactionRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

final aiBookkeeperProvider = Provider(
  (ref) => AiBookkeeper(
    engine: ref.watch(extractionEngineProvider),
    creation: ref.watch(billCreationServiceProvider),
  ),
);

final aiChatServiceProvider = Provider(
  (ref) => AiChatService(
    bookkeeper: ref.watch(aiBookkeeperProvider),
    engine: ref.watch(extractionEngineProvider),
    statistics: ref.watch(statisticsRepositoryProvider),
  ),
);

final speechAsrServiceProvider = Provider((ref) => SpeechAsrService());

final autoGenerateTagsProvider = StreamProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAutoGenerateTags();
});

final screenshotAutoBillingProvider = StreamProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).watchScreenshotAutoBilling();
});

final aiAssistantEnabledProvider = StreamProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAiAssistantEnabled();
});
