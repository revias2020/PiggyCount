import 'dart:io';

import 'package:flutter/services.dart';

import '../../utils/app_permissions.dart';
import '../system/logger_service.dart';
import 'auto_billing_service.dart';

/// Android 截图监听 Dart 端适配（ADR-045 / ADR-048）。
class ScreenshotMonitorService {
  ScreenshotMonitorService(this._autoBilling);

  static const _channel = MethodChannel('com.xiaozhu.piggy_count/screenshot');

  final AutoBillingService _autoBilling;
  bool _listening = false;

  bool get isListening => _listening;

  /// 申请相册读权限；失败时抛出带中文说明的 [StateError]。
  Future<void> ensurePermissionOrThrow() async {
    if (!Platform.isAndroid) {
      throw StateError('截图静默监听仅支持 Android');
    }
    final outcome = await AppPermissions.requestPhotos();
    if (!outcome.granted) {
      throw StateError(outcome.message ?? '需要相册权限才能监听截图');
    }
    await AppPermissions.requestNotification();
  }

  Future<void> start() async {
    if (!Platform.isAndroid) return;
    if (_listening) return;

    await ensurePermissionOrThrow();

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onScreenshotDetected':
          final path = call.arguments as String?;
          if (path == null || path.isEmpty) return;
          await _autoBilling.processImagePath(
            path,
            source: 'screenshot',
            showNotification: true,
            autoSave: true,
          );
          return;
        case 'onScreenshotProgress':
          final path = call.arguments as String?;
          if (path == null || path.isEmpty) return;
          await _autoBilling.showScreenshotEarlyProgress(path);
          return;
        case 'onScreenshotSuperseded':
          final args = call.arguments;
          if (args is! Map) return;
          final oldPath = args['oldPath'] as String?;
          final newPath = args['newPath'] as String?;
          if (oldPath == null || oldPath.isEmpty) return;
          await _autoBilling.supersedeScreenshot(
            oldPath: oldPath,
            newPath: newPath,
          );
          return;
        case 'onScreenshotCancelled':
          final cancelled = call.arguments as String?;
          if (cancelled == null || cancelled.isEmpty) return;
          await _autoBilling.cancelScreenshotProgress(cancelled);
          return;
        case 'onScreenshotSettleLog':
          final message = call.arguments as String?;
          if (message == null || message.isEmpty) return;
          logger.info('Screenshot', message);
          return;
      }
    });

    await _channel.invokeMethod<void>('startScreenshotObserver');
    _listening = true;
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopScreenshotObserver');
    } catch (_) {}
    _channel.setMethodCallHandler(null);
    _listening = false;
  }
}
