import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:piggy_count/data/repositories/category_repository.dart';
import 'package:piggy_count/data/seed_service.dart';
import 'package:piggy_count/services/csv/category_csv_service.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;
  late CategoryCsvService csv;

  setUp(() async {
    db = AppDatabase.memory();
    await SeedService(db).ensureSeeded();
    repo = CategoryRepository(db);
    csv = CategoryCsvService(repo);
  });

  tearDown(() async {
    await db.close();
  });

  test('导出 CSV 含 BeeCount 兼容表头与父子关系', () async {
    final parentId = await repo.create(
      name: '导出主类',
      kind: 'expense',
      icon: 'restaurant',
    );
    await repo.create(
      name: '导出子类',
      kind: 'expense',
      parentId: parentId,
      icon: 'cake',
    );

    final exported = await csv.exportCsv(filterKind: 'expense');
    expect(exported, contains(CategoryCsvService.header));
    expect(exported, contains('导出主类'));
    expect(exported, contains('导出子类'));
    expect(
      exported.split('\n').any(
            (l) => l.contains('导出子类') && l.contains('导出主类'),
          ),
      isTrue,
    );
  });

  test('CSV 导出再导入（合并）可新增分类', () async {
    final before = await repo.listAll();
    final exported = await csv.exportCsv();

    await repo.clearUnused();
    final afterClear = await repo.listAll();
    expect(afterClear.length, lessThan(before.length));

    final result = await csv.importText(
      exported,
      fileName: 'categories.csv',
      mode: 'merge',
    );
    expect(result.imported, greaterThan(0));
  });

  test('导入 BeeCount categories.yaml', () async {
    const yaml = '''
# BeeCount 分类包
version: 1
exported_at: "2026-08-16T00:00:00.000"
categories:
  - name: "Bee主类"
    kind: "expense"
    icon: "restaurant"
    sort_order: 0
    level: 1
    icon_type: "material"
  - name: "Bee子类"
    kind: "expense"
    icon: "cake"
    sort_order: 0
    level: 2
    icon_type: "material"
    parent_name: "Bee主类"
''';
    final result = await csv.importText(
      yaml,
      fileName: 'categories.yaml',
      mode: 'merge',
    );
    expect(result.imported, 2);

    final all = await repo.listByKind('expense');
    final parent = all.firstWhere((c) => c.name == 'Bee主类');
    expect(parent.parentId, isNull);
    final child = all.firstWhere((c) => c.name == 'Bee子类');
    expect(child.parentId, parent.id);
  });

  test('导入 BeeCount zip 分类包', () async {
    const yaml = '''
version: 1
exported_at: "2026-08-16T00:00:00.000"
categories:
  - name: "Zip主类"
    kind: "income"
    icon: "payments"
    sort_order: 1
    level: 1
    icon_type: "material"
''';
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'categories.yaml',
          utf8.encode(yaml).length,
          utf8.encode(yaml),
        ),
      );
    final zipBytes = ZipEncoder().encode(archive);

    final result = await csv.importBeeCountZip(zipBytes, mode: 'merge');
    expect(result.imported, 1);
    final hit =
        (await repo.listByKind('income')).where((c) => c.name == 'Zip主类');
    expect(hit.length, 1);
  });

  test('导出 zip 含 categories.csv', () async {
    final dir = await Directory.systemTemp.createTemp('piggy_cat_');
    final out = '${dir.path}/cats.zip';
    await csv.exportZip(outputPath: out);
    final bytes = await File(out).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.findFile('categories.csv'), isNotNull);
    await dir.delete(recursive: true);
  });

  test('同名同 kind 合并时跳过', () async {
    await repo.create(name: '重复名', kind: 'expense', icon: 'category');
    final csvText = [
      CategoryCsvService.header,
      '重复名,expense,category,0,1,,material,',
    ].join('\n');
    final result = await csv.importText(
      csvText,
      fileName: 'a.csv',
      mode: 'merge',
    );
    expect(result.imported, 0);
    expect(result.skipped, 1);
  });
}
