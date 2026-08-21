import 'dart:io';

import 'package:flutter/services.dart';

/// Android [MainActivity] 保活：后台直存时避免返回键 finish 掉 Flutter 引擎。
class AndroidActivityBridge {
  AndroidActivityBridge._();

  static const _channel = MethodChannel('com.xiaozhu.piggy_count/activity');

  /// 为 true 时系统返回键改为 [moveTaskToBack]，不销毁 Activity。
  static Future<void> setRetainOnBack(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setRetainOnBack', enabled);
    } catch (_) {}
  }

  /// 将任务送入后台，回到分享来源（如截图编辑）。
  static Future<void> moveTaskToBack() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('moveTaskToBack');
    } catch (_) {}
  }
}
