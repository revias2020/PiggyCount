import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai_config.dart';

/// AI 配置本地存储（密钥只在本机 prefs，不入库、不进 git）。
class AiConfigStore {
  static const _key = 'ai_config_v1';

  Future<AiConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return AiConfig.zhipu();
    try {
      return AiConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AiConfig.zhipu();
    }
  }

  Future<void> save(AiConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }
}
