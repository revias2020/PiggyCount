/// 拼装 Prompt 所需的用户上下文（无账户；分类按主类分组，ADR-047）。
class AiExtractionContext {
  const AiExtractionContext({
    this.expenseGroups = const [],
    this.incomeGroups = const [],
    this.tagGroups = const [],
  });

  final List<AiCategoryGroupHint> expenseGroups;
  final List<AiCategoryGroupHint> incomeGroups;
  final List<AiTagGroupHint> tagGroups;

  static const AiExtractionContext fallback = AiExtractionContext();
}

/// 一个主类及其子类名（prompt 分组用）。
class AiCategoryGroupHint {
  const AiCategoryGroupHint({
    required this.mainName,
    this.childNames = const [],
  });

  final String mainName;
  final List<String> childNames;
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
