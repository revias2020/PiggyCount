import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/ledger_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../data/repositories/statistics_repository.dart';
import '../data/repositories/transaction_repository.dart';

/// 数据库实例；必须在 [main] 里用 `overrideWithValue` 注入。
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('请在 main 中 override databaseProvider');
});

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(ref.watch(databaseProvider)),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(databaseProvider)),
);

final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepository(ref.watch(databaseProvider)),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(databaseProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final statisticsRepositoryProvider = Provider<StatisticsRepository>(
  (ref) => StatisticsRepository(ref.watch(databaseProvider)),
);
