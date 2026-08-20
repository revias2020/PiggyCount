import 'dart:async';
import 'dart:typed_data';

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

  Future<List<BillInfo>> extractFromImage({
    required Uint8List imageBytes,
    required AiExtractionContext context,
    String mimeType = 'image/jpeg',
  }) async {
    final provider = await _store.resolve(AiCapabilityKind.vision);
    final prompt = _prompts.build(
      context: context,
      inputSource: '分析支付账单截图，从中',
      billGuard: PromptBuilder.billGuardForImage,
    );
    final raw = await _client.vision(
      provider: provider,
      imageBytes: imageBytes,
      prompt: prompt,
      mimeType: mimeType,
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
    for (final provider in providers) {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (attempt == 1) {
          final prev = lastError;
          if (prev == null || !isAiTransportFailure(prev)) break;
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
          if (!isAiTransportFailure(e)) break;
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

  /// 自由对话（账单分析等）。
  Future<String> chat({
    required String userMessage,
    String? systemPrompt,
  }) async {
    final provider = await _store.resolve(AiCapabilityKind.text);
    return _client.chat(
      provider: provider,
      userPrompt: userMessage,
      systemPrompt: systemPrompt,
      temperature: 0.7,
    );
  }
}
