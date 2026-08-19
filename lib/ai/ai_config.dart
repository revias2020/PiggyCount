// 旧版单服务商配置，仅供 AiProviderStore 的 M1 迁移读取。
// 新代码请使用 AiServiceProvider / AiCapabilityBinding。

enum AiProviderKind { zhipu, openaiCompatible }

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

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'zhipu';
    final kind = kindName == AiProviderKind.openaiCompatible.name
        ? AiProviderKind.openaiCompatible
        : AiProviderKind.zhipu;
    return AiConfig(
      kind: kind,
      apiKey: json['apiKey'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      textModel: json['textModel'] as String? ?? '',
      visionModel: json['visionModel'] as String? ?? '',
    );
  }
}
