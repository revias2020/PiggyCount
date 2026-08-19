import 'dart:typed_data';

import '../../ai/bill_info.dart';
import '../../ai/extraction_engine.dart';
import 'bill_creation_service.dart';

/// 智能记账统一入口：提取 →（可选）确认后落库。
///
/// MVP：语音/对话与扇形拍照选图默认先返回待确认账单，由 UI 调用 [saveBills]；
/// 截图自动 / 分享入账走后台通知直存（ADR-018）。
class AiBookkeeper {
  AiBookkeeper({
    required this.engine,
    required this.creation,
  });

  final AiExtractionEngine engine;
  final BillCreationService creation;

  Future<List<BillInfo>> fromText(String text) async {
    final ctx = await creation.buildContext();
    return engine.extractFromText(text: text, context: ctx);
  }

  Future<List<BillInfo>> fromImage(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final ctx = await creation.buildContext();
    return engine.extractFromImage(
      imageBytes: bytes,
      context: ctx,
      mimeType: mimeType,
    );
  }

  /// 确认后批量落库；返回成功写入的交易 id。
  Future<List<int>> saveBills({
    required List<BillInfo> bills,
    required int ledgerId,
    String source = 'ai_chat',
  }) async {
    final ids = <int>[];
    for (final bill in bills) {
      final id = await creation.createFromBill(
        bill: bill,
        ledgerId: ledgerId,
        source: source,
      );
      if (id != null) ids.add(id);
    }
    return ids;
  }
}
