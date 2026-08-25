import 'package:flutter/services.dart';

import '../platform/android_activity_bridge.dart';
import '../platform/foreground_billing_bridge.dart';
import '../system/logger_service.dart';
import 'auto_billing_service.dart';
import 'billing_image_limits.dart';

/// 系统分享图片入账：冷/热启动均由原生写入临时文件后经 MethodChannel 通知。
///
/// Android 热启动经透明 ShareRelayActivity 转发，避免主界面再闪启动页。
/// 始终走后台智能记账（通知 + 自动落库），不打开确认弹层（ADR-018）。
/// 支持单张与多选（`SEND_MULTIPLE`，ADR-058）。
///
/// 收到分享后尽快 [AndroidActivityBridge.moveTaskToBack]，回到分享来源
/// （如系统截图编辑）；直存期间返回键由 [AutoBillingService] 保活，不 finish。
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

    // 冷启动：原生可能已拷好文件但 invoke 早于 handler
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
        ? '$kBillingImagesTruncatedHint，准备识别…'
        : '准备识别…';

    // 先入队；FGS 须在 moveTaskToBack 前就绪，避免冷启动分享后 Dart 被挂起（ADR-054）。
    await ForegroundBillingBridge.start(
      title: '分享入账',
      body: progressBody,
    );
    await AndroidActivityBridge.setRetainOnBack(true);

    if (didTruncate) {
      autoBilling.setBatchNote(kBillingImagesTruncatedHint);
    }

    final billing = Future.wait([
      for (final path in list)
        autoBilling.processImagePath(
          path,
          source: 'share',
          showNotification: true,
          autoSave: true,
        ),
    ]);
    logger.info(
      'AutoBilling',
      '分享入账送后台 n=${list.length}'
      '${didTruncate ? ' truncated' : ''}，避免返回中断识别',
    );
    await AndroidActivityBridge.moveTaskToBack();
    await billing;
  }
}
