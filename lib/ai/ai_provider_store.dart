import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai_config.dart';
import 'ai_provider_config.dart';
import 'ai_provider_config_package.dart';

/// 多服务商 + 能力绑定存储（ADR-009 / ADR-032 / ADR-078 / ADR-079）；含旧版单配置 M1 迁移。
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
      final defaults = List<AiServiceProvider>.from(
        AiServiceProvider.builtInDefaults,
      );
      await _saveProviders(prefs, defaults);
      await _ensureBinding(prefs);
      return defaults;
    }
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => AiServiceProvider.fromJson(e as Map<String, dynamic>))
          .toList();
      return _ensureBuiltInsPresent(prefs, list);
    } catch (_) {
      final defaults = List<AiServiceProvider>.from(
        AiServiceProvider.builtInDefaults,
      );
      await _saveProviders(prefs, defaults);
      return defaults;
    }
  }

  Future<AiCapabilityBinding> loadBinding() async {
    final prefs = await SharedPreferences.getInstance();
    await loadProviders(); // 触发迁移与内置服务商兜底
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
  /// 后台直存 Vision 回退候选：主绑定优先，其余按列表顺序；仅 [visionReadyForCapability]。
  Future<List<AiServiceProvider>> listVisionFallbackProviders() async {
    final binding = await loadBinding();
    final providers = await loadProviders();
    return orderVisionFallbackProviders(
      providers,
      binding.visionProviderId,
    );
  }

  /// 纯函数：便于单测回退顺序。
  static List<AiServiceProvider> orderVisionFallbackProviders(
    List<AiServiceProvider> providers,
    String? primaryId,
  ) {
    final ready =
        providers.where((p) => p.visionReadyForCapability).toList(growable: false);
    if (ready.isEmpty) return const [];

    final ordered = <AiServiceProvider>[];
    if (primaryId != null && primaryId.isNotEmpty) {
      for (final p in ready) {
        if (p.id == primaryId) {
          ordered.add(p);
          break;
        }
      }
    }
    for (final p in ready) {
      if (p.id != primaryId) ordered.add(p);
    }
    return ordered;
  }

  Future<AiServiceProvider> resolve(AiCapabilityKind kind) async {
    final binding = await loadBinding();
    final id = switch (kind) {
      AiCapabilityKind.text => binding.textProviderId,
      AiCapabilityKind.vision => binding.visionProviderId,
      AiCapabilityKind.voice => binding.voiceProviderId,
    };
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
    if (kind == AiCapabilityKind.voice && !provider.supportsVoice) {
      throw AiCapabilityNotReadyException(
        '「${provider.name}」未填写语音模型，请到服务商编辑页配置',
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
    if (kind == AiCapabilityKind.voice && !provider.voiceReadyForCapability) {
      throw AiCapabilityNotReadyException(
        '「${provider.name}」语音模型未通过连接测试，请到服务商编辑页保存以完成测连',
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
    String voiceModel = '',
    AiModelTestStatus textTestStatus = AiModelTestStatus.untested,
    AiModelTestStatus visionTestStatus = AiModelTestStatus.untested,
    AiModelTestStatus voiceTestStatus = AiModelTestStatus.untested,
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
      voiceModel: voiceModel,
      createdAt: DateTime.now(),
      textTestStatus: textTestStatus,
      visionTestStatus: visionTestStatus,
      voiceTestStatus: voiceTestStatus,
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
            voiceModel: provider.voiceModel,
            textTestStatus: provider.textTestStatus,
            visionTestStatus: provider.visionTestStatus,
            voiceTestStatus: provider.voiceTestStatus,
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
        '该服务商正被「文本对话」「图片理解」或「语音直接记账」使用，请先在 AI 设置中改绑后再删除',
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

  /// 导出服务商配置包文本（ADR-079）。
  Future<String> exportConfigPackage() async {
    final providers = await loadProviders();
    final binding = await loadBinding();
    return AiProviderConfigPackage(
      version: AiProviderConfigPackage.currentVersion,
      providers: providers,
      binding: binding,
    ).encode();
  }

  /// 导入服务商配置包；失败抛 [FormatException] / [AiProviderConfigPackageException]。
  Future<void> importConfigPackage(
    String raw, {
    required AiProviderImportMode mode,
  }) async {
    final pkg = AiProviderConfigPackage.parse(raw);
    final prefs = await SharedPreferences.getInstance();

    late final List<AiServiceProvider> next;
    switch (mode) {
      case AiProviderImportMode.overwrite:
        next = List<AiServiceProvider>.from(pkg.providers);
      case AiProviderImportMode.merge:
        next = _mergeProviders(await loadProviders(), pkg.providers);
        final customCount = next.where((p) => !p.isBuiltIn).length;
        if (customCount > maxCustomProviders) {
          throw AiProviderConfigPackageException(
            '合并后自定义服务商将超过 $maxCustomProviders 个，已取消导入',
          );
        }
    }

    final ensured = _withBuiltInsPresent(next);
    final customAfter = ensured.where((p) => !p.isBuiltIn).length;
    if (customAfter > maxCustomProviders) {
      throw AiProviderConfigPackageException(
        '自定义服务商最多 $maxCustomProviders 个',
      );
    }
    await _saveProviders(prefs, ensured);
    await prefs.setString(
      bindingKey,
      jsonEncode(pkg.binding.toJson()),
    );
  }

  /// 按 id 合并：已有则更新可变字段，没有则追加。
  List<AiServiceProvider> _mergeProviders(
    List<AiServiceProvider> current,
    List<AiServiceProvider> incoming,
  ) {
    final list = List<AiServiceProvider>.from(current);
    for (final raw in incoming) {
      final next = AiProviderConfigPackage.normalizeImported(raw);
      final i = list.indexWhere((p) => p.id == next.id);
      if (i < 0) {
        list.add(next);
        continue;
      }
      final existing = list[i];
      if (existing.isBuiltIn ||
          AiServiceProvider.builtInTemplate(next.id) != null) {
        list[i] = existing
            .copyWith(
              apiKey: next.apiKey,
              textModel: next.textModel,
              visionModel: next.visionModel,
              voiceModel: next.voiceModel,
              textTestStatus: next.textTestStatus,
              visionTestStatus: next.visionTestStatus,
              voiceTestStatus: next.voiceTestStatus,
              createdAt: next.createdAt,
            )
            .applyBuiltInLocks();
      } else {
        list[i] = next;
      }
    }
    return list;
  }

  Future<List<AiServiceProvider>> _ensureBuiltInsPresent(
    SharedPreferences prefs,
    List<AiServiceProvider> list,
  ) async {
    final next = _withBuiltInsPresent(list);
    final changed = next.length != list.length ||
        !_sameProviderSnapshots(list, next);
    if (changed) {
      await _saveProviders(prefs, next);
    }
    await _ensureBinding(prefs);
    return next;
  }

  /// 内存内补齐/校正内置；不落盘。
  List<AiServiceProvider> _withBuiltInsPresent(List<AiServiceProvider> list) {
    var next = List<AiServiceProvider>.from(list);

    final zhipuIndex =
        next.indexWhere((p) => p.id == AiServiceProvider.zhipuId);
    if (zhipuIndex < 0) {
      next.insert(0, AiServiceProvider.zhipuDefault);
    } else {
      var zhipu = next[zhipuIndex];
      if (zhipu.voiceModel.trim().isEmpty) {
        zhipu = zhipu.copyWith(
          voiceModel: AiServiceProvider.zhipuDefaultVoiceModel,
        );
      }
      next[zhipuIndex] = zhipu.applyBuiltInLocks();
    }

    final agnesIndex =
        next.indexWhere((p) => p.id == AiServiceProvider.agnesId);
    if (agnesIndex < 0) {
      final afterZhipu =
          next.indexWhere((p) => p.id == AiServiceProvider.zhipuId);
      final insertAt = afterZhipu >= 0 ? afterZhipu + 1 : 0;
      next.insert(insertAt, AiServiceProvider.agnesDefault);
    } else {
      next[agnesIndex] = next[agnesIndex].applyBuiltInLocks();
    }

    return next;
  }

  bool _sameProviderSnapshots(
    List<AiServiceProvider> a,
    List<AiServiceProvider> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toJson().toString() != b[i].toJson().toString()) return false;
    }
    return true;
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
      final defaults = List<AiServiceProvider>.from(
        AiServiceProvider.builtInDefaults,
      );
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
      final defaults = List<AiServiceProvider>.from(
        AiServiceProvider.builtInDefaults,
      );
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
      await _saveProviders(prefs, [
        zhipu,
        AiServiceProvider.agnesDefault,
      ]);
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
        voiceModel: '',
        createdAt: DateTime.now(),
      );
      await _saveProviders(prefs, [
        AiServiceProvider.zhipuDefault,
        AiServiceProvider.agnesDefault,
        custom,
      ]);
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
