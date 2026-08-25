/// [AiBookkeeper.saveBills] 的分桶结果（ADR-056）。
class BillSaveResult {
  const BillSaveResult({
    required this.ids,
    required this.skipped,
    required this.failed,
    this.savedAmount = 0,
  });

  /// 实际写入的本地交易 id。
  final List<int> ids;

  /// 指纹撞车跳过的候选数。
  final int skipped;

  /// 金额无效等应写未写的候选数。
  final int failed;

  /// 成功落库金额合计。
  final double savedAmount;

  int get saved => ids.length;

  bool get isEmpty => ids.isEmpty && skipped == 0 && failed == 0;
}
