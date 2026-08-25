import 'dart:io';

import 'package:flutter/services.dart';

/// Android 后台直存批次前台服务桥（ADR-054）。
class ForegroundBillingBridge {
  ForegroundBillingBridge._();

  static const _channel = MethodChannel('com.xiaozhu.piggy_count/activity');

  static var _active = false;

  static bool get isActive => _active;

  static Future<void> start({
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startBillingForeground', {
        'title': title,
        'body': body,
      });
      _active = true;
    } catch (_) {}
  }

  static Future<void> update({
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('updateBillingForeground', {
        'title': title,
        'body': body,
      });
      _active = true;
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopBillingForeground');
    } catch (_) {}
    _active = false;
  }
}
