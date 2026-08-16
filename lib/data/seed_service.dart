import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

/// 首次启动种子：默认账本 + 常用支出/收入分类（单层扁平，无父子）。
///
/// 幂等：若已存在任意账本则跳过，避免重复插入。
class SeedService {
  SeedService(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<void> ensureSeeded() async {
    final existing = await _db.select(_db.ledgers).get();
    if (existing.isNotEmpty) return;

    await _db.transaction(() async {
      await _db.into(_db.ledgers).insert(
            LedgersCompanion.insert(
              name: '日常账本',
              syncId: _uuid.v4(),
            ),
          );

      await _seedExpense();
      await _seedIncome();

      await _db.into(_db.appSettings).insert(
            AppSettingsCompanion.insert(
              key: 'current_ledger_id',
              value: '1',
            ),
          );
    });
  }

  Future<void> _seedExpense() async {
    const items = <(String, String)>[
      ('消费', 'shopping_bag'),
      ('餐饮', 'restaurant'),
      ('购物', 'storefront'),
      ('住房', 'home'),
      ('交通', 'directions_car'),
      ('通讯', 'phone'),
      ('娱乐', 'sports_esports'),
      ('医疗', 'local_hospital'),
      ('教育', 'school'),
      ('红包', 'card_giftcard'),
      ('转账', 'swap_horiz'),
      ('旅行', 'flight'),
      ('投资', 'trending_up'),
      ('借出', 'volunteer_activism'),
      ('还款', 'handshake'),
      ('美容', 'spa'),
      ('亲子', 'child_care'),
      ('人情社交', 'handshake'),
      ('宠物', 'pets'),
      ('快递', 'local_shipping'),
      ('其他', 'more_horiz'),
      ('生活日用', 'cleaning_services'),
    ];
    await _insertFlat('expense', items);
  }

  Future<void> _seedIncome() async {
    const items = <(String, String)>[
      ('薪资', 'payments'),
      ('理财', 'trending_up'),
      ('收红包', 'card_giftcard'),
      ('收转账', 'call_received'),
      ('借入', 'savings'),
      ('收款', 'request_quote'),
      ('其他', 'more_horiz'),
    ];
    await _insertFlat('income', items);
  }

  Future<void> _insertFlat(String kind, List<(String, String)> items) async {
    var order = 0;
    for (final (name, icon) in items) {
      await _db.into(_db.categories).insert(
            CategoriesCompanion.insert(
              name: name,
              kind: kind,
              syncId: _uuid.v4(),
              icon: Value(icon),
              sortOrder: Value(order++),
            ),
          );
    }
  }
}
