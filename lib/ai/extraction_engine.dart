import 'dart:typed_data';

import 'ai_provider_config.dart';
import 'ai_provider_store.dart';
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
