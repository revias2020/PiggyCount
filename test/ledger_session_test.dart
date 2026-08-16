import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:piggy_count/data/seed_service.dart';
import 'package:piggy_count/providers/database_provider.dart';
import 'package:piggy_count/providers/ledger_session_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.memory();
    await SeedService(db).ensureSeeded();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<LedgerSession> waitSession() async {
    for (var i = 0; i < 40; i++) {
      final value = container.read(ledgerSessionProvider);
      if (value.hasValue) return value.requireValue;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('ledgerSessionProvider 未就绪');
  }

  test('切换账本会更新 currentId 与持久化设置', () async {
    final session = await waitSession();
    final firstId = session.currentId;

    final secondId = await container
        .read(ledgerRepositoryProvider)
        .create('旅行账本', select: false);
    // create 会触发 ledgers.watch，等列表含新账本
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final withTwo = await waitSession();
    expect(withTwo.ledgers.map((e) => e.id), containsAll([firstId, secondId]));
    expect(withTwo.currentId, firstId);

    await container.read(ledgerSessionProvider.notifier).select(secondId);

    final switched = container.read(ledgerSessionProvider).requireValue;
    expect(switched.currentId, secondId);
    expect(container.read(currentLedgerIdProvider), secondId);
    expect(
      await container.read(ledgerRepositoryProvider).readCurrentLedgerId(),
      secondId,
    );
  });
}
