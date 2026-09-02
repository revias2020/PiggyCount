import 'dart:io';

import 'package:flutter/services.dart';

import '../system/logger_service.dart';

/// Android 后台直存批次前台服务桥（ADR-054 / 063）。
class ForegroundBillingBridge {
  ForegroundBillingBridge._();

  static const _channel = MethodChannel('com.xiaozhu.piggy_count/activity');

  static var _active = false;

  static bool get isActive => _active;

  /// 起或刷新进度通知。原生 start/update 先同 id 直发再
  /// `startForegroundService` + `startForeground`（ADR-066 / 069）；即便 ShareRelay
  /// 已起 FGS，Dart 仍须再调一次以对齐 [_active]（ADR-063）。
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
    } catch (e) {
      logger.warning(
        'AutoBilling',
        'FGS start failed title=$title body=$body err=$e',
      );
    }
  }

  /// 与 [start] 同实现；保留方法名方便调用方区分语义（首启 vs 改文案）。
  static Future<void> update({
    required String title,
    required String body,
  }) =>
      start(title: title, body: body);

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopBillingForeground');
    } catch (e) {
      logger.warning('AutoBilling', 'FGS stop failed err=$e');
    }
    _active = false;
  }
}
