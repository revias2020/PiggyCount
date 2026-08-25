import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 后台直存传输失败、待回前台重试的条目（ADR-054）。
class PendingBillingRetryItem {
  const PendingBillingRetryItem({
    required this.imagePath,
    required this.source,
    required this.enqueuedAtMs,
  });

  final String imagePath;
  final String source;
  final int enqueuedAtMs;

  Map<String, dynamic> toJson() => {
        'imagePath': imagePath,
        'source': source,
        'enqueuedAtMs': enqueuedAtMs,
      };

  static PendingBillingRetryItem? tryParse(Map<String, dynamic> json) {
    final path = json['imagePath'];
    final source = json['source'];
    final at = json['enqueuedAtMs'];
    if (path is! String || path.isEmpty) return null;
    if (source is! String || source.isEmpty) return null;
    if (at is! int) return null;
    return PendingBillingRetryItem(
      imagePath: path,
      source: source,
      enqueuedAtMs: at,
    );
  }
}

/// 本机持久化待重试队列。
class PendingBillingRetryStore {
  static const _key = 'piggy_pending_billing_retries';
  static const _maxItems = 20;

  Future<List<PendingBillingRetryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null || raw.isEmpty) return const [];
    final out = <PendingBillingRetryItem>[];
    for (final line in raw) {
      try {
        final map = jsonDecode(line) as Map<String, dynamic>;
        final item = PendingBillingRetryItem.tryParse(map);
        if (item != null) out.add(item);
      } catch (_) {}
    }
    return out;
  }

  Future<void> enqueue(PendingBillingRetryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final filtered = [
      for (final e in list)
        if (e.imagePath != item.imagePath) e,
    ];
    filtered.add(item);
    final trimmed = filtered.length > _maxItems
        ? filtered.sublist(filtered.length - _maxItems)
        : filtered;
    await prefs.setStringList(
      _key,
      [for (final e in trimmed) jsonEncode(e.toJson())],
    );
  }

  Future<void> remove(String imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final next = [
      for (final e in list)
        if (e.imagePath != imagePath) e,
    ];
    if (next.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setStringList(
      _key,
      [for (final e in next) jsonEncode(e.toJson())],
    );
  }
}
