import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'default_catalog_applier.dart';
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
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // ADR-039：出厂分类／标签仅在新库导入一次，之后启动不再补缺。
          final applier = DefaultCatalogApplier(this);
          await applier.ensureCategories();
          await applier.ensureTags();
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
            // 历史路径：旧 tags 无 group_id，临时挂「默认」；空组由 v8 清理。
            final defaultGroupId = await _insertLegacyDefaultTagGroup();
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
          if (from < 6 && from >= 5) {
            await m.addColumn(tagGroups, tagGroups.scope);
          }
          if (from < 7) {
            await customStatement(
              "ALTER TABLE tags ADD COLUMN color TEXT NOT NULL "
              "DEFAULT '#607D8B'",
            );
            await _backfillTagColors();
          }
          if (from < 8) {
            await _deleteEmptyLegacyDefaultTagGroup();
          }
          if (from < 9) {
            await _migrateSyncWorkspaceV9(m);
          }
        },
      );

  /// ADR-042：较晚改动、墓碑、账单指纹。
  Future<void> _migrateSyncWorkspaceV9(Migrator m) async {
    // SQLite 禁止 ALTER TABLE 给新列使用 CURRENT_TIMESTAMP 等非常量默认值。
    await _addUpdatedAtColumn('ledgers');
    await m.addColumn(ledgers, ledgers.deletedAt);
    await _addUpdatedAtColumn('categories');
    await m.addColumn(categories, categories.deletedAt);
    await _addUpdatedAtColumn('tag_groups');
    await m.addColumn(tagGroups, tagGroups.deletedAt);
    await _addUpdatedAtColumn('tags');
    await m.addColumn(tags, tags.deletedAt);
    await customStatement(
      "ALTER TABLE transactions ADD COLUMN fingerprint TEXT NOT NULL DEFAULT ''",
    );
    await _addUpdatedAtColumn('transactions');
    await m.addColumn(transactions, transactions.deletedAt);
    await _backfillUpdatedAt();
    await _backfillTransactionFingerprints();
  }

  Future<void> _addUpdatedAtColumn(String table) async {
    await customStatement(
      'ALTER TABLE $table ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _backfillUpdatedAt() async {
    await customStatement('UPDATE ledgers SET updated_at = created_at');
    await customStatement('UPDATE tag_groups SET updated_at = created_at');
    await customStatement('UPDATE tags SET updated_at = created_at');
    await customStatement('UPDATE transactions SET updated_at = created_at');
    await customStatement(
      "UPDATE categories SET updated_at = "
      "CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)",
    );
  }

  Future<void> _backfillTransactionFingerprints() async {
    final rows = await customSelect(
      'SELECT t.id AS id, t.amount AS amount, t.happened_at AS happened_at, '
      'l.sync_id AS ledger_sync '
      'FROM transactions t JOIN ledgers l ON l.id = t.ledger_id',
      readsFrom: {transactions, ledgers},
    ).get();
    for (final row in rows) {
      final id = row.read<int>('id');
      final amount = row.read<double>('amount');
      final happened = row.read<DateTime>('happened_at');
      final ledgerSync = row.read<String>('ledger_sync');
      final cents = (amount * 100).round();
      final amt = (cents / 100).toStringAsFixed(2);
      final t = DateTime(
        happened.year,
        happened.month,
        happened.day,
        happened.hour,
        happened.minute,
        happened.second,
      );
      final iso =
          '${t.year.toString().padLeft(4, '0')}-'
          '${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')}T'
          '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}:'
          '${t.second.toString().padLeft(2, '0')}';
      final fp = '$ledgerSync|$amt|$iso';
      await customStatement(
        'UPDATE transactions SET fingerprint = ? WHERE id = ?',
        [fp, id],
      );
    }
  }

  /// 存量标签按色板轮询补色（ADR-017）。
  Future<void> _backfillTagColors() async {
    const palette = [
      '#FF5722',
      '#E91E63',
      '#9C27B0',
      '#673AB7',
      '#3F51B5',
      '#2196F3',
      '#03A9F4',
      '#00BCD4',
      '#009688',
      '#4CAF50',
      '#8BC34A',
      '#CDDC39',
      '#FFC107',
      '#FF9800',
      '#795548',
      '#607D8B',
      '#F44336',
      '#00E676',
      '#FF4081',
      '#536DFE',
    ];
    final rows = await select(tags).get();
    for (var i = 0; i < rows.length; i++) {
      await (update(tags)..where((t) => t.id.equals(rows[i].id))).write(
            TagsCompanion(color: Value(palette[i % palette.length])),
          );
    }
  }

  /// 仅供 v5 升级给旧 tags 挂 group_id（ADR-031 后新装不再使用）。
  Future<int> _insertLegacyDefaultTagGroup() {
    return into(tagGroups).insert(
      TagGroupsCompanion.insert(
        name: '默认',
        kind: TagGroupKind.string,
        syncId: const Uuid().v4(),
      ),
    );
  }

  /// ADR-031：删除名为「默认」且组内无标签的遗留组。
  Future<void> _deleteEmptyLegacyDefaultTagGroup() async {
    final groups = await (select(tagGroups)
          ..where((g) => g.name.equals('默认')))
        .get();
    for (final g in groups) {
      final members =
          await (select(tags)..where((t) => t.groupId.equals(g.id))).get();
      if (members.isEmpty) {
        await (delete(tagGroups)..where((x) => x.id.equals(g.id))).go();
      }
    }
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

/// 标签组生效范围（存 [TagGroups.scope]）。
abstract final class TagGroupScope {
  static const both = 'both';
  static const expense = 'expense';
  static const income = 'income';

  static bool matchesType(String scope, String transactionType) {
    if (scope == both) return true;
    return scope == transactionType;
  }

  static String label(String scope) {
    switch (scope) {
      case expense:
        return '仅支出';
      case income:
        return '仅收入';
      default:
        return '全部';
    }
  }
}
