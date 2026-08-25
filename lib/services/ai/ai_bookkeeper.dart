import 'dart:typed_data';

import '../../ai/bill_info.dart';
import '../../ai/ai_vision_failure.dart';
import '../../ai/extraction_engine.dart';
import 'bill_creation_service.dart';
import 'bill_save_result.dart';

/// 智能记账统一入口：提取 →（可选）确认后落库。
///
/// 语音与扇形拍照选图默认先返回待确认账单，由 UI 调用 [saveBills]；
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
    AiVisionSwitchCallback? onSwitch,
  }) async {
    final ctx = await creation.buildContext();
    return engine.extractFromImage(
      imageBytes: bytes,
      context: ctx,
      mimeType: mimeType,
      onSwitch: onSwitch,
    );
  }

  /// AI 语音模型直接记账（不经听写）。
  Future<List<BillInfo>> fromVoice(
    Uint8List audioBytes, {
    String format = 'wav',
  }) async {
    final ctx = await creation.buildContext();
    return engine.extractFromVoice(
      audioBytes: audioBytes,
      context: ctx,
      format: format,
    );
  }

  /// 后台直存：重试 + 服务商回退（仅截图自动 / 分享入账）。
  Future<List<BillInfo>> fromImageWithFallback(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final ctx = await creation.buildContext();
    return engine.extractFromImageWithFallback(
      imageBytes: bytes,
      context: ctx,
      mimeType: mimeType,
    );
  }

  /// 确认后批量落库；按候选分桶，指纹撞车不中断后续（ADR-056）。
  ///
  /// [source] 须由调用方显式传入（如 `voice` / `screenshot` / `share`）。
  Future<BillSaveResult> saveBills({
    required List<BillInfo> bills,
    required int ledgerId,
    required String source,
  }) async {
    final ids = <int>[];
    var skipped = 0;
    var failed = 0;
    var savedAmount = 0.0;
    for (final bill in bills) {
      try {
        final id = await creation.createFromBill(
          bill: bill,
          ledgerId: ledgerId,
          source: source,
        );
        if (id != null) {
          ids.add(id);
          savedAmount += bill.amount ?? 0;
        } else {
          failed++;
        }
      } on StateError catch (e) {
        if ('$e'.contains('已存在相同账本')) {
          skipped++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }
    return BillSaveResult(
      ids: ids,
      skipped: skipped,
      failed: failed,
      savedAmount: savedAmount,
    );
  }
}
