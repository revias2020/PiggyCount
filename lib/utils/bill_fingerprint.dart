import 'happened_at.dart';

/// 账单指纹：账本 UUID + 金额（到分）+ 账单时间（到秒）。用于去重，不是跨设备身份。ADR-044。
abstract final class BillFingerprint {
  /// 拼指纹字符串（稳定、可比较）。
  static String build({
    required String ledgerSyncId,
    required double amount,
    required DateTime happenedAt,
  }) {
    final cents = (amount * 100).round();
    final amt = (cents / 100).toStringAsFixed(2);
    final t = HappenedAt.toSecond(happenedAt);
    final iso =
        '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}T'
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    return '$ledgerSyncId|$amt|$iso';
  }
}
