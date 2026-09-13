import 'dart:convert';

import 'ai_provider_config.dart';
import 'ai_provider_store.dart';

/// 服务商配置包（ADR-079）：`.txt` 内 UTF-8 JSON。
class AiProviderConfigPackage {
  const AiProviderConfigPackage({
    required this.version,
    required this.providers,
    required this.binding,
  });

  static const currentVersion = 1;

  final int version;
  final List<AiServiceProvider> providers;
  final AiCapabilityBinding binding;

  Map<String, dynamic> toJson() => {
        'version': version,
        'providers': providers.map((e) => e.toJson()).toList(),
        'binding': binding.toJson(),
      };

  String encode({bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  /// 解析并校验；失败抛 [FormatException]（整包拒绝）。
  factory AiProviderConfigPackage.parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('配置包为空');
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      throw const FormatException('配置包不是有效 JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('配置包格式无效');
    }
    final versionRaw = decoded['version'];
    final version = versionRaw is int
        ? versionRaw
        : versionRaw is num
            ? versionRaw.toInt()
            : null;
    if (version != currentVersion) {
      throw const FormatException('无法识别的配置包版本');
    }

    final providersRaw = decoded['providers'];
    if (providersRaw is! List) {
      throw const FormatException('配置包缺少服务商列表');
    }
    if (providersRaw.isEmpty) {
      throw const FormatException('配置包服务商列表为空');
    }

    final providers = <AiServiceProvider>[];
    final seen = <String>{};
    for (final item in providersRaw) {
      if (item is! Map) {
        throw const FormatException('配置包服务商项无效');
      }
      final map = Map<String, dynamic>.from(item);
      final provider = normalizeImported(AiServiceProvider.fromJson(map));
      if (provider.id.trim().isEmpty) {
        throw const FormatException('配置包存在空的服务商 id');
      }
      if (!seen.add(provider.id)) {
        throw FormatException('配置包存在重复的服务商 id：${provider.id}');
      }
      providers.add(provider);
    }

    final bindingRaw = decoded['binding'];
    if (bindingRaw is! Map) {
      throw const FormatException('配置包缺少能力绑定');
    }
    final binding = AiCapabilityBinding.fromJson(
      Map<String, dynamic>.from(bindingRaw),
    );
    final ids = seen;
    void requireBound(String? id, String label) {
      if (id == null || id.isEmpty) {
        throw FormatException('能力绑定「$label」为空');
      }
      if (!ids.contains(id)) {
        throw FormatException('能力绑定「$label」引用了包内不存在的服务商');
      }
    }

    requireBound(binding.textProviderId, '文本对话');
    requireBound(binding.visionProviderId, '图片理解');
    requireBound(binding.voiceProviderId, '语音直接记账');

    final customCount =
        providers.where((p) => !p.isBuiltIn).length;
    if (customCount > AiProviderStore.maxCustomProviders) {
      throw FormatException(
        '自定义服务商最多 ${AiProviderStore.maxCustomProviders} 个',
      );
    }

    return AiProviderConfigPackage(
      version: version!,
      providers: providers,
      binding: binding,
    );
  }

  /// 内置按稳定 id 锁死；伪造的 isBuiltIn 降为自定义。
  static AiServiceProvider normalizeImported(AiServiceProvider provider) {
    final template = AiServiceProvider.builtInTemplate(provider.id);
    if (template != null) {
      return provider.copyWith(
        name: template.name,
        baseUrl: template.baseUrl,
        isBuiltIn: true,
      );
    }
    return provider.copyWith(isBuiltIn: false);
  }
}

/// 导入模式（ADR-079）。
enum AiProviderImportMode { merge, overwrite }

/// 配置包导入失败（含超限等业务拒绝）。
class AiProviderConfigPackageException implements Exception {
  AiProviderConfigPackageException(this.message);
  final String message;

  @override
  String toString() => message;
}
