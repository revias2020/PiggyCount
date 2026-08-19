import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v8 库升级到 v9 能为 updated_at 加上常量默认值', () async {
    final sqlite = sqlite3.openInMemory();
    sqlite.execute('''
      CREATE TABLE ledgers (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sync_id TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
    sqlite.execute('''
      CREATE TABLE categories (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        icon TEXT NULL,
        icon_type TEXT NOT NULL DEFAULT 'material',
        custom_icon_path TEXT NULL,
        parent_id INTEGER NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT NOT NULL
      );
    ''');
    sqlite.execute('''
      CREATE TABLE tag_groups (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT 'both',
        sort_order INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
    sqlite.execute('''
      CREATE TABLE tags (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        group_id INTEGER NOT NULL,
        color TEXT NOT NULL DEFAULT '#607D8B',
        range_min REAL NULL,
        range_max REAL NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
    sqlite.execute('''
      CREATE TABLE transactions (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        ledger_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        category_id INTEGER NULL,
        happened_at INTEGER NOT NULL,
        note TEXT NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        sync_id TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
    sqlite.execute(
      "INSERT INTO ledgers (name, sync_id, created_at) "
      "VALUES ('日常账本', 'ledger-sync', 1700000000)",
    );
    sqlite.execute('PRAGMA user_version = 8');

    final db = AppDatabase(NativeDatabase.opened(sqlite));
    addTearDown(db.close);

    final rows = await db.select(db.ledgers).get();
    expect(rows, hasLength(1));
    expect(
      rows.single.updatedAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: false),
    );
    expect(
      sqlite.select('PRAGMA user_version').first.columnAt(0),
      9,
    );
  });
}
