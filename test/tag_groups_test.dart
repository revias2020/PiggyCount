import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/ai/bill_info.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:piggy_count/data/repositories/category_repository.dart';
import 'package:piggy_count/data/repositories/ledger_repository.dart';
import 'package:piggy_count/data/repositories/settings_repository.dart';
import 'package:piggy_count/data/repositories/tag_repository.dart';
import 'package:piggy_count/data/repositories/transaction_repository.dart';
import 'package:piggy_count/services/ai/bill_creation_service.dart';

void main() {
  late AppDatabase db;
  late TagRepository tags;
  late BillCreationService creation;
  late int ledgerId;

  setUp(() async {
    db = AppDatabase.memory();
    tags = TagRepository(db);
    final ledgers = LedgerRepository(db);
    ledgerId = await ledgers.create('测试账本');
    creation = BillCreationService(
      categories: CategoryRepository(db),
      tags: tags,
      transactions: TransactionRepository(db),
      settings: SettingsRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('升级语义：默认字符串组存在且可挂标签', () async {
    final bundles = await tags.getBundles();
    expect(bundles, isNotEmpty);
    expect(bundles.first.group.name, TagRepository.defaultGroupName);
    expect(bundles.first.isString, isTrue);

    final id = await tags.create('咖啡');
    final all = await tags.getAll();
    expect(all.single.id, id);
    expect(all.single.groupId, bundles.first.group.id);
  });

  test('数值组禁重叠且金额落区间选标', () async {
    final gid = await tags.createGroup(name: '金额档', kind: TagGroupKind.number);
    await tags.create('小额', groupId: gid, rangeMin: 0, rangeMax: 100);
    await tags.create('大额', groupId: gid, rangeMin: 100, rangeMax: null);

    expect(
      () => tags.create('中额', groupId: gid, rangeMin: 50, rangeMax: 200),
      throwsA(isA<StateError>()),
    );

    await SettingsRepository(db).setAutoGenerateTags(false);
    final smallId = await creation.createFromBill(
      bill: const BillInfo(
        amount: 50,
        type: BillType.expense,
        note: '测试',
      ),
      ledgerId: ledgerId,
    );
    expect(smallId, isNotNull);
    final smallTags =
        await TransactionRepository(db).getTagIds(smallId!);
    final smallName = (await tags.getAll())
        .firstWhere((t) => t.id == smallTags.single)
        .name;
    expect(smallName, '小额');

    final largeId = await creation.createFromBill(
      bill: const BillInfo(
        amount: 100,
        type: BillType.expense,
        note: '测试',
      ),
      ledgerId: ledgerId,
    );
    final largeTags =
        await TransactionRepository(db).getTagIds(largeId!);
    final largeName = (await tags.getAll())
        .firstWhere((t) => t.id == largeTags.single)
        .name;
    expect(largeName, '大额');
  });

  test('字符串组智能选标最多 2 个，并可按组名建标', () async {
    final gid = await tags.createGroup(name: '场景', kind: TagGroupKind.string);
    await tags.create('外卖', groupId: gid);
    await tags.create('聚餐', groupId: gid);
    await tags.create('通勤', groupId: gid);
    await SettingsRepository(db).setAutoGenerateTags(true);

    final txId = await creation.createFromBill(
      bill: const BillInfo(
        amount: 30,
        type: BillType.expense,
        tags: [
          SuggestedTag(name: '外卖'),
          SuggestedTag(name: '聚餐'),
          SuggestedTag(name: '通勤'),
          SuggestedTag(groupName: '场景', name: '加班餐'),
        ],
      ),
      ledgerId: ledgerId,
    );
    final ids = await TransactionRepository(db).getTagIds(txId!);
    // 前两个已有 + 配额 2，加班餐因配额满而不建；仅「外卖」「聚餐」
    expect(ids.length, 2);
    final names = (await tags.getAll())
        .where((t) => ids.contains(t.id))
        .map((t) => t.name)
        .toSet();
    expect(names, {'外卖', '聚餐'});
  });

  test('有标签时禁删组', () async {
    final gid = await tags.createGroup(name: '对象', kind: TagGroupKind.string);
    await tags.create('自己', groupId: gid);
    expect(
      () => tags.deleteGroup(gid),
      throwsA(isA<StateError>()),
    );
  });

  test('增删标签时 watchBundles 会刷新组内列表', () async {
    final gid = await tags.createGroup(name: '金额档', kind: TagGroupKind.number);
    final events = <List<String>>[];
    final sub = tags.watchBundles().listen((bundles) {
      events.add(
        bundles
            .firstWhere((b) => b.group.id == gid)
            .tags
            .map((t) => t.name)
            .toList(),
      );
    });

    await Future<void>.delayed(Duration.zero);
    expect(events.isNotEmpty, isTrue);
    expect(events.last, isEmpty);

    await tags.create('little', groupId: gid, rangeMin: 0, rangeMax: 50);
    await Future<void>.delayed(Duration.zero);
    expect(events.last, ['little']);

    final littleId =
        (await tags.getAll()).firstWhere((t) => t.name == 'little').id;
    await tags.delete(littleId);
    await Future<void>.delayed(Duration.zero);
    expect(events.last, isEmpty);

    await sub.cancel();
  });

  test('SuggestedTag 解析 group/name 与对象', () {
    final a = BillInfo.fromJson({
      'amount': 1,
      'tags': ['场景/外卖', {'group': '对象', 'name': '自己'}],
    });
    expect(a.tags!.length, 2);
    expect(a.tags![0].groupName, '场景');
    expect(a.tags![0].name, '外卖');
    expect(a.tags![1].groupName, '对象');
    expect(a.tags![1].name, '自己');
  });
}
