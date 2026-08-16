import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../pages/transaction/image_billing_sheet.dart';
import 'auto_billing_service.dart';

/// 系统分享图片入账：冷/热启动均由原生写入临时文件后经 MethodChannel 通知。
class ImageShareHandler {
  ImageShareHandler({
    required this.autoBilling,
    required this.navigatorKey,
  });

  static const _channel = MethodChannel('com.xiaozhu.piggy_count/share');

  final AutoBillingService autoBilling;
  final GlobalKey<NavigatorState> navigatorKey;

  bool _bound = false;

  Future<void> bind() async {
    if (!Platform.isAndroid || _bound) return;
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
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      // 前台：走确认弹层，降低误记
      final bytes = await File(path).readAsBytes();
      final mime =
          path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      if (!ctx.mounted) return;
      await showImageBillingSheet(
        ctx,
        imageBytes: bytes,
        mimeType: mime,
        source: 'share',
      );
      return;
    }
    // 无 UI：后台自动落库 + 通知
    await autoBilling.processImagePath(
      path,
      source: 'share',
      showNotification: true,
      autoSave: true,
    );
  }
}
