import 'package:intl/intl.dart';

import '../../ai/bill_info.dart';

/// 账单确认 UI 共用展示字段（语音确认卡 / 图片多选行）。
bool billIsExpense(BillInfo bill) => bill.type != BillType.income;

String formatBillTime(BillInfo bill) {
  final t = bill.time;
  if (t == null) return '';
  return DateFormat('M月d日 HH:mm').format(t);
}

String formatBillTagLabel(SuggestedTag tag) {
  final group = tag.groupName;
  if (group == null || group.isEmpty) return tag.name;
  return '$group/${tag.name}';
}
