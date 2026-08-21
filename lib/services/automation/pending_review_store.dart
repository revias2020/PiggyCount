import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本机持久的待核对条目（ADR-050）。
class PendingReviewEntry {
  const PendingReviewEntry({
    required this.syncId,
    required this.ledgerId,
    required this.happenedAt,
  });

  final String syncId;
  final int ledgerId;
  final DateTime happenedAt;

  Map<String, Object?> toJson() => {
        'syncId': syncId,
        'ledgerId': ledgerId,
        'happenedAt': happenedAt.toIso8601String(),
      };

  static PendingReviewEntry? fromJson(Map<String, dynamic> json) {
    final syncId = json['syncId'] as String?;
    final ledgerId = json['ledgerId'];
    final happenedAtRaw = json['happenedAt'] as String?;
    if (syncId == null || syncId.isEmpty || ledgerId is! int) return null;
    final happenedAt = happenedAtRaw == null
        ? DateTime.now()
        : DateTime.tryParse(happenedAtRaw) ?? DateTime.now();
    return PendingReviewEntry(
      syncId: syncId,
      ledgerId: ledgerId,
      happenedAt: happenedAt,
    );
  }
}

/// SharedPreferences 存待核对集合（不进云同步）。
class PendingReviewStore {
  static const _key = 'piggy_pending_review_v1';

  Future<List<PendingReviewEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <PendingReviewEntry>[];
      for (final item in list) {
        if (item is! Map) continue;
        final e = PendingReviewEntry.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (e != null) out.add(e);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<PendingReviewEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }
}
