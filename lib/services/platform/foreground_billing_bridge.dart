import 'dart:io';

import 'package:flutter/services.dart';

import '../system/logger_service.dart';

/// 后台直存 FGS / 进度 1001 的持有者（ADR-076）。
enum BillingFgsOwner {
  /// 截图关联窗早期进度。
  assoc,

  /// 分享入站 / 插队等待 / 分享识别。
  share,

  /// 门闩后 Vision 批次（含补扫）。
  batch,

  /// 阻塞队列回前台重试。
  retry,
}

/// 持有者集合（可单测）；空才允许 stop FGS。
class BillingFgsOwnerSet {
  final Set<BillingFgsOwner> _owners = {};

  bool get isEmpty => _owners.isEmpty;

  bool get isNotEmpty => _owners.isNotEmpty;

  bool contains(BillingFgsOwner owner) => _owners.contains(owner);

  Set<BillingFgsOwner> get snapshot => Set.unmodifiable(_owners);

  /// 返回是否从空变为非空（需要 start FGS）。
  bool acquire(BillingFgsOwner owner) {
    final wasEmpty = _owners.isEmpty;
    _owners.add(owner);
    return wasEmpty;
  }

  /// 返回是否变为空（需要 stop FGS）。
  bool release(BillingFgsOwner owner) {
    _owners.remove(owner);
    return _owners.isEmpty;
  }

  void clear() => _owners.clear();
}

/// Android 后台直存批次前台服务桥（ADR-054 / 063 / 076）。
class ForegroundBillingBridge {
  ForegroundBillingBridge._();

  static const _channel = MethodChannel('com.xiaozhu.piggy_count/activity');

  static var _active = false;
  static final BillingFgsOwnerSet owners = BillingFgsOwnerSet();

  static bool get isActive => _active;

  static bool hasOwner(BillingFgsOwner owner) => owners.contains(owner);

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

  /// 登记 [owner]；必要时起 FGS / 刷新文案（ADR-076）。
  ///
  /// [updateText] 为 false 且已在跑时只加持有者、不改通知文案（如 retry 相位下再挂 batch）。
  static Future<void> acquire(
    BillingFgsOwner owner, {
    required String title,
    required String body,
    bool updateText = true,
  }) async {
    if (!Platform.isAndroid) return;
    final first = owners.acquire(owner);
    if (first || updateText || !_active) {
      await start(title: title, body: body);
    }
  }

  /// 释放 [owner]；集合空时才真正 stop（ADR-076）。
  static Future<void> release(BillingFgsOwner owner) async {
    if (!Platform.isAndroid) return;
    if (!owners.contains(owner)) return;
    final nowEmpty = owners.release(owner);
    if (nowEmpty) {
      await stop();
    }
  }

  /// 批次结束：清空全部持有者并 stop，再发结果通知（ADR-076）。
  static Future<void> releaseAll() async {
    if (!Platform.isAndroid) return;
    owners.clear();
    await stop();
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
