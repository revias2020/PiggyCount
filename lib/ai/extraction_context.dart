/// 拼装 Prompt 所需的用户上下文（无账户；分类名列表即可）。
class AiExtractionContext {
  const AiExtractionContext({
    this.expenseCategories = const [],
    this.incomeCategories = const [],
    this.tagGroups = const [],
  });

  final List<String> expenseCategories;
  final List<String> incomeCategories;
  final List<AiTagGroupHint> tagGroups;

  static const AiExtractionContext fallback = AiExtractionContext();
}

/// Prompt 里描述一个标签组。
class AiTagGroupHint {
  const AiTagGroupHint({
    required this.name,
    required this.kind,
    this.scope = 'both',
    this.tags = const [],
  });

  final String name;
  /// `string` | `number`
  final String kind;
  /// `both` | `expense` | `income`
  final String scope;
  final List<AiTagHint> tags;

  List<String> get tagLabels => [for (final t in tags) t.label];
}

class AiTagHint {
  const AiTagHint({required this.name, this.rangeLabel});

  final String name;
  final String? rangeLabel;

  String get label =>
      rangeLabel == null || rangeLabel!.isEmpty ? name : '$name($rangeLabel)';
}
