import 'package:intl/intl.dart';

/// 金额展示：千分位 + 两位小数，不含货币符号（UI 用「元」或 ¥ 自行拼接）。
String formatMoney(double value) {
  return NumberFormat('#,##0.00').format(value);
}

/// 带符号金额：支出侧常用负号；报表排行对支出显示 `-x.xx`。
String formatSignedMoney(double value, {bool asExpense = false}) {
  final abs = formatMoney(value.abs());
  if (asExpense || value < 0) return '-$abs';
  if (value > 0) return abs;
  return abs;
}
