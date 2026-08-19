import 'package:uuid/uuid.dart';

import 'app_database.dart';

/// 首次启动：默认账本与当前账本设置。
///
/// 出厂分类／标签仅在数据库 [MigrationStrategy.onCreate] 导入（ADR-039），
/// 本服务不再每次启动补缺。
class SeedService {
  SeedService(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<void> ensureSeeded() async {
    final existing = await _db.select(_db.ledgers).get();
    if (existing.isEmpty) {
      await _db.into(_db.ledgers).insert(
            LedgersCompanion.insert(
              name: '日常账本',
              syncId: _uuid.v4(),
            ),
          );
    }

    final settings = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals('current_ledger_id')))
        .get();
    if (settings.isEmpty) {
      final ledgers = await _db.select(_db.ledgers).get();
      if (ledgers.isNotEmpty) {
        await _db.into(_db.appSettings).insert(
              AppSettingsCompanion.insert(
                key: 'current_ledger_id',
                value: '${ledgers.first.id}',
              ),
            );
      }
    }
  }
}
