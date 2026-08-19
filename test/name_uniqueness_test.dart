import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:piggy_count/data/repositories/category_repository.dart';
import 'package:piggy_count/data/repositories/ledger_repository.dart';
import 'package:piggy_count/data/repositories/tag_repository.dart';

void main() {
  late AppDatabase db;
  late LedgerRepository ledgers;
  late CategoryRepository categories;
  late TagRepository tags;

  setUp(() {
    db = AppDatabase.memory();
    ledgers = LedgerRepository(db);
    categories = CategoryRepository(db);
    tags = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('账本新建撞名抛错', () async {
    await ledgers.create('测试账本甲', select: false);
    expect(
      () => ledgers.create('测试账本甲', select: false),
      throwsA(isA<StateError>()),
    );
  });

  test('同一收支类型分类不可重名，跨类型可以', () async {
    await categories.create(name: '测试分类甲', kind: 'expense');
    expect(
      () => categories.create(name: '测试分类甲', kind: 'expense'),
      throwsA(isA<StateError>()),
    );
    final incomeId = await categories.create(name: '测试分类甲', kind: 'income');
    expect(incomeId, greaterThan(0));
  });

  test('标签与标签组撞名抛错，软删后可再建同名', () async {
    final gid = await tags.createGroup(name: '测试组甲', kind: TagGroupKind.string);
    await tags.create('测试标甲', groupId: gid);
    expect(
      () => tags.create('测试标甲'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => tags.createGroup(name: '测试组甲', kind: TagGroupKind.string),
      throwsA(isA<StateError>()),
    );

    final tag = (await tags.getAll()).firstWhere((t) => t.name == '测试标甲');
    await tags.delete(tag.id);
    final id = await tags.create('测试标甲', groupId: gid);
    expect(id, greaterThan(0));
  });
}
