import 'package:flutter/services.dart';

import '../platform/android_activity_bridge.dart';
import '../platform/foreground_billing_bridge.dart';
import 'auto_billing_service.dart';
import 'billing_image_limits.dart';
import 'share_early_progress_gate.dart';

/// 系统分享图片入账：冷/热启动均由原生写入临时文件后经 MethodChannel 通知。
///
/// Android 热启动经透明 ShareRelayActivity 转发，避免主界面再闪启动页。
/// 始终走后台智能记账（通知 + 自动落库），不打开确认弹层（ADR-018）。
/// 支持单张与多选（`SEND_MULTIPLE`，ADR-058）。
///
/// ShareRelay 拷图成功即起 FGS（ADR-063）；Dart 接手时再次 [ForegroundBillingBridge.start]，
/// **先** [AndroidActivityBridge.moveTaskToBack] 回源，再 hold 分享已收到进度 ≥1s，然后 Vision。
/// 直存期间返回键由 [AutoBillingService] 保活，不 finish。
class ImageShareHandler {
  ImageShareHandler({
    required this.autoBilling,
  });

  static const _channel = MethodChannel('com.xiaozhu.piggy_count/share');

  final AutoBillingService autoBilling;

  bool _bound = false;

  Future<void> bind() async {
    if (_bound) return;
    _bound = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onImagesShared') {
        final args = call.arguments;
        if (args is Map) {
          await _handlePayload(args);
        }
      } else if (call.method == 'onImageShared') {
        // 兼容旧单路径推送
        final path = call.arguments as String?;
        if (path != null) {
          await _handle(paths: [path], truncated: false);
        }
      }
    });

    // 冷启动：原生已拷好文件，pending 等此处取走（ADR-063，无固定 delay）
    try {
      final pending =
          await _channel.invokeMethod<dynamic>('getPendingSharedImages');
      if (pending is Map) {
        await _handlePayload(pending);
      } else {
        final legacy =
            await _channel.invokeMethod<String?>('getPendingSharedImage');
        if (legacy != null && legacy.isNotEmpty) {
          await _handle(paths: [legacy], truncated: false);
        }
      }
    } catch (_) {}
  }

  Future<void> _handlePayload(Map<dynamic, dynamic> args) async {
    final raw = args['paths'];
    final paths = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String && e.isNotEmpty) paths.add(e);
      }
    }
    final truncated = args['truncated'] == true;
    if (paths.isEmpty) return;
    await _handle(paths: paths, truncated: truncated);
  }

  Future<void> _handle({
    required List<String> paths,
    required bool truncated,
  }) async {
    var list = paths;
    var didTruncate = truncated;
    if (list.length > kMaxBillingImages) {
      list = list.take(kMaxBillingImages).toList();
      didTruncate = true;
    }

    final progressBody = didTruncate
        ? '已收到（$kBillingImagesTruncatedHint），准备识别…'
        : '已收到，准备识别…';

    // 始终 startForegroundService，不假设 Relay 已成功（ADR-063）。
    await ForegroundBillingBridge.start(
      title: '分享入账',
      body: progressBody,
    );
    await AndroidActivityBridge.setRetainOnBack(true);

    if (didTruncate) {
      autoBilling.setBatchNote(kBillingImagesTruncatedHint);
    }

    // 先回源再 hold：前台期间 FGS 文案常不可见；回源后栏里才算「看得到」。
    await AndroidActivityBridge.moveTaskToBack();
    // moveTaskToBack 返回早于 visibility=false（热启实测约 300ms）
    await Future<void>.delayed(ShareEarlyProgressGate.backgroundSettle);
    ShareEarlyProgressGate.markShown();
    await ShareEarlyProgressGate.awaitMinDisplay();

    await Future.wait([
      for (final path in list)
        autoBilling.processImagePath(
          path,
          source: 'share',
          showNotification: true,
          autoSave: true,
        ),
    ]);
  }
}
