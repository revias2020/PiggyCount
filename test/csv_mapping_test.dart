import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:piggy_count/data/repositories/category_repository.dart';
import 'package:piggy_count/data/repositories/ledger_repository.dart';
import 'package:piggy_count/data/repositories/tag_repository.dart';
import 'package:piggy_count/data/repositories/transaction_repository.dart';
import 'package:piggy_count/data/seed_service.dart';
import 'package:piggy_count/services/csv/csv_codec.dart';
import 'package:piggy_count/services/csv/csv_import_mapping.dart';
import 'package:piggy_count/services/csv/csv_service.dart';
import 'package:piggy_count/services/csv/csv_table.dart';

void main() {
  test('首行同时含日期和金额视为无表头', () {
    expect(
      CsvTable.looksLikeDataRow(['2024-01-01', '支出', '12.50']),
      isTrue,
    );
    expect(
      CsvTable.looksLikeDataRow(['日期时间', '类型', '金额', '主分类']),
      isFalse,
    );
    expect(
      () => CsvTable.parse('2024-01-01,支出,12.50\n2024-01-02,收入,3'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          CsvTable.noHeaderMessage,
        ),
      ),
    );
  });

  test('表头别名预填列名映射', () {
    final mapping = ColumnMapping.guess(
      ['交易时间', '收/支', '金额', '分类', '备注'],
    );
    expect(mapping[CsvImportField.happenedAt], '交易时间');
    expect(mapping[CsvImportField.type], '收/支');
    expect(mapping[CsvImportField.amount], '金额');
    expect(mapping[CsvImportField.primaryCategory], '分类');
    expect(mapping[CsvImportField.note], '备注');
    expect(mapping.isReady, isTrue);
  });

  test('金额解析去掉货币符号', () {
    expect(CsvCodec.parseAmount('¥12.50'), 12.5);
    expect(CsvCodec.parseAmount('1,234.00'), 1234);
  });

  late AppDatabase db;
  late CsvService csv;
  late int ledgerId;
  late CategoryRepository cats;
  late TagRepository tagRepo;

  setUp(() async {
    db = AppDatabase.memory();
    await SeedService(db).ensureSeeded();
    final ledgers = LedgerRepository(db);
    ledgerId = (await ledgers.getAll()).first.id;
    cats = CategoryRepository(db);
    tagRepo = TagRepository(db);
    csv = CsvService(
      ledgers: ledgers,
      categories: cats,
      tags: tagRepo,
      transactions: TransactionRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('按列名映射导入，列顺序可打乱', () async {
    const raw = '金额,日期时间,类型,主分类,备注\n'
        '8.80,2026-03-01 12:00:00,支出,餐饮,豆浆';
    final table = CsvTable.parse(raw);
    final columns = ColumnMapping.guess(table.headers);
    final n = await csv.importMapped(
      table: table,
      columns: columns,
      defaultLedgerId: ledgerId,
    );
    expect(n, 1);
    final rows = await db.select(db.transactions).get();
    expect(rows.single.amount, 8.8);
    expect(rows.single.note, '豆浆');
    expect(rows.single.happenedAt.month, 3);
  });

  test('日期解析失败的行跳过，不用今天充数', () async {
    const raw = '日期时间,金额\n'
        '不是日期,9.00\n'
        '2026-04-02,1.00';
    final table = CsvTable.parse(raw);
    final columns = ColumnMapping.guess(table.headers);
    final n = await csv.importMapped(
      table: table,
      columns: columns,
      defaultLedgerId: ledgerId,
    );
    expect(n, 1);
    final rows = await db.select(db.transactions).get();
    expect(rows.single.happenedAt.month, 4);
  });

  test('分类映射对到指定子分类', () async {
    final all = await cats.listByKind('expense');
    final dining = all.firstWhere((c) => c.name == '餐饮' && c.parentId == null);
    final child = all.firstWhere(
      (c) => c.parentId == dining.id,
      orElse: () => dining,
    );
    const raw = '日期时间,金额,主分类,子分类\n'
        '2026-05-01,20,外卖类,随便';
    final table = CsvTable.parse(raw);
    final columns = ColumnMapping.guess(table.headers);
    final key = const CategoryMapKey(
      kind: 'expense',
      primary: '外卖类',
      secondary: '随便',
    );
    final n = await csv.importMapped(
      table: table,
      columns: columns,
      defaultLedgerId: ledgerId,
      categoryMap: {key: child.id},
    );
    expect(n, 1);
    final tx = (await db.select(db.transactions).get()).single;
    expect(tx.categoryId, child.id);
  });

  test('标签映射范围不符则不挂', () async {
    final bundles = await tagRepo.getBundles();
    final pay = bundles.firstWhere((b) => b.group.name == '支付/渠道');
    expect(pay.group.scope, TagGroupScope.expense);
    final wechat = pay.tags.firstWhere((t) => t.name.contains('微信'));
    const raw = '日期时间,金额,类型,标签\n'
        '2026-06-01,100,收入,微信';
    final table = CsvTable.parse(raw);
    final columns = ColumnMapping.guess(table.headers);
    final n = await csv.importMapped(
      table: table,
      columns: columns,
      defaultLedgerId: ledgerId,
      tagMap: {'微信': wechat.id},
    );
    expect(n, 1);
    final links = await db.select(db.transactionTags).get();
    expect(links, isEmpty);
  });

  test('分类不映射写入未分类且不建树', () async {
    const raw = '日期时间,金额,主分类\n'
        '2026-07-01,5,外星分类\n'
        '2026-07-02,6,外星分类';
    final table = CsvTable.parse(raw);
    final columns = ColumnMapping.guess(table.headers);
    final key = const CategoryMapKey(
      kind: 'expense',
      primary: '外星分类',
      secondary: '',
    );
    final n = await csv.importMapped(
      table: table,
      columns: columns,
      defaultLedgerId: ledgerId,
      categoryMap: {key: null},
    );
    expect(n, 2);
    final rows = await db.select(db.transactions).get();
    expect(rows.every((r) => r.categoryId == null), isTrue);
    final created = await cats.listByKind('expense');
    expect(created.any((c) => c.name == '外星分类'), isFalse);
  });

  test('标签不映射忽略该名，不进外部导入', () async {
    const raw = '日期时间,金额,标签\n'
        '2026-08-01,3,一次性标签';
    final table = CsvTable.parse(raw);
    final columns = ColumnMapping.guess(table.headers);
    final n = await csv.importMapped(
      table: table,
      columns: columns,
      defaultLedgerId: ledgerId,
      tagMap: {'一次性标签': null},
    );
    expect(n, 1);
    final links = await db.select(db.transactionTags).get();
    expect(links, isEmpty);
    final allTags = await tagRepo.getAll();
    expect(allTags.any((t) => t.name == '一次性标签'), isFalse);
  });
}
