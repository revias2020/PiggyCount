import 'dart:io';

import 'package:flutter/services.dart';

import '../system/logger_service.dart';

/// Android 后台直存批次前台服务桥（ADR-054 / 063）。
class ForegroundBillingBridge {
  ForegroundBillingBridge._();

  static const _channel = MethodChannel('com.xiaozhu.piggy_count/activity');

  static var _active = false;

  static bool get isActive => _active;

  /// 始终走 [startBillingForeground]（`startForegroundService`），即便 ShareRelay 已起 FGS。
  /// 禁止仅凭假设将 [_active] 置真后只 update——update 用 `startService`，FGS 未真跑时会丢早期通知。
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
    } catch (e) {
      logger.warning(
        'AutoBilling',
        'FGS update failed title=$title body=$body err=$e',
      );
    }
  }

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
