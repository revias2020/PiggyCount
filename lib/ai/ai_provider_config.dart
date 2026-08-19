/// AI 服务商与能力绑定（ADR-009 / ADR-032）。
library;

/// 能力类型：仅文本 / 视觉（无大模型 ASR）。
enum AiCapabilityKind { text, vision }

extension AiCapabilityKindLabel on AiCapabilityKind {
  String get label => switch (this) {
        AiCapabilityKind.text => '文本对话',
        AiCapabilityKind.vision => '图片理解',
      };
}

/// 服务商某侧模型的上次连接测试结果（ADR-032）。
enum AiModelTestStatus { untested, success, failed }

extension AiModelTestStatusCodec on AiModelTestStatus {
  String get wire => switch (this) {
        AiModelTestStatus.untested => 'untested',
        AiModelTestStatus.success => 'success',
        AiModelTestStatus.failed => 'failed',
      };

  static AiModelTestStatus parse(Object? raw) {
    return switch (raw) {
      'success' => AiModelTestStatus.success,
      'failed' => AiModelTestStatus.failed,
      _ => AiModelTestStatus.untested,
    };
  }
}

/// 单个服务商配置。
class AiServiceProvider {
  const AiServiceProvider({
    required this.id,
    required this.name,
    required this.isBuiltIn,
    required this.apiKey,
    required this.baseUrl,
    required this.textModel,
    required this.visionModel,
    required this.createdAt,
    this.textTestStatus = AiModelTestStatus.untested,
    this.visionTestStatus = AiModelTestStatus.untested,
  });

  final String id;
  final String name;
  final bool isBuiltIn;
  final String apiKey;
  final String baseUrl;
  final String textModel;
  final String visionModel;
  final DateTime createdAt;
  final AiModelTestStatus textTestStatus;
  final AiModelTestStatus visionTestStatus;

  static const zhipuId = 'zhipu_glm';
  static const zhipuDefaultBaseUrl = 'https://open.bigmodel.cn/api/paas/v4';
  static const zhipuDefaultTextModel = 'glm-4-flash';
  static const zhipuDefaultVisionModel = 'glm-4v-flash';

  /// 内置智谱（不可删除）。
  static AiServiceProvider get zhipuDefault => AiServiceProvider(
        id: zhipuId,
        name: '智谱GLM',
        isBuiltIn: true,
        apiKey: '',
        baseUrl: zhipuDefaultBaseUrl,
        textModel: zhipuDefaultTextModel,
        visionModel: zhipuDefaultVisionModel,
        createdAt: DateTime(2024, 1, 1),
      );

  bool get isValid => apiKey.trim().isNotEmpty;

  bool get supportsText => textModel.trim().isNotEmpty;

  bool get supportsVision => visionModel.trim().isNotEmpty;

  /// 能力选择 / resolve：该侧有模型且上次测连成功（ADR-032）。
  bool get textReadyForCapability =>
      supportsText && textTestStatus == AiModelTestStatus.success;

  bool get visionReadyForCapability =>
      supportsVision && visionTestStatus == AiModelTestStatus.success;

  AiServiceProvider copyWith({
    String? id,
    String? name,
    bool? isBuiltIn,
    String? apiKey,
    String? baseUrl,
    String? textModel,
    String? visionModel,
    DateTime? createdAt,
    AiModelTestStatus? textTestStatus,
    AiModelTestStatus? visionTestStatus,
  }) {
    return AiServiceProvider(
      id: id ?? this.id,
      name: name ?? this.name,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      textModel: textModel ?? this.textModel,
      visionModel: visionModel ?? this.visionModel,
      createdAt: createdAt ?? this.createdAt,
      textTestStatus: textTestStatus ?? this.textTestStatus,
      visionTestStatus: visionTestStatus ?? this.visionTestStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isBuiltIn': isBuiltIn,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'textModel': textModel,
        'visionModel': visionModel,
        'createdAt': createdAt.toIso8601String(),
        'textTestStatus': textTestStatus.wire,
        'visionTestStatus': visionTestStatus.wire,
      };

  factory AiServiceProvider.fromJson(Map<String, dynamic> json) {
    return AiServiceProvider(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      apiKey: json['apiKey'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      textModel: json['textModel'] as String? ?? '',
      visionModel: json['visionModel'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      textTestStatus: AiModelTestStatusCodec.parse(json['textTestStatus']),
      visionTestStatus: AiModelTestStatusCodec.parse(json['visionTestStatus']),
    );
  }
}

/// 文本 / 视觉各绑定一个服务商 id。
class AiCapabilityBinding {
  const AiCapabilityBinding({
    this.textProviderId,
    this.visionProviderId,
  });

  final String? textProviderId;
  final String? visionProviderId;

  static const defaultBinding = AiCapabilityBinding(
    textProviderId: AiServiceProvider.zhipuId,
    visionProviderId: AiServiceProvider.zhipuId,
  );

  AiCapabilityBinding copyWith({
    String? textProviderId,
    String? visionProviderId,
  }) {
    return AiCapabilityBinding(
      textProviderId: textProviderId ?? this.textProviderId,
      visionProviderId: visionProviderId ?? this.visionProviderId,
    );
  }

  bool isBoundTo(String providerId) =>
      textProviderId == providerId || visionProviderId == providerId;

  Map<String, dynamic> toJson() => {
        'textProviderId': textProviderId,
        'visionProviderId': visionProviderId,
      };

  factory AiCapabilityBinding.fromJson(Map<String, dynamic> json) {
    return AiCapabilityBinding(
      textProviderId: json['textProviderId'] as String?,
      visionProviderId: json['visionProviderId'] as String?,
    );
  }
}

/// 能力未就绪（无绑定 / 无 Key / 无对应模型），供 UI 走 E1 SnackBar。
class AiCapabilityNotReadyException implements Exception {
  AiCapabilityNotReadyException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 删除被能力绑定的服务商时抛出（D2）。
class AiProviderInUseException implements Exception {
  AiProviderInUseException(this.message);
  final String message;

  @override
  String toString() => message;
}
