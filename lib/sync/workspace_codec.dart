import 'workspace_models.dart';

/// 工作区 JSON 编解码。远端文件 `piggy_workspace.json`（ADR-042）。
abstract final class WorkspaceCodec {
  static const version = 2;

  static Map<String, Object?> encode(WorkspaceSnapshot snap) {
    return {
      'version': version,
      'ledgers': [
        for (final e in snap.ledgers)
          {
            'syncId': e.syncId,
            'name': e.name,
            'updatedAt': _iso(e.updatedAt),
            'deletedAt': _iso(e.deletedAt),
          },
      ],
      'categories': [
        for (final e in snap.categories)
          {
            'syncId': e.syncId,
            'name': e.name,
            'kind': e.kind,
            'parentSyncId': e.parentSyncId,
            'icon': e.icon,
            'iconType': e.iconType,
            'sortOrder': e.sortOrder,
            'updatedAt': _iso(e.updatedAt),
            'deletedAt': _iso(e.deletedAt),
          },
      ],
      'tagGroups': [
        for (final e in snap.tagGroups)
          {
            'syncId': e.syncId,
            'name': e.name,
            'kind': e.kind,
            'scope': e.scope,
            'sortOrder': e.sortOrder,
            'updatedAt': _iso(e.updatedAt),
            'deletedAt': _iso(e.deletedAt),
          },
      ],
      'tags': [
        for (final e in snap.tags)
          {
            'syncId': e.syncId,
            'name': e.name,
            'groupSyncId': e.groupSyncId,
            'color': e.color,
            'rangeMin': e.rangeMin,
            'rangeMax': e.rangeMax,
            'sortOrder': e.sortOrder,
            'updatedAt': _iso(e.updatedAt),
            'deletedAt': _iso(e.deletedAt),
          },
      ],
      'bills': [
        for (final e in snap.bills)
          {
            'syncId': e.syncId,
            'fingerprint': e.fingerprint,
            'ledgerSyncId': e.ledgerSyncId,
            'type': e.type,
            'amount': e.amount,
            'happenedAt': _iso(e.happenedAt),
            'categoryName': e.categoryName,
            'note': e.note,
            'tagNames': e.tagNames,
            'source': e.source,
            'updatedAt': _iso(e.updatedAt),
            'deletedAt': _iso(e.deletedAt),
          },
      ],
    };
  }

  static WorkspaceSnapshot decode(Map<String, Object?> json) {
    List<Map<String, Object?>> list(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map) Map<String, Object?>.from(e),
      ];
    }

    return WorkspaceSnapshot(
      ledgers: [
        for (final e in list('ledgers'))
          SyncLedger(
            syncId: e['syncId'] as String,
            name: e['name'] as String,
            updatedAt: _dt(e['updatedAt']),
            deletedAt: _dtn(e['deletedAt']),
          ),
      ],
      categories: [
        for (final e in list('categories'))
          SyncCategory(
            syncId: e['syncId'] as String,
            name: e['name'] as String,
            kind: e['kind'] as String,
            parentSyncId: e['parentSyncId'] as String?,
            icon: e['icon'] as String?,
            iconType: (e['iconType'] as String?) ?? 'material',
            sortOrder: (e['sortOrder'] as num?)?.toInt() ?? 0,
            updatedAt: _dt(e['updatedAt']),
            deletedAt: _dtn(e['deletedAt']),
          ),
      ],
      tagGroups: [
        for (final e in list('tagGroups'))
          SyncTagGroup(
            syncId: e['syncId'] as String,
            name: e['name'] as String,
            kind: e['kind'] as String,
            scope: (e['scope'] as String?) ?? 'both',
            sortOrder: (e['sortOrder'] as num?)?.toInt() ?? 0,
            updatedAt: _dt(e['updatedAt']),
            deletedAt: _dtn(e['deletedAt']),
          ),
      ],
      tags: [
        for (final e in list('tags'))
          SyncTag(
            syncId: e['syncId'] as String,
            name: e['name'] as String,
            groupSyncId: e['groupSyncId'] as String,
            color: e['color'] as String?,
            rangeMin: (e['rangeMin'] as num?)?.toDouble(),
            rangeMax: (e['rangeMax'] as num?)?.toDouble(),
            sortOrder: (e['sortOrder'] as num?)?.toInt() ?? 0,
            updatedAt: _dt(e['updatedAt']),
            deletedAt: _dtn(e['deletedAt']),
          ),
      ],
      bills: [
        for (final e in list('bills'))
          SyncBill(
            syncId: (e['syncId'] as String?) ?? (e['fingerprint'] as String),
            fingerprint: e['fingerprint'] as String,
            ledgerSyncId: e['ledgerSyncId'] as String,
            type: e['type'] as String,
            amount: (e['amount'] as num).toDouble(),
            happenedAt: _dt(e['happenedAt']),
            categoryName: e['categoryName'] as String?,
            note: e['note'] as String?,
            tagNames: [
              for (final n in (e['tagNames'] as List? ?? const []))
                if (n is String) n,
            ],
            source: (e['source'] as String?) ?? 'manual',
            updatedAt: _dt(e['updatedAt']),
            deletedAt: _dtn(e['deletedAt']),
          ),
      ],
    );
  }

  static String? _iso(DateTime? value) => value?.toIso8601String();

  static DateTime _dt(Object? value) => DateTime.parse(value as String);

  static DateTime? _dtn(Object? value) {
    if (value == null) return null;
    return DateTime.parse(value as String);
  }
}
