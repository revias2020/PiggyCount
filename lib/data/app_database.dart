import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// 小猪记账本地数据库。
///
/// 打开方式见 [AppDatabase.open]；业务访问请走 Repository，避免页面直接拼 SQL。
@DriftDatabase(
  tables: [
    Ledgers,
    Categories,
    TagGroups,
    Tags,
    Transactions,
    TransactionTags,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _insertDefaultTagGroup();
        },
        onUpgrade: (m, from, to) async {
          // v2 曾尝试拍平树；v3 起恢复两层树产品语义，表结构不变。
          if (from < 3) {
            await into(appSettings).insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: 'categories_flattened_v2',
                value: 'skip',
              ),
            );
          }
          if (from < 4) {
            await m.addColumn(categories, categories.iconType);
            await m.addColumn(categories, categories.customIconPath);
          }
          if (from < 5) {
            await m.createTable(tagGroups);
            final defaultGroupId = await _insertDefaultTagGroup();
            await customStatement(
              'ALTER TABLE tags ADD COLUMN group_id INTEGER NOT NULL '
              'DEFAULT $defaultGroupId',
            );
            await customStatement(
              'ALTER TABLE tags ADD COLUMN range_min REAL NULL',
            );
            await customStatement(
              'ALTER TABLE tags ADD COLUMN range_max REAL NULL',
            );
            await customStatement(
              'ALTER TABLE tags ADD COLUMN sort_order INTEGER NOT NULL '
              'DEFAULT 0',
            );
          }
        },
      );

  Future<int> _insertDefaultTagGroup() {
    return into(tagGroups).insert(
      TagGroupsCompanion.insert(
        name: '默认',
        kind: TagGroupKind.string,
        syncId: const Uuid().v4(),
      ),
    );
  }

  /// 在应用文档目录创建/打开 `piggy_count.sqlite`。
  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'piggy_count.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  /// 测试用内存库，避免污染真机数据。
  static AppDatabase memory() => AppDatabase(NativeDatabase.memory());
}

/// 标签组类型常量（存 [TagGroups.kind]）。
abstract final class TagGroupKind {
  static const string = 'string';
  static const number = 'number';
}
