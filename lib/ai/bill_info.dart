/// AI 提取的账单模型（无账户/转账；金额存绝对值，类型单独字段）。
enum BillType { expense, income }

/// AI 建议的标签（可带组名，供自动建标）。
class SuggestedTag {
  const SuggestedTag({required this.name, this.groupName});

  final String name;
  final String? groupName;
}

class BillInfo {
  const BillInfo({
    this.amount,
    this.time,
    this.note,
    this.category,
    this.type,
    this.tags,
    this.confidence = 0.0,
  });

  /// 正数金额；符号由 [type] 决定。
  final double? amount;
  final DateTime? time;
  final String? note;
  final String? category;
  final BillType? type;
  final List<SuggestedTag>? tags;
  final double confidence;

  BillInfo copyWith({
    double? amount,
    DateTime? time,
    String? note,
    String? category,
    BillType? type,
    List<SuggestedTag>? tags,
    double? confidence,
  }) {
    return BillInfo(
      amount: amount ?? this.amount,
      time: time ?? this.time,
      note: note ?? this.note,
      category: category ?? this.category,
      type: type ?? this.type,
      tags: tags ?? this.tags,
      confidence: confidence ?? this.confidence,
    );
  }

  factory BillInfo.fromJson(Map<String, dynamic> json) {
    final rawAmount = _parseDouble(json['amount']);
    BillType? type = _parseBillType(json['type']);
    double? amount = rawAmount;
    // AI 常把支出写成负数：转成绝对值并推断类型。
    if (amount != null && amount < 0) {
      amount = amount.abs();
      type ??= BillType.expense;
    } else if (amount != null && amount > 0 && type == null) {
      type = BillType.expense;
    }

    return BillInfo(
      amount: amount,
      time: _parseTime(json['time']),
      note: json['note'] as String? ?? json['merchant'] as String?,
      category: json['category'] as String?,
      type: type,
      tags: _parseTags(json['tags'] ?? json['tag']),
      confidence: _parseDouble(json['confidence']) ?? 0.8,
    );
  }

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'time': time?.toIso8601String(),
        'note': note,
        'category': category,
        'type': type?.name,
        'tags': [
          for (final t in tags ?? const <SuggestedTag>[])
            if (t.groupName != null && t.groupName!.isNotEmpty)
              {'group': t.groupName, 'name': t.name}
            else
              t.name,
        ],
        'confidence': confidence,
      };

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[,，\s¥￥]'), '');
      if (cleaned.isEmpty) return null;
      return double.tryParse(cleaned);
    }
    return null;
  }

  static DateTime? _parseTime(dynamic value) {
    if (value is! String) return null;
    final raw = value.trim();
    if (raw.isEmpty) return null;
    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;
    final stripped = DateTime.tryParse(raw.replaceAll(RegExp(r'\s+'), ''));
    if (stripped != null) return stripped;
    final m = RegExp(
      r'(\d{4})\s*[年./-]\s*(\d{1,2})\s*[月./-]\s*(\d{1,2})\s*日?'
      r'(?:[\sT]+(\d{1,2})\s*[:时点]\s*(\d{1,2})(?:\s*[:分]\s*(\d{1,2}))?)?',
    ).firstMatch(raw);
    if (m == null) return null;
    int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
    final month = g(2);
    final day = g(3);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(g(1), month, day, g(4), g(5), g(6));
  }

  static BillType? _parseBillType(dynamic value) {
    if (value == null) return null;
    final str = value.toString().toLowerCase();
    if (str.contains('income') || str == '收入') return BillType.income;
    if (str.contains('expense') || str == '支出') return BillType.expense;
    return null;
  }

  static List<SuggestedTag>? _parseTags(dynamic value) {
    if (value == null) return null;
    final tags = <SuggestedTag>[];
    void addRaw(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return;
      final slash = s.indexOf('/');
      final colon = s.indexOf(':');
      final sep = slash >= 0
          ? slash
          : (colon >= 0 ? colon : -1);
      if (sep > 0 && sep < s.length - 1) {
        tags.add(
          SuggestedTag(
            groupName: s.substring(0, sep).trim(),
            name: s.substring(sep + 1).trim(),
          ),
        );
      } else {
        tags.add(SuggestedTag(name: s));
      }
    }

    if (value is String) {
      for (final part in value.split(RegExp(r'[,\n，、;；|]+'))) {
        addRaw(part);
      }
    } else if (value is List) {
      for (final e in value) {
        if (e is Map) {
          final name = (e['name'] ?? e['tag'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final group = (e['group'] ?? e['groupName'] ?? '').toString().trim();
          tags.add(
            SuggestedTag(
              name: name,
              groupName: group.isEmpty ? null : group,
            ),
          );
        } else {
          addRaw(e.toString());
        }
      }
    }
    return tags.isEmpty ? null : tags;
  }
}
