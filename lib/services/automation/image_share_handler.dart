import 'package:flutter/services.dart';

import '../platform/android_activity_bridge.dart';
import '../system/logger_service.dart';
import 'auto_billing_service.dart';

/// 系统分享图片入账：冷/热启动均由原生写入临时文件后经 MethodChannel 通知。
///
/// Android 热启动经透明 ShareRelayActivity 转发，避免主界面再闪启动页。
/// 始终走后台智能记账（通知 + 自动落库），不打开确认弹层（ADR-018）。
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
    // 先入队抬升批次；再确保返回保活后送后台，最后等识别结束。
    final billing = autoBilling.processImagePath(
      path,
      source: 'share',
      showNotification: true,
      autoSave: true,
    );
    await AndroidActivityBridge.setRetainOnBack(true);
    logger.info('AutoBilling', '分享入账送后台，避免返回中断识别');
    await AndroidActivityBridge.moveTaskToBack();
    await billing;
  }
}
