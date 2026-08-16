import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:piggy_count/app.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:piggy_count/data/seed_service.dart';
import 'package:piggy_count/providers/database_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await SeedService(db).ensureSeeded();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('主壳展示三 Tab 与顶栏标题', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const PiggyApp(),
      ),
    );
    // 等账本 Stream 首帧；避免 pumpAndSettle 卡在无限动画上
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('小猪记账'), findsOneWidget);
    expect(find.text('日常账本'), findsOneWidget);
    expect(find.text('明细'), findsWidgets);
    expect(find.text('报表'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    expect(find.text('记一笔'), findsOneWidget);

    // 先卸掉 ProviderScope，再关闭 DB，消化 Drift 取消订阅产生的 Timer
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('种子数据包含默认账本与分类', () async {
    final ledgers = await db.select(db.ledgers).get();
    expect(ledgers, isNotEmpty);
    expect(ledgers.first.name, '日常账本');

    final cats = await db.select(db.categories).get();
    expect(cats.where((c) => c.kind == 'expense'), isNotEmpty);
    expect(cats.where((c) => c.kind == 'income'), isNotEmpty);
  });
}
