import 'package:flutter/material.dart';

/// 将种子/数据库中的图标 key 映射为 Material [IconData]。
///
/// 未知 key 回退到 [Icons.category_outlined]，避免坏数据导致崩溃。
IconData categoryIconData(String? key) {
  switch (key) {
    case 'shopping_bag':
      return Icons.shopping_bag_outlined;
    case 'restaurant':
      return Icons.restaurant_outlined;
    case 'cake':
      return Icons.cake_outlined;
    case 'icecream':
      return Icons.icecream_outlined;
    case 'dinner_dining':
      return Icons.dinner_dining_outlined;
    case 'liquor':
      return Icons.liquor_outlined;
    case 'apple':
      return Icons.apple;
    case 'coffee':
      return Icons.coffee_outlined;
    case 'kitchen':
      return Icons.kitchen_outlined;
    case 'storefront':
      return Icons.storefront_outlined;
    case 'checkroom':
      return Icons.checkroom_outlined;
    case 'devices':
      return Icons.devices_outlined;
    case 'chair':
      return Icons.chair_outlined;
    case 'home':
      return Icons.home_outlined;
    case 'bolt':
      return Icons.bolt_outlined;
    case 'apartment':
      return Icons.apartment_outlined;
    case 'directions_car':
      return Icons.directions_car_outlined;
    case 'subway':
      return Icons.subway_outlined;
    case 'local_taxi':
      return Icons.local_taxi_outlined;
    case 'local_gas_station':
      return Icons.local_gas_station_outlined;
    case 'payments':
      return Icons.payments_outlined;
    case 'emoji_events':
      return Icons.emoji_events_outlined;
    case 'card_giftcard':
      return Icons.card_giftcard_outlined;
    case 'redeem':
      return Icons.redeem_outlined;
    case 'trending_up':
      return Icons.trending_up;
    case 'savings':
      return Icons.savings_outlined;
    case 'show_chart':
      return Icons.show_chart;
    case 'more_horiz':
      return Icons.more_horiz;
    case 'work':
      return Icons.work_outline;
    case 'attach_money':
      return Icons.attach_money;
    case 'phone':
      return Icons.phone_outlined;
    case 'sports_esports':
      return Icons.sports_esports_outlined;
    case 'local_hospital':
      return Icons.local_hospital_outlined;
    case 'school':
      return Icons.school_outlined;
    case 'swap_horiz':
      return Icons.swap_horiz;
    case 'flight':
      return Icons.flight_outlined;
    case 'account_balance':
      return Icons.account_balance_outlined;
    case 'volunteer_activism':
      return Icons.volunteer_activism_outlined;
    case 'handshake':
      return Icons.handshake_outlined;
    case 'spa':
      return Icons.spa_outlined;
    case 'child_care':
      return Icons.child_care_outlined;
    case 'pets':
      return Icons.pets_outlined;
    case 'local_shipping':
      return Icons.local_shipping_outlined;
    case 'cleaning_services':
      return Icons.cleaning_services_outlined;
    case 'call_received':
      return Icons.call_received;
    case 'request_quote':
      return Icons.request_quote_outlined;
    case 'category':
      return Icons.category_outlined;
    default:
      return Icons.category_outlined;
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
  'category',
];

/// 分类图标底色（按名称稳定取色，与截图多彩圆标一致）。
Color categoryIconColor(String name, {String? icon}) {
  const palette = <Color>[
    Color(0xFFFF6B6B),
    Color(0xFFFF8E53),
    Color(0xFFFFB347),
    Color(0xFFFFD93D),
    Color(0xFF6BCB77),
    Color(0xFF4D96FF),
    Color(0xFF6C63FF),
    Color(0xFF9B59B6),
    Color(0xFFE056A0),
    Color(0xFF20C997),
    Color(0xFF17A2B8),
    Color(0xFF5C7AEA),
  ];
  final seed = Object.hash(name, icon ?? '');
  return palette[seed.abs() % palette.length];
}
