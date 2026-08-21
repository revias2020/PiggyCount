import '../app_database.dart';

/// 应用设置（智能记账开关等）读写。
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const autoGenerateTagsKey = 'auto_generate_tags';

  /// 智能记账是否允许创建新标签（默认 true）。
  Future<bool> autoGenerateTags() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(autoGenerateTagsKey)))
        .getSingleOrNull();
    if (row == null) return true;
    return row.value != '0' && row.value != 'false';
  }

  Stream<bool> watchAutoGenerateTags() {
    return (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(autoGenerateTagsKey)))
        .watch()
        .map((rows) {
      if (rows.isEmpty) return true;
      final v = rows.first.value;
      return v != '0' && v != 'false';
    });
  }

  Future<void> setAutoGenerateTags(bool enabled) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: autoGenerateTagsKey,
            value: enabled ? '1' : '0',
          ),
        );
  }

  static const screenshotAutoKey = 'screenshot_auto_billing';

  /// 截图自动记账开关（默认关闭）。Android 真机监听见 Phase 4 后续原生通道；
  /// 当前开启后可通过「选择截图识别」手动触发同一 Vision 管道。
  Future<bool> screenshotAutoBilling() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(screenshotAutoKey)))
        .getSingleOrNull();
    if (row == null) return false;
    return row.value == '1' || row.value == 'true';
  }

  Stream<bool> watchScreenshotAutoBilling() {
    return (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(screenshotAutoKey)))
        .watch()
        .map((rows) {
      if (rows.isEmpty) return false;
      final v = rows.first.value;
      return v == '1' || v == 'true';
    });
  }

  Future<void> setScreenshotAutoBilling(bool enabled) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: screenshotAutoKey,
            value: enabled ? '1' : '0',
          ),
        );
  }

}
