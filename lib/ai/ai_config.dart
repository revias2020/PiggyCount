/// AI 服务商类型：内置智谱（OpenAI 兼容接口）或自定义 OpenAI 兼容。
enum AiProviderKind { zhipu, openaiCompatible }

/// 当前生效的 AI 配置（存 SharedPreferences）。
class AiConfig {
  const AiConfig({
    required this.kind,
    required this.apiKey,
    required this.baseUrl,
    required this.textModel,
    required this.visionModel,
  });

  final AiProviderKind kind;
  final String apiKey;
  final String baseUrl;
  final String textModel;
  final String visionModel;

  bool get isConfigured => apiKey.trim().isNotEmpty;

  static const zhipuDefaultBaseUrl = 'https://open.bigmodel.cn/api/paas/v4';
  static const zhipuDefaultTextModel = 'glm-4-flash';
  static const zhipuDefaultVisionModel = 'glm-4v-flash';

  static AiConfig zhipu({
    String apiKey = '',
    String textModel = zhipuDefaultTextModel,
    String visionModel = zhipuDefaultVisionModel,
  }) {
    return AiConfig(
      kind: AiProviderKind.zhipu,
      apiKey: apiKey,
      baseUrl: zhipuDefaultBaseUrl,
      textModel: textModel,
      visionModel: visionModel,
    );
  }

  static AiConfig openaiCompatible({
    String apiKey = '',
    String baseUrl = 'https://api.openai.com/v1',
    String textModel = 'gpt-4o-mini',
    String visionModel = 'gpt-4o-mini',
  }) {
    return AiConfig(
      kind: AiProviderKind.openaiCompatible,
      apiKey: apiKey,
      baseUrl: baseUrl,
      textModel: textModel,
      visionModel: visionModel,
    );
  }

  AiConfig copyWith({
    AiProviderKind? kind,
    String? apiKey,
    String? baseUrl,
    String? textModel,
    String? visionModel,
  }) {
    return AiConfig(
      kind: kind ?? this.kind,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      textModel: textModel ?? this.textModel,
      visionModel: visionModel ?? this.visionModel,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'textModel': textModel,
        'visionModel': visionModel,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'zhipu';
    final kind = kindName == AiProviderKind.openaiCompatible.name
        ? AiProviderKind.openaiCompatible
        : AiProviderKind.zhipu;
    return AiConfig(
      kind: kind,
      apiKey: json['apiKey'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ??
          (kind == AiProviderKind.zhipu
              ? zhipuDefaultBaseUrl
              : 'https://api.openai.com/v1'),
      textModel: json['textModel'] as String? ??
          (kind == AiProviderKind.zhipu
              ? zhipuDefaultTextModel
              : 'gpt-4o-mini'),
      visionModel: json['visionModel'] as String? ??
          (kind == AiProviderKind.zhipu
              ? zhipuDefaultVisionModel
              : 'gpt-4o-mini'),
    );
  }
}
