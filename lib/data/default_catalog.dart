/// 出厂默认分类树与默认标签清单（纯数据，无 IO）。
abstract final class DefaultCatalog {
  /// 支出主分类（含可选子分类）。顺序即默认 sortOrder。
  static const expenseTree = <DefaultMainCategory>[
    DefaultMainCategory('消费', 'shopping_bag'),
    DefaultMainCategory('餐饮', 'restaurant', children: [
      DefaultChildCategory('鲜花蛋糕', 'cake'),
      DefaultChildCategory('奶茶甜点', 'icecream'),
      DefaultChildCategory('早午晚餐', 'dinner_dining'),
      DefaultChildCategory('烟酒茶叶', 'liquor'),
      DefaultChildCategory('水果零食', 'apple'),
      DefaultChildCategory('咖啡奶茶', 'coffee'),
      DefaultChildCategory('烹饪食材', 'kitchen'),
    ]),
    DefaultMainCategory('购物', 'storefront', children: [
      DefaultChildCategory('其他物品', 'category'),
      DefaultChildCategory('摄影器械', 'photo_camera'),
      DefaultChildCategory('小家电', 'kitchen'),
      DefaultChildCategory('生活用品', 'cleaning_services'),
      DefaultChildCategory('零食甜水', 'fastfood'),
      DefaultChildCategory('穿搭美妆', 'checkroom'),
      DefaultChildCategory('手机数码', 'devices'),
      DefaultChildCategory('母婴玩具', 'child_care'),
    ]),
    DefaultMainCategory('住房', 'home', children: [
      DefaultChildCategory('网络宽带', 'wifi'),
      DefaultChildCategory('房租物业', 'apartment'),
      DefaultChildCategory('水电燃气', 'bolt'),
      DefaultChildCategory('维修清洁', 'handyman'),
    ]),
    DefaultMainCategory('交通', 'directions_car', children: [
      DefaultChildCategory('共享单车', 'pedal_bike'),
      DefaultChildCategory('公交地铁', 'subway'),
      DefaultChildCategory('打车租车', 'local_taxi'),
      DefaultChildCategory('火车飞机', 'flight'),
      DefaultChildCategory('保养修车', 'car_repair'),
      DefaultChildCategory('加油充电', 'local_gas_station'),
      DefaultChildCategory('停车费', 'local_parking'),
    ]),
    DefaultMainCategory('通讯', 'phone'),
    DefaultMainCategory('娱乐', 'sports_esports', children: [
      DefaultChildCategory('游戏', 'sports_esports'),
      DefaultChildCategory('约会', 'favorite'),
      DefaultChildCategory('电影', 'movie'),
      DefaultChildCategory('运动健身', 'fitness_center'),
      DefaultChildCategory('足浴按摩', 'spa'),
      DefaultChildCategory('歌舞演出', 'mic'),
    ]),
    DefaultMainCategory('医疗', 'local_hospital'),
    DefaultMainCategory('教育', 'school', children: [
      DefaultChildCategory('学费', 'school'),
      DefaultChildCategory('培训考试', 'devices'),
      DefaultChildCategory('家教补习', 'menu_book'),
      DefaultChildCategory('书报杂志', 'auto_stories'),
    ]),
    DefaultMainCategory('红包', 'card_giftcard'),
    DefaultMainCategory('转账', 'swap_horiz'),
    DefaultMainCategory('旅行', 'flight', children: [
      DefaultChildCategory('零食水果', 'apple'),
      DefaultChildCategory('高速过路', 'toll'),
      DefaultChildCategory('租车加油', 'local_gas_station'),
      DefaultChildCategory('旅行交通', 'train'),
      DefaultChildCategory('酒店住宿', 'hotel'),
      DefaultChildCategory('美食特产', 'restaurant'),
      DefaultChildCategory('景点门票', 'account_balance'),
    ]),
    DefaultMainCategory('投资', 'trending_up', children: [
      DefaultChildCategory('基金', 'show_chart'),
      DefaultChildCategory('股票', 'candlestick_chart'),
      DefaultChildCategory('黄金', 'payments'),
      DefaultChildCategory('保险', 'health_and_safety'),
    ]),
    DefaultMainCategory('借出', 'volunteer_activism'),
    DefaultMainCategory('还款', 'credit_card', children: [
      DefaultChildCategory('房贷车贷', 'home'),
      DefaultChildCategory('消费还款', 'credit_card'),
    ]),
    DefaultMainCategory('美容', 'spa'),
    DefaultMainCategory('亲子', 'child_care'),
    DefaultMainCategory('人情社交', 'forum', children: [
      DefaultChildCategory('请客送礼', 'card_giftcard'),
      DefaultChildCategory('慈善捐款', 'volunteer_activism'),
      DefaultChildCategory('孝敬长辈', 'elderly'),
    ]),
    DefaultMainCategory('宠物', 'pets'),
    DefaultMainCategory('快递', 'local_shipping'),
    DefaultMainCategory('其他', 'more_horiz'),
  ];

  static const incomeMains = <DefaultMainCategory>[
    DefaultMainCategory('薪资', 'payments'),
    DefaultMainCategory('理财', 'trending_up'),
    DefaultMainCategory('收红包', 'card_giftcard'),
    DefaultMainCategory('收转账', 'call_received'),
    DefaultMainCategory('借入', 'savings'),
    DefaultMainCategory('收款', 'request_quote'),
    DefaultMainCategory('其他', 'more_horiz'),
  ];

  static const paymentChannelGroup = DefaultTagGroup(
    name: '支付/渠道',
    kind: 'string',
    scope: 'expense',
    tags: [
      DefaultTag('微信', color: '#4CAF50'),
      DefaultTag('支付宝', color: '#2196F3'),
      DefaultTag('信用卡', color: '#9C27B0'),
      DefaultTag('花呗/白条', color: '#FF9800'),
      DefaultTag('美团', color: '#FF5722'),
      DefaultTag('京东', color: '#F44336'),
      DefaultTag('拼多多', color: '#E91E63'),
      DefaultTag('抖音', color: '#607D8B'),
      DefaultTag('银行卡', color: '#3F51B5'),
    ],
  );

  static const amountTierGroup = DefaultTagGroup(
    name: '额度',
    kind: 'number',
    scope: 'both',
    tags: [
      DefaultTag('小额', color: '#8BC34A', rangeMin: 0, rangeMax: 100),
      DefaultTag('中额', color: '#FFC107', rangeMin: 100, rangeMax: 500),
      DefaultTag('大额', color: '#FF5722', rangeMin: 500),
    ],
  );

  static const tagGroups = [paymentChannelGroup, amountTierGroup];
}

class DefaultMainCategory {
  const DefaultMainCategory(this.name, this.icon, {this.children = const []});

  final String name;
  final String icon;
  final List<DefaultChildCategory> children;
}

class DefaultChildCategory {
  const DefaultChildCategory(this.name, this.icon);

  final String name;
  final String icon;
}

class DefaultTagGroup {
  const DefaultTagGroup({
    required this.name,
    required this.kind,
    required this.scope,
    required this.tags,
  });

  final String name;
  final String kind;
  final String scope;
  final List<DefaultTag> tags;
}

class DefaultTag {
  const DefaultTag(
    this.name, {
    required this.color,
    this.rangeMin,
    this.rangeMax,
  });

  final String name;
  final String color;
  final double? rangeMin;
  final double? rangeMax;
}
