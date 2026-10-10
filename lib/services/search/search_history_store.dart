import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 明细搜索关键词历史条目。
class SearchHistoryEntry {
  const SearchHistoryEntry({
    required this.keyword,
    required this.searchedAt,
  });

  final String keyword;
  final DateTime searchedAt;

  Map<String, Object?> toJson() => {
        'keyword': keyword,
        'searchedAt': searchedAt.toIso8601String(),
      };

  static SearchHistoryEntry? fromJson(Map<String, dynamic> json) {
    final keyword = (json['keyword'] as String?)?.trim();
    if (keyword == null || keyword.isEmpty) return null;
    final raw = json['searchedAt'] as String?;
    final searchedAt =
        raw == null ? DateTime.now() : DateTime.tryParse(raw) ?? DateTime.now();
    return SearchHistoryEntry(keyword: keyword, searchedAt: searchedAt);
  }
}

/// SharedPreferences 存搜索关键词历史（本机、不进云同步）。
class SearchHistoryStore {
  static const _key = 'piggy_search_keyword_history_v1';
  static const maxAge = Duration(days: 7);
  static const maxCount = 20;

  Future<List<SearchHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <SearchHistoryEntry>[];
      for (final item in list) {
        if (item is! Map) continue;
        final e = SearchHistoryEntry.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (e != null) out.add(e);
      }
      return _prune(out);
    } catch (_) {
      return const [];
    }
  }

  /// 写入非空关键词；同词（忽略大小写）置顶并刷新时间。
  Future<List<SearchHistoryEntry>> add(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return load();

    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final key = trimmed.toLowerCase();
    final next = <SearchHistoryEntry>[
      SearchHistoryEntry(keyword: trimmed, searchedAt: DateTime.now()),
      ...current.where((e) => e.keyword.toLowerCase() != key),
    ];
    final pruned = _prune(next);
    await prefs.setString(
      _key,
      jsonEncode(pruned.map((e) => e.toJson()).toList()),
    );
    return pruned;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  List<SearchHistoryEntry> _prune(List<SearchHistoryEntry> entries) {
    final cutoff = DateTime.now().subtract(maxAge);
    final fresh = entries.where((e) => !e.searchedAt.isBefore(cutoff)).toList()
      ..sort((a, b) => b.searchedAt.compareTo(a.searchedAt));
    if (fresh.length <= maxCount) return fresh;
    return fresh.sublist(0, maxCount);
  }
}
