import 'dart:convert';

import '../app_database.dart';
import '../../utils/screenshot_watch_path.dart';

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

  static const screenshotWatchDirsKey = 'screenshot_watch_directories';

  /// 截图自动记账监听目录（相对路径列表，如 `Pictures/Screenshots`；ADR-070）。
  Future<List<String>> screenshotWatchDirectories() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(screenshotWatchDirsKey)))
        .getSingleOrNull();
    return _decodeWatchDirs(row?.value);
  }

  Stream<List<String>> watchScreenshotWatchDirectories() {
    return (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(screenshotWatchDirsKey)))
        .watch()
        .map((rows) => _decodeWatchDirs(rows.isEmpty ? null : rows.first.value));
  }

  /// 是否已写入过监听目录设置（含空列表；用于区分「从未扫描」）。
  Future<bool> hasScreenshotWatchDirectoriesSetting() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(screenshotWatchDirsKey)))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> setScreenshotWatchDirectories(List<String> dirs) async {
    final cleaned = <String>[];
    final seen = <String>{};
    for (final raw in dirs) {
      final n = ScreenshotWatchPath.normalize(raw);
      if (n == null) continue;
      final key = n.toLowerCase();
      if (!seen.add(key)) continue;
      cleaned.add(n);
    }
    cleaned.sort();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: screenshotWatchDirsKey,
            value: jsonEncode(cleaned),
          ),
        );
  }

  static List<String> _decodeWatchDirs(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <String>[];
      final seen = <String>{};
      for (final item in decoded.whereType<String>()) {
        final n = ScreenshotWatchPath.normalize(item);
        if (n == null) continue;
        if (!seen.add(n.toLowerCase())) continue;
        out.add(n);
      }
      out.sort();
      return out;
    } catch (_) {
      return const [];
    }
  }
}
