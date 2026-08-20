import 'package:intl/intl.dart';

/// 金额展示：千分位 + 两位小数，不含货币符号（UI 用「元」或 ¥ 自行拼接）。
String formatMoney(double value) {
  return NumberFormat('#,##0.00').format(value);
}

/// 带 ¥ 前缀（桌面小组件等）。
String formatWidgetMoney(double value) => '¥${formatMoney(value)}';

/// 小号本月金额：&lt;1k 整数；\[1k,1w) 为 `x.xxk`；≥1w 为 `x.xxw`（档内截断两位）。
String formatWidgetMoneyCompact(double value) {
  final abs = value.abs();
  if (abs < 1000) {
    return '¥${abs.truncate()}';
  }
  if (abs < 10000) {
    return '¥${_truncateFixed2(abs / 1000)}k';
  }
  return '¥${_truncateFixed2(abs / 10000)}w';
}

String _truncateFixed2(double v) {
  final truncated = (v * 100).floor() / 100;
  return truncated.toStringAsFixed(2);
}

/// 带符号金额：支出侧常用负号；报表排行对支出显示 `-x.xx`。
String formatSignedMoney(double value, {bool asExpense = false}) {
  final abs = formatMoney(value.abs());
  if (asExpense || value < 0) return '-$abs';
  if (value > 0) return abs;
  return abs;
}

/// 列表/头部紧凑金额：整数去尾零，并加千分位。
String formatMoneyCompact(double value) {
  final s = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}
