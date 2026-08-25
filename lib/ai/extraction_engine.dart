import 'dart:async';
import 'dart:typed_data';

import '../services/system/logger_service.dart';
import 'ai_provider_config.dart';
import 'ai_provider_store.dart';
import 'ai_vision_failure.dart';
import 'bill_info.dart';
import 'extraction_context.dart';
import 'json_response_parser.dart';
import 'openai_compatible_client.dart';
import 'prompt_builder.dart';

/// 从文本/图片提取 [BillInfo]；不落库。按能力绑定解析服务商（ADR-009）。
class AiExtractionEngine {
  AiExtractionEngine({
    AiProviderStore? providerStore,
    OpenAiCompatibleClient? client,
    PromptBuilder? promptBuilder,
    JsonResponseParser? parser,
  })  : _store = providerStore ?? AiProviderStore(),
        _client = client ?? OpenAiCompatibleClient(),
        _prompts = promptBuilder ?? const PromptBuilder(),
        _parser = parser ?? const JsonResponseParser();

  final AiProviderStore _store;
  final OpenAiCompatibleClient _client;
  final PromptBuilder _prompts;
  final JsonResponseParser _parser;

  Future<List<BillInfo>> extractFromText({
    required String text,
    required AiExtractionContext context,
  }) async {
    final provider = await _store.resolve(AiCapabilityKind.text);
    final prompt = _prompts.build(
      context: context,
      inputSource: '从以下用户描述中',
      userText: text,
    );
    final raw = await _client.chat(provider: provider, userPrompt: prompt);
    return _parser.parse(raw);
  }

  /// 前台图片识别：每服务商仅 1 次；失败立即切换下一已测通候选（ADR-055）。
  Future<List<BillInfo>> extractFromImage({
    required Uint8List imageBytes,
    required AiExtractionContext context,
    String mimeType = 'image/jpeg',
    AiVisionSwitchCallback? onSwitch,
  }) async {
    final providers = await _store.listVisionFallbackProviders();
    return _extractFromImageWithProviders(
      providers: providers,
      imageBytes: imageBytes,
      context: context,
      mimeType: mimeType,
      retryTransportOnSameProvider: false,
      onSwitch: onSwitch,
    );
  }

  /// 语音直接记账：音频 → BillInfo（ADR-052）。
  Future<List<BillInfo>> extractFromVoice({
    required Uint8List audioBytes,
    required AiExtractionContext context,
    String format = 'wav',
  }) async {
    final provider = await _store.resolve(AiCapabilityKind.voice);
    final prompt = _prompts.build(
      context: context,
      inputSource: '分析用户口述的记账内容，从中',
    );
    final raw = await _client.voice(
      provider: provider,
      audioBytes: audioBytes,
      prompt: prompt,
      format: format,
    );
    return _parser.parse(raw);
  }

  static const _networkRetryDelay = Duration(seconds: 3);

  /// 后台直存：网络失败 3s 重试 1 次；仍失败或非网络失败则换下一个已测通视觉服务商。
  Future<List<BillInfo>> extractFromImageWithFallback({
    required Uint8List imageBytes,
    required AiExtractionContext context,
    String mimeType = 'image/jpeg',
  }) async {
    final providers = await _store.listVisionFallbackProviders();
    return _extractFromImageWithProviders(
      providers: providers,
      imageBytes: imageBytes,
      context: context,
      mimeType: mimeType,
      retryTransportOnSameProvider: true,
    );
  }

  Future<List<BillInfo>> _extractFromImageWithProviders({
    required List<AiServiceProvider> providers,
    required Uint8List imageBytes,
    required AiExtractionContext context,
    required String mimeType,
    required bool retryTransportOnSameProvider,
    AiVisionSwitchCallback? onSwitch,
  }) async {
    if (providers.isEmpty) {
      throw AiCapabilityNotReadyException(
        '未绑定「图片理解」服务商，请到「我的 → AI 设置」配置',
      );
    }

    final prompt = _prompts.build(
      context: context,
      inputSource: '分析支付账单截图，从中',
      billGuard: PromptBuilder.billGuardForImage,
    );

    Object? lastError;
    for (var providerIndex = 0; providerIndex < providers.length; providerIndex++) {
      final provider = providers[providerIndex];
      final maxAttempts = retryTransportOnSameProvider ? 2 : 1;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (attempt == 1) {
          final prev = lastError;
          if (prev == null || !isAiTransportFailure(prev)) break;
          logger.info(
            'AI',
            '${_networkRetryDelay.inSeconds}s 后重试 '
            'provider=${provider.name} model=${provider.visionModel}',
          );
          await Future<void>.delayed(_networkRetryDelay);
        }
        try {
          final raw = await _client.vision(
            provider: provider,
            imageBytes: imageBytes,
            prompt: prompt,
            mimeType: mimeType,
          );
          return _parser.parse(raw);
        } catch (e) {
          lastError = e;
          final next = providerIndex + 1 < providers.length
              ? providers[providerIndex + 1]
              : null;
          final switchNow = !retryTransportOnSameProvider ||
              !isAiTransportFailure(e) ||
              attempt == maxAttempts - 1;
          if (switchNow && next != null) {
            logger.info(
              'AI',
              '切换 provider=${next.name} model=${next.visionModel} 重试',
            );
            onSwitch?.call(
              AiVisionSwitchEvent(
                failureMessage: aiVisionErrorMessage(e),
                nextProviderName: next.name,
                nextModel: next.visionModel,
              ),
            );
          }
          if (switchNow) break;
        }
      }
    }

    final err = lastError;
    final kind = err != null && isAiTransportFailure(err)
        ? AiVisionFailureKind.transport
        : AiVisionFailureKind.api;
    throw AiVisionExhaustedException(
      kind: kind,
      message: err == null ? '识别失败' : aiVisionErrorMessage(err),
      providersAttempted: providers.length,
    );
  }
}
