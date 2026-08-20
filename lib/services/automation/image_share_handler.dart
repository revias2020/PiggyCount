import 'package:flutter/services.dart';

import 'auto_billing_service.dart';

/// 系统分享图片入账：冷/热启动均由原生写入临时文件后经 MethodChannel 通知。
///
/// Android 热启动经透明 ShareRelayActivity 转发，避免主界面再闪启动页。
/// 始终走后台智能记账（通知 + 自动落库），不打开确认弹层（ADR-018）。
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
      if (call.method == 'onImageShared') {
        final path = call.arguments as String?;
        if (path != null) await _handle(path);
      }
    });

    // 冷启动：原生可能已拷好文件但 invoke 早于 handler
    try {
      final pending =
          await _channel.invokeMethod<String?>('getPendingSharedImage');
      if (pending != null && pending.isNotEmpty) {
        await _handle(pending);
      }
    } catch (_) {}
  }

  Future<void> _handle(String path) async {
    await autoBilling.processImagePath(
      path,
      source: 'share',
      showNotification: true,
      autoSave: true,
    );
  }
}
