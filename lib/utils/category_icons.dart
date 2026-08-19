import 'package:flutter/material.dart';

/// 未知 / 空 icon /「未分类」回退色。
const Color kCategoryIconFallbackColor = Color(0xFF9E9E9E);

/// 将种子/数据库中的图标 key 映射为 Material [IconData]（Filled）。
///
/// 未知 key 回退到 [Icons.category]，避免坏数据导致崩溃。
IconData categoryIconData(String? key) {
  switch (key) {
    case 'shopping_bag':
      return Icons.shopping_bag;
    case 'restaurant':
      return Icons.restaurant;
    case 'cake':
      return Icons.cake;
    case 'icecream':
      return Icons.icecream;
    case 'dinner_dining':
      return Icons.dinner_dining;
    case 'liquor':
      return Icons.liquor;
    case 'apple':
      return Icons.apple;
    case 'coffee':
      return Icons.coffee;
    case 'kitchen':
      return Icons.kitchen;
    case 'storefront':
      return Icons.storefront;
    case 'checkroom':
      return Icons.checkroom;
    case 'devices':
      return Icons.devices;
    case 'chair':
      return Icons.chair;
    case 'home':
      return Icons.home;
    case 'bolt':
      return Icons.bolt;
    case 'apartment':
      return Icons.apartment;
    case 'directions_car':
      return Icons.directions_car;
    case 'subway':
      return Icons.subway;
    case 'local_taxi':
      return Icons.local_taxi;
    case 'local_gas_station':
      return Icons.local_gas_station;
    case 'payments':
      return Icons.payments;
    case 'emoji_events':
      return Icons.emoji_events;
    case 'card_giftcard':
      return Icons.card_giftcard;
    case 'redeem':
      return Icons.redeem;
    case 'trending_up':
      return Icons.trending_up;
    case 'savings':
      return Icons.savings;
    case 'show_chart':
      return Icons.show_chart;
    case 'more_horiz':
      return Icons.more_horiz;
    case 'work':
      return Icons.work;
    case 'attach_money':
      return Icons.attach_money;
    case 'phone':
      return Icons.phone;
    case 'sports_esports':
      return Icons.sports_esports;
    case 'local_hospital':
      return Icons.local_hospital;
    case 'school':
      return Icons.school;
    case 'swap_horiz':
      return Icons.swap_horiz;
    case 'flight':
      return Icons.flight;
    case 'account_balance':
      return Icons.account_balance;
    case 'volunteer_activism':
      return Icons.volunteer_activism;
    case 'handshake':
      return Icons.handshake;
    case 'spa':
      return Icons.spa;
    case 'child_care':
      return Icons.child_care;
    case 'pets':
      return Icons.pets;
    case 'local_shipping':
      return Icons.local_shipping;
    case 'cleaning_services':
      return Icons.cleaning_services;
    case 'call_received':
      return Icons.call_received;
    case 'request_quote':
      return Icons.request_quote;
    case 'photo_camera':
      return Icons.photo_camera;
    case 'fastfood':
      return Icons.fastfood;
    case 'wifi':
      return Icons.wifi;
    case 'handyman':
      return Icons.handyman;
    case 'pedal_bike':
      return Icons.pedal_bike;
    case 'car_repair':
      return Icons.car_repair;
    case 'local_parking':
      return Icons.local_parking;
    case 'favorite':
      return Icons.favorite;
    case 'movie':
      return Icons.movie;
    case 'fitness_center':
      return Icons.fitness_center;
    case 'mic':
      return Icons.mic;
    case 'menu_book':
      return Icons.menu_book;
    case 'auto_stories':
      return Icons.auto_stories;
    case 'toll':
      return Icons.toll;
    case 'train':
      return Icons.train;
    case 'hotel':
      return Icons.hotel;
    case 'candlestick_chart':
      return Icons.candlestick_chart;
    case 'health_and_safety':
      return Icons.health_and_safety;
    case 'credit_card':
      return Icons.credit_card;
    case 'forum':
      return Icons.forum;
    case 'elderly':
      return Icons.elderly;
    case 'category':
      return Icons.category;
    default:
      return Icons.category;
  }
}

/// 可选图标列表（添加/编辑分类时展示）。
const List<String> categoryIconKeys = [
  'shopping_bag',
  'restaurant',
  'storefront',
  'home',
  'directions_car',
  'phone',
  'sports_esports',
  'local_hospital',
  'school',
  'card_giftcard',
  'swap_horiz',
  'flight',
  'trending_up',
  'volunteer_activism',
  'handshake',
  'spa',
  'child_care',
  'pets',
  'local_shipping',
  'cleaning_services',
  'payments',
  'savings',
  'call_received',
  'request_quote',
  'work',
  'attach_money',
  'more_horiz',
  'coffee',
  'cake',
  'devices',
  'checkroom',
  'bolt',
  'subway',
  'local_taxi',
  'photo_camera',
  'fastfood',
  'wifi',
  'handyman',
  'pedal_bike',
  'car_repair',
  'local_parking',
  'favorite',
  'movie',
  'fitness_center',
  'mic',
  'menu_book',
  'auto_stories',
  'toll',
  'train',
  'hotel',
  'candlestick_chart',
  'health_and_safety',
  'credit_card',
  'forum',
  'elderly',
  'category',
];

/// 分类彩标色：按 icon key 固定（大致对齐参考图）。
Color categoryIconColor(String? icon) {
  if (icon == null || icon.isEmpty) return kCategoryIconFallbackColor;
  return _kIconColors[icon] ?? kCategoryIconFallbackColor;
}

const Map<String, Color> _kIconColors = {
  // 支出常用（对齐参考图气质）
  'shopping_bag': Color(0xFFF5C518), // 消费 · 黄
  'restaurant': Color(0xFFFF8A3D), // 餐饮 · 橙
  'storefront': Color(0xFF4A7DFF), // 购物 · 蓝
  'home': Color(0xFFE85D5D), // 住房 · 红
  'directions_car': Color(0xFF5B9FE8), // 交通 · 天蓝
  'phone': Color(0xFF2BBBAD), // 通讯 · 青
  'sports_esports': Color(0xFFFF6B6B), // 娱乐 · 珊瑚
  'local_hospital': Color(0xFF26A69A), // 医疗 · 青绿
  'school': Color(0xFF5C7CFA), // 教育 · 靛蓝
  'card_giftcard': Color(0xFFE53935), // 红包 · 红
  'volunteer_activism': Color(0xFFF6C445), // 借出 · 黄
  'trending_up': Color(0xFFFF8F3D), // 投资 · 橙
  'spa': Color(0xFFFF7A6E), // 美容 · 珊瑚
  'handshake': Color(0xFF26A69A), // 社交/还款 · 青绿
  'local_shipping': Color(0xFF20C997), // 快递 · 薄荷绿
  'flight': Color(0xFF4A90E2), // 旅行 · 蓝
  'cleaning_services': Color(0xFF5B8DEF), // 日用 · 蓝
  'swap_horiz': Color(0xFF20C997), // 转账 · 绿
  'pets': Color(0xFFFFB347), // 宠物 · 黄橙
  'child_care': Color(0xFFFF8E53), // 亲子 · 橙
  'more_horiz': Color(0xFF5C7AEA), // 其他 · 蓝紫
  // 收入常用
  'payments': Color(0xFFE85D5D), // 薪资 · 红
  'savings': Color(0xFFF5C518), // 理财/借入 · 黄
  'call_received': Color(0xFF4CAF50), // 收转账 · 绿
  'request_quote': Color(0xFF43A047), // 收款 · 绿
  'work': Color(0xFF5C7AEA), // 工作 · 蓝
  'attach_money': Color(0xFFF6C445), // 金钱 · 黄
  'emoji_events': Color(0xFFFFB347), // 奖金 · 金
  'redeem': Color(0xFFE53935), // 兑换/红包 · 红
  // 其余可选
  'coffee': Color(0xFFA1887F),
  'cake': Color(0xFFFF8FAB),
  'icecream': Color(0xFFFF99C3),
  'dinner_dining': Color(0xFFFF8A3D),
  'liquor': Color(0xFF945FB9),
  'apple': Color(0xFF6BCB77),
  'kitchen': Color(0xFF17A2B8),
  'checkroom': Color(0xFF9B59B6),
  'devices': Color(0xFF4D96FF),
  'chair': Color(0xFF8D6E63),
  'bolt': Color(0xFFFFD93D),
  'apartment': Color(0xFFE056A0),
  'subway': Color(0xFF5C7AEA),
  'local_taxi': Color(0xFFFFB347),
  'local_gas_station': Color(0xFFFF8E53),
  'show_chart': Color(0xFFFF8F3D),
  'account_balance': Color(0xFF5C7AEA),
  'photo_camera': Color(0xFF4A90E2),
  'fastfood': Color(0xFFFF8A3D),
  'wifi': Color(0xFF4A7DFF),
  'handyman': Color(0xFFF6C445),
  'pedal_bike': Color(0xFF5B9FE8),
  'car_repair': Color(0xFF5B9FE8),
  'local_parking': Color(0xFF43A047),
  'favorite': Color(0xFFE53935),
  'movie': Color(0xFF5B8DEF),
  'fitness_center': Color(0xFFFF8E53),
  'mic': Color(0xFFF5C518),
  'menu_book': Color(0xFF5C7CFA),
  'auto_stories': Color(0xFFFF8A3D),
  'toll': Color(0xFF5B9FE8),
  'train': Color(0xFF4A90E2),
  'hotel': Color(0xFF5B8DEF),
  'candlestick_chart': Color(0xFFE85D5D),
  'health_and_safety': Color(0xFFE53935),
  'credit_card': Color(0xFF26A69A),
  'forum': Color(0xFF20C997),
  'elderly': Color(0xFFFF8E53),
  'category': kCategoryIconFallbackColor,
};
