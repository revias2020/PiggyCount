import 'dart:typed_data';

import 'ai_config.dart';
import 'ai_config_store.dart';
import 'bill_info.dart';
import 'extraction_context.dart';
import 'json_response_parser.dart';
import 'openai_compatible_client.dart';
import 'prompt_builder.dart';

/// 从文本/图片提取 [BillInfo]；不落库。
class AiExtractionEngine {
  AiExtractionEngine({
    AiConfigStore? configStore,
    OpenAiCompatibleClient? client,
    PromptBuilder? promptBuilder,
    JsonResponseParser? parser,
  })  : _store = configStore ?? AiConfigStore(),
        _client = client ?? OpenAiCompatibleClient(),
        _prompts = promptBuilder ?? const PromptBuilder(),
        _parser = parser ?? const JsonResponseParser();

  final AiConfigStore _store;
  final OpenAiCompatibleClient _client;
  final PromptBuilder _prompts;
  final JsonResponseParser _parser;

  Future<AiConfig> _config() => _store.load();

  Future<List<BillInfo>> extractFromText({
    required String text,
    required AiExtractionContext context,
  }) async {
    final config = await _config();
    final prompt = _prompts.build(
      context: context,
      inputSource: '从以下用户描述中',
      userText: text,
    );
    final raw = await _client.chat(config: config, userPrompt: prompt);
    return _parser.parse(raw);
  }

  Future<List<BillInfo>> extractFromImage({
    required Uint8List imageBytes,
    required AiExtractionContext context,
    String mimeType = 'image/jpeg',
  }) async {
    final config = await _config();
    final prompt = _prompts.build(
      context: context,
      inputSource: '分析支付账单截图，从中',
      billGuard: PromptBuilder.billGuardForImage,
    );
    final raw = await _client.vision(
      config: config,
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
    final config = await _config();
    return _client.chat(
      config: config,
      userPrompt: userMessage,
      systemPrompt: systemPrompt,
      temperature: 0.7,
    );
  }
}
