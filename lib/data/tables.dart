import 'package:drift/drift.dart';

/// 账本表。
///
/// 分类/标签为全局实体（不按账本隔离），账单通过 [ledgerId] 归属账本。
class Ledgers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  /// 跨设备同步稳定 ID。
  TextColumn get syncId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  /// 较晚改动（墙上时钟，ADR-042）。
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  /// 非空表示已删除（墓碑）；未删除名唯一由业务层保证。
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// 分类表：支出/收入两套；[parentId] 为空=主分类，非空=子分类（深度固定 2）。
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  /// `expense` | `income`
  TextColumn get kind => text()();
  TextColumn get icon => text().nullable()();
  /// `material` | `custom`
  TextColumn get iconType =>
      text().withDefault(const Constant('material'))();
  /// 相对路径，如 `custom_icons/12_1710000000000.png`；仅 [iconType]=custom 时有值。
  TextColumn get customIconPath => text().nullable()();
  /// 主分类为 null；子分类指向主分类 id。
  IntColumn get parentId => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get syncId => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// 标签组：`string` = 字符串组；`number` = 数值组。
class TagGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  /// 全库唯一（活着的）；库层仍 unique，软删时改名腾位。
  TextColumn get name => text().unique()();
  /// `string` | `number`
  TextColumn get kind => text()();
  /// `both` | `expense` | `income`
  TextColumn get scope =>
      text().withDefault(const Constant('both'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get syncId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// 标签表：恰好属于一个 [TagGroups]；经 [TransactionTags] 挂到账单。
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  IntColumn get groupId => integer()();
  /// 展示色 hex（如 `#FF5722`）；预设色板内取值。
  TextColumn get color =>
      text().withDefault(const Constant('#607D8B'))();
  /// 数值组标签：区间下限（含）；字符串组为 null。
  RealColumn get rangeMin => real().nullable()();
  /// 数值组标签：区间上限（不含）；null 表示无上界。
  RealColumn get rangeMax => real().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get syncId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// 账单表。
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ledgerId => integer()();
  /// `expense` | `income`
  TextColumn get type => text()();
  RealColumn get amount => real()();
  IntColumn get categoryId => integer().nullable()();
  DateTimeColumn get happenedAt => dateTime()();
  TextColumn get note => text().nullable()();
  /// `manual` | `voice` | `screenshot` | `share` | `ai_chat`
  TextColumn get source => text().withDefault(const Constant('manual'))();
  /// 遗留列；跨设备认亲以 [fingerprint] 为准（ADR-042）。
  TextColumn get syncId => text()();
  /// 账单指纹：账本 UUID + 金额到分 + 账单时间到秒。
  TextColumn get fingerprint => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// 账单 ↔ 标签 多对多。
class TransactionTags extends Table {
  IntColumn get transactionId => integer()();
  IntColumn get tagId => integer()();

  @override
  Set<Column> get primaryKey => {transactionId, tagId};
}

/// 应用键值设置（分类模式等）。
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
