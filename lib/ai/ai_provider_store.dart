import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai_config.dart';
import 'ai_provider_config.dart';

/// 多服务商 + 能力绑定存储（ADR-009 / ADR-032）；含旧版单配置 M1 迁移。
class AiProviderStore {
  static const providersKey = 'ai_providers_v2';
  static const bindingKey = 'ai_capability_binding_v2';
  static const legacyConfigKey = 'ai_config_v1';
  static const maxCustomProviders = 5;

  Future<List<AiServiceProvider>> loadProviders() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(providersKey);
    if (raw == null || raw.isEmpty) {
      await _migrateFromLegacy(prefs);
      raw = prefs.getString(providersKey);
    }
    if (raw == null || raw.isEmpty) {
      final defaults = [AiServiceProvider.zhipuDefault];
      await _saveProviders(prefs, defaults);
      await _ensureBinding(prefs);
      return defaults;
    }
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => AiServiceProvider.fromJson(e as Map<String, dynamic>))
          .toList();
      return _ensureZhipuPresent(prefs, list);
    } catch (_) {
      final defaults = [AiServiceProvider.zhipuDefault];
      await _saveProviders(prefs, defaults);
      return defaults;
    }
  }

  Future<AiCapabilityBinding> loadBinding() async {
    final prefs = await SharedPreferences.getInstance();
    await loadProviders(); // 触发迁移与内置智谱兜底
    final raw = prefs.getString(bindingKey);
    if (raw == null || raw.isEmpty) {
      await prefs.setString(
        bindingKey,
        jsonEncode(AiCapabilityBinding.defaultBinding.toJson()),
      );
      return AiCapabilityBinding.defaultBinding;
    }
    try {
      return AiCapabilityBinding.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return AiCapabilityBinding.defaultBinding;
    }
  }

  Future<void> saveBinding(AiCapabilityBinding binding) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(bindingKey, jsonEncode(binding.toJson()));
  }

  Future<AiServiceProvider?> getProvider(String id) async {
    final list = await loadProviders();
    for (final p in list) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 解析某能力当前服务商；未就绪抛 [AiCapabilityNotReadyException]。
  Future<AiServiceProvider> resolve(AiCapabilityKind kind) async {
    final binding = await loadBinding();
    final id = kind == AiCapabilityKind.text
        ? binding.textProviderId
        : binding.visionProviderId;
    if (id == null || id.isEmpty) {
      throw AiCapabilityNotReadyException(
        '未绑定「${kind.label}」服务商，请到「我的 → AI 设置」配置',
      );
    }
    final provider = await getProvider(id);
    if (provider == null) {
      throw AiCapabilityNotReadyException(
        '「${kind.label}」绑定的服务商不存在，请到「我的 → AI 设置」重新选择',
      );
    }
    if (!provider.isValid) {
      throw AiCapabilityNotReadyException(
        '请先为「${provider.name}」填写 API Key（我的 → AI 设置）',
      );
    }
    if (kind == AiCapabilityKind.text && !provider.supportsText) {
      throw AiCapabilityNotReadyException(
        '「${provider.name}」未填写文本模型，请到服务商编辑页配置',
      );
    }
    if (kind == AiCapabilityKind.vision && !provider.supportsVision) {
      throw AiCapabilityNotReadyException(
        '「${provider.name}」未填写视觉模型，请到服务商编辑页配置',
      );
    }
    if (kind == AiCapabilityKind.text && !provider.textReadyForCapability) {
      throw AiCapabilityNotReadyException(
        '「${provider.name}」文本模型未通过连接测试，请到服务商编辑页保存以完成测连',
      );
    }
    if (kind == AiCapabilityKind.vision && !provider.visionReadyForCapability) {
      throw AiCapabilityNotReadyException(
        '「${provider.name}」视觉模型未通过连接测试，请到服务商编辑页保存以完成测连',
      );
    }
    return provider;
  }

  Future<bool> isTextReady() async {
    try {
      await resolve(AiCapabilityKind.text);
      return true;
    } on AiCapabilityNotReadyException {
      return false;
    }
  }

  Future<bool> canAddCustomProvider() async {
    final list = await loadProviders();
    final custom = list.where((p) => !p.isBuiltIn).length;
    return custom < maxCustomProviders;
  }

  Future<AiServiceProvider> addCustomProvider({
    required String name,
    required String apiKey,
    required String baseUrl,
    String textModel = 'gpt-4o-mini',
    String visionModel = 'gpt-4o-mini',
    AiModelTestStatus textTestStatus = AiModelTestStatus.untested,
    AiModelTestStatus visionTestStatus = AiModelTestStatus.untested,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadProviders();
    final customCount = list.where((p) => !p.isBuiltIn).length;
    if (customCount >= maxCustomProviders) {
      throw StateError('自定义服务商最多 $maxCustomProviders 个');
    }
    final provider = AiServiceProvider(
      id: _newId(),
      name: name.trim().isEmpty ? '自定义服务商' : name.trim(),
      isBuiltIn: false,
      apiKey: apiKey,
      baseUrl: baseUrl.trim().isEmpty
          ? 'https://api.openai.com/v1'
          : baseUrl.trim(),
      textModel: textModel,
      visionModel: visionModel,
      createdAt: DateTime.now(),
      textTestStatus: textTestStatus,
      visionTestStatus: visionTestStatus,
    );
    list.add(provider);
    await _saveProviders(prefs, list);
    return provider;
  }

  Future<void> updateProvider(AiServiceProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadProviders();
    final i = list.indexWhere((p) => p.id == provider.id);
    if (i < 0) return;
    // 内置：锁死 id / isBuiltIn / name / baseUrl
    final next = provider.isBuiltIn
        ? list[i].copyWith(
            apiKey: provider.apiKey,
            textModel: provider.textModel,
            visionModel: provider.visionModel,
            textTestStatus: provider.textTestStatus,
            visionTestStatus: provider.visionTestStatus,
          )
        : provider;
    list[i] = next;
    await _saveProviders(prefs, list);
  }

  /// 删除自定义服务商；若仍被绑定则抛 [AiProviderInUseException]（D2）。
  Future<void> deleteProvider(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadProviders();
    AiServiceProvider? target;
    for (final p in list) {
      if (p.id == id) {
        target = p;
        break;
      }
    }
    if (target == null) return;
    if (target.isBuiltIn) {
      throw StateError('内置服务商不可删除');
    }
    final binding = await loadBinding();
    if (binding.isBoundTo(id)) {
      throw AiProviderInUseException(
        '该服务商正被「文本对话」或「图片理解」使用，请先在 AI 设置中改绑后再删除',
      );
    }
    list.removeWhere((p) => p.id == id);
    await _saveProviders(prefs, list);
  }

  /// 「我的」副标题：已配 Key 的服务商数摘要。
  Future<String> mineSubtitle() async {
    final list = await loadProviders();
    final ready = list.where((p) => p.isValid).length;
    if (ready == 0) return '未配置 API Key';
    return '$ready 个服务商已配置';
  }

  Future<List<AiServiceProvider>> _ensureZhipuPresent(
    SharedPreferences prefs,
    List<AiServiceProvider> list,
  ) async {
    if (list.any((p) => p.id == AiServiceProvider.zhipuId)) {
      await _ensureBinding(prefs);
      return list;
    }
    list.insert(0, AiServiceProvider.zhipuDefault);
    await _saveProviders(prefs, list);
    await _ensureBinding(prefs);
    return list;
  }

  Future<void> _ensureBinding(SharedPreferences prefs) async {
    final raw = prefs.getString(bindingKey);
    if (raw == null || raw.isEmpty) {
      await prefs.setString(
        bindingKey,
        jsonEncode(AiCapabilityBinding.defaultBinding.toJson()),
      );
    }
  }

  Future<void> _saveProviders(
    SharedPreferences prefs,
    List<AiServiceProvider> list,
  ) async {
    await prefs.setString(
      providersKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  /// M1：旧 `ai_config_v1` → 服务商列表 + 双绑。
  Future<void> _migrateFromLegacy(SharedPreferences prefs) async {
    final legacyRaw = prefs.getString(legacyConfigKey);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      final defaults = [AiServiceProvider.zhipuDefault];
      await _saveProviders(prefs, defaults);
      await prefs.setString(
        bindingKey,
        jsonEncode(AiCapabilityBinding.defaultBinding.toJson()),
      );
      return;
    }

    AiConfig? legacy;
    try {
      legacy = AiConfig.fromJson(jsonDecode(legacyRaw) as Map<String, dynamic>);
    } catch (_) {
      legacy = null;
    }

    if (legacy == null) {
      final defaults = [AiServiceProvider.zhipuDefault];
      await _saveProviders(prefs, defaults);
      await prefs.setString(
        bindingKey,
        jsonEncode(AiCapabilityBinding.defaultBinding.toJson()),
      );
      return;
    }

    if (legacy.kind == AiProviderKind.zhipu) {
      final zhipu = AiServiceProvider.zhipuDefault.copyWith(
        apiKey: legacy.apiKey,
        textModel: legacy.textModel.isEmpty
            ? AiServiceProvider.zhipuDefaultTextModel
            : legacy.textModel,
        visionModel: legacy.visionModel.isEmpty
            ? AiServiceProvider.zhipuDefaultVisionModel
            : legacy.visionModel,
      );
      await _saveProviders(prefs, [zhipu]);
      await prefs.setString(
        bindingKey,
        jsonEncode(AiCapabilityBinding.defaultBinding.toJson()),
      );
    } else {
      final custom = AiServiceProvider(
        id: _newId(),
        name: 'OpenAI 兼容',
        isBuiltIn: false,
        apiKey: legacy.apiKey,
        baseUrl: legacy.baseUrl.isEmpty
            ? 'https://api.openai.com/v1'
            : legacy.baseUrl,
        textModel:
            legacy.textModel.isEmpty ? 'gpt-4o-mini' : legacy.textModel,
        visionModel:
            legacy.visionModel.isEmpty ? 'gpt-4o-mini' : legacy.visionModel,
        createdAt: DateTime.now(),
      );
      await _saveProviders(prefs, [AiServiceProvider.zhipuDefault, custom]);
      await prefs.setString(
        bindingKey,
        jsonEncode(
          AiCapabilityBinding(
            textProviderId: custom.id,
            visionProviderId: custom.id,
          ).toJson(),
        ),
      );
    }
    // 保留旧 key 以免回滚丢数据；新数据以 v2 为准。
  }

  String _newId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'provider_${ts}_$r';
  }
}
