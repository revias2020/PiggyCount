import '../../ai/bill_info.dart';
import '../../ai/extraction_engine.dart';
import '../../data/repositories/statistics_repository.dart';
import '../../utils/report_period.dart';
import 'ai_bookkeeper.dart';

/// 对话编排：记账意图 → 提取待确认账单；否则自由分析对话。
class AiChatService {
  AiChatService({
    required this.bookkeeper,
    required this.engine,
    required this.statistics,
  });

  final AiBookkeeper bookkeeper;
  final AiExtractionEngine engine;
  final StatisticsRepository statistics;

  Future<AiChatReply> processMessage(
    String userInput, {
    required int ledgerId,
    bool forceAnalysis = false,
  }) async {
    final text = userInput.trim();
    if (text.isEmpty) {
      return AiChatReply.text('请输入内容');
    }

    if (!forceAnalysis && _isTransactionIntent(text)) {
      try {
        final bills = await bookkeeper.fromText(text);
        if (bills.isEmpty) {
          return AiChatReply.text(
            '没有识别到完整记账信息。\n\n可以试试：\n'
            '• 买了杯奶茶 28\n'
            '• 今天午餐花了 50\n'
            '• 打车回家 35',
          );
        }
        return AiChatReply.pendingBills(bills);
      } catch (e) {
        return AiChatReply.text('记账识别失败：$e');
      }
    }

    try {
      final context = await _ledgerBrief(ledgerId);
      final reply = await engine.chat(
        userMessage: text,
        systemPrompt: '''你是「小猪记账」的中文账单助手。
根据用户账本摘要回答消费分析、省钱建议、异常排查等问题。
不要编造不存在的精确账单；若信息不足请说明。
不做预算功能，可用「花费与结余」表述。
账本摘要：
$context''',
      );
      return AiChatReply.text(reply.trim());
    } catch (e) {
      return AiChatReply.text('对话失败：$e');
    }
  }

  bool _isTransactionIntent(String input) {
    final hasAmount = RegExp(r'\d+(?:\.\d+)?').hasMatch(input);
    const keywords = [
      '买',
      '花',
      '消费',
      '支付',
      '记账',
      '付',
      '收入',
      '赚',
      '工资',
      '报销',
      '打车',
      '吃饭',
    ];
    final hasKeyword = keywords.any(input.contains);
    return (hasAmount && hasKeyword) ||
        (hasAmount && RegExp(r'[元块钱¥￥]').hasMatch(input));
  }

  Future<String> _ledgerBrief(int ledgerId) async {
    final now = DateTime.now();
    final month = ReportPeriod.fromScope(ReportScope.month, now);
    final week = ReportPeriod.fromScope(ReportScope.week, now);
    final monthSnap = await statistics.loadReport(
      ledgerId: ledgerId,
      period: month,
      type: ReportMoneyType.expense,
    );
    final weekSnap = await statistics.loadReport(
      ledgerId: ledgerId,
      period: week,
      type: ReportMoneyType.expense,
    );
    return '本周支出 ${weekSnap.expenseTotal.toStringAsFixed(2)} / '
        '收入 ${weekSnap.incomeTotal.toStringAsFixed(2)}；'
        '本月支出 ${monthSnap.expenseTotal.toStringAsFixed(2)} / '
        '收入 ${monthSnap.incomeTotal.toStringAsFixed(2)}。';
  }
}

class AiChatReply {
  AiChatReply._({this.text, this.pendingBills});

  factory AiChatReply.text(String text) => AiChatReply._(text: text);

  factory AiChatReply.pendingBills(List<BillInfo> bills) =>
      AiChatReply._(pendingBills: bills);

  final String? text;
  final List<BillInfo>? pendingBills;

  bool get isBills => pendingBills != null && pendingBills!.isNotEmpty;
}
