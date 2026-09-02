import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_provider_config.dart';
import '../ai/ai_provider_store.dart';
import '../ai/extraction_engine.dart';
import '../services/ai/ai_bookkeeper.dart';
import '../services/ai/bill_creation_service.dart';
import '../services/ai/offline_asr_model_store.dart';
import '../services/ai/speech_engine_preference.dart';
import '../services/ai/voice_recognition_session.dart';
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

final speechEnginePreferenceStoreProvider =
    Provider((ref) => SpeechEnginePreferenceStore());

final speechEngineKindProvider =
    FutureProvider<SpeechRecognitionEngineKind>((ref) {
  return ref.watch(speechEnginePreferenceStoreProvider).load();
});

final offlineAsrModelStoreProvider = Provider((ref) => OfflineAsrModelStore());

final voiceRecognitionSessionProvider = Provider((ref) {
  return VoiceRecognitionSession(
    preferenceStore: ref.watch(speechEnginePreferenceStoreProvider),
    offlineStore: ref.watch(offlineAsrModelStoreProvider),
    aiStore: ref.watch(aiProviderStoreProvider),
  );
});

final autoGenerateTagsProvider = StreamProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAutoGenerateTags();
});

final screenshotAutoBillingProvider = StreamProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).watchScreenshotAutoBilling();
});

final screenshotWatchDirectoriesProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(settingsRepositoryProvider).watchScreenshotWatchDirectories();
});
