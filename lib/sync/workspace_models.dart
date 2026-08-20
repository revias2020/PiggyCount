/// 同步工作区快照与预览（纯数据，不含 Drift）。ADR-042。

class SyncPreviewCounts {
  const SyncPreviewCounts({
    this.added = 0,
    this.updated = 0,
    this.deleted = 0,
  });

  final int added;
  final int updated;
  final int deleted;

  bool get isEmpty => added == 0 && updated == 0 && deleted == 0;
}

class SyncPreview {
  const SyncPreview({
    required this.catalog,
    required this.ledgers,
    required this.bills,
    this.duplicates = const [],
    this.categoryTreeConflict,
  });

  final SyncPreviewCounts catalog;
  final SyncPreviewCounts ledgers;
  final SyncPreviewCounts bills;

  /// 不同账单身份、相同账单指纹的疑似重复（ADR-044）。
  final List<BillDuplicateGroup> duplicates;

  /// 目标树不合法、已强制子变主时的说明。
  final String? categoryTreeConflict;
}

/// 预览里一组可折合的疑似重复账单。
class BillDuplicateGroup {
  const BillDuplicateGroup({
    required this.fingerprint,
    required this.bills,
  });

  final String fingerprint;
  final List<SyncBill> bills;
}

class SyncLedger {
  const SyncLedger({
    required this.syncId,
    required this.name,
    required this.updatedAt,
    this.deletedAt,
  });

  final String syncId;
  final String name;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLive => deletedAt == null;

  SyncLedger copyWith({
    String? syncId,
    String? name,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return SyncLedger(
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

class SyncCategory {
  const SyncCategory({
    required this.syncId,
    required this.name,
    required this.kind,
    this.parentSyncId,
    this.icon,
    this.iconType = 'material',
    this.sortOrder = 0,
    required this.updatedAt,
    this.deletedAt,
  });

  final String syncId;
  final String name;
  final String kind;
  final String? parentSyncId;
  final String? icon;
  final String iconType;
  final int sortOrder;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLive => deletedAt == null;

  SyncCategory copyWith({
    String? syncId,
    String? name,
    String? kind,
    String? parentSyncId,
    bool clearParent = false,
    String? icon,
    String? iconType,
    int? sortOrder,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return SyncCategory(
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      parentSyncId: clearParent ? null : (parentSyncId ?? this.parentSyncId),
      icon: icon ?? this.icon,
      iconType: iconType ?? this.iconType,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

class SyncTagGroup {
  const SyncTagGroup({
    required this.syncId,
    required this.name,
    required this.kind,
    this.scope = 'both',
    this.sortOrder = 0,
    required this.updatedAt,
    this.deletedAt,
  });

  final String syncId;
  final String name;
  final String kind;
  final String scope;
  final int sortOrder;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLive => deletedAt == null;

  SyncTagGroup copyWith({
    String? syncId,
    String? name,
    String? kind,
    String? scope,
    int? sortOrder,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return SyncTagGroup(
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      scope: scope ?? this.scope,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

class SyncTag {
  const SyncTag({
    required this.syncId,
    required this.name,
    required this.groupSyncId,
    this.color,
    this.rangeMin,
    this.rangeMax,
    this.sortOrder = 0,
    required this.updatedAt,
    this.deletedAt,
  });

  final String syncId;
  final String name;
  final String groupSyncId;
  final String? color;
  final double? rangeMin;
  final double? rangeMax;
  final int sortOrder;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLive => deletedAt == null;

  SyncTag copyWith({
    String? syncId,
    String? name,
    String? groupSyncId,
    String? color,
    double? rangeMin,
    double? rangeMax,
    int? sortOrder,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return SyncTag(
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      groupSyncId: groupSyncId ?? this.groupSyncId,
      color: color ?? this.color,
      rangeMin: rangeMin ?? this.rangeMin,
      rangeMax: rangeMax ?? this.rangeMax,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

class SyncBill {
  const SyncBill({
    required this.syncId,
    required this.fingerprint,
    required this.ledgerSyncId,
    required this.type,
    required this.amount,
    required this.happenedAt,
    this.categoryName,
    this.note,
    this.tagNames = const [],
    this.source = 'manual',
    required this.updatedAt,
    this.deletedAt,
  });

  /// 跨设备账单身份（创建时 UUID，ADR-044）。
  final String syncId;
  final String fingerprint;
  final String ledgerSyncId;
  final String type;
  final double amount;
  final DateTime happenedAt;
  final String? categoryName;
  final String? note;
  final List<String> tagNames;
  final String source;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isLive => deletedAt == null;

  SyncBill copyWith({
    String? syncId,
    String? fingerprint,
    String? ledgerSyncId,
    String? type,
    double? amount,
    DateTime? happenedAt,
    String? categoryName,
    String? note,
    List<String>? tagNames,
    String? source,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return SyncBill(
      syncId: syncId ?? this.syncId,
      fingerprint: fingerprint ?? this.fingerprint,
      ledgerSyncId: ledgerSyncId ?? this.ledgerSyncId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      happenedAt: happenedAt ?? this.happenedAt,
      categoryName: categoryName ?? this.categoryName,
      note: note ?? this.note,
      tagNames: tagNames ?? this.tagNames,
      source: source ?? this.source,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    this.ledgers = const [],
    this.categories = const [],
    this.tagGroups = const [],
    this.tags = const [],
    this.bills = const [],
  });

  final List<SyncLedger> ledgers;
  final List<SyncCategory> categories;
  final List<SyncTagGroup> tagGroups;
  final List<SyncTag> tags;
  final List<SyncBill> bills;

  WorkspaceSnapshot copyWith({
    List<SyncLedger>? ledgers,
    List<SyncCategory>? categories,
    List<SyncTagGroup>? tagGroups,
    List<SyncTag>? tags,
    List<SyncBill>? bills,
  }) {
    return WorkspaceSnapshot(
      ledgers: ledgers ?? this.ledgers,
      categories: categories ?? this.categories,
      tagGroups: tagGroups ?? this.tagGroups,
      tags: tags ?? this.tags,
      bills: bills ?? this.bills,
    );
  }
}

class WorkspaceMergeResult {
  const WorkspaceMergeResult({
    required this.merged,
    required this.preview,
  });

  final WorkspaceSnapshot merged;
  final SyncPreview preview;
}
