import 'dart:io';

import 'package:flutter/services.dart';

import '../../utils/app_permissions.dart';
import '../../utils/screenshot_watch_path.dart';
import '../system/logger_service.dart';
import 'auto_billing_service.dart';

/// Android 截图监听 Dart 端适配（ADR-068 / ADR-070）。
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

  /// 目录发现扫描：关键词命中图 → 去重父目录（相对路径）。
  Future<List<String>> discoverDirectories() async {
    if (!Platform.isAndroid) return const [];
    await ensurePermissionOrThrow();
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'discoverScreenshotDirectories',
    );
    return _stringList(raw);
  }

  /// 将 SAF / 绝对路径规范为相对监听目录键；无法解析则返回 null。
  Future<String?> normalizeDirectory(String raw) async {
    if (!Platform.isAndroid) {
      return ScreenshotWatchPath.normalize(raw);
    }
    final n = await _channel.invokeMethod<String>(
      'normalizeWatchDirectory',
      raw,
    );
    return n ?? ScreenshotWatchPath.normalize(raw);
  }

  /// 按当前监听目录启动；[directories] 为空则不注册 Observer（返回 false）。
  Future<bool> start({required List<String> directories}) async {
    if (!Platform.isAndroid) return false;
    await ensurePermissionOrThrow();
    _ensureHandler();
    if (directories.isEmpty) {
      await stop();
      return false;
    }
    final ok = await _channel.invokeMethod<bool>(
      'startScreenshotObserver',
      {'directories': directories},
    );
    _listening = ok == true;
    return _listening;
  }

  /// 热更新目录；空列表则停止监听。
  Future<bool> applyDirectories(List<String> directories) async {
    if (!Platform.isAndroid) return false;
    if (directories.isEmpty) {
      await stop();
      return false;
    }
    _ensureHandler();
    final ok = await _channel.invokeMethod<bool>(
      'setWatchDirectories',
      {'directories': directories},
    );
    _listening = ok == true;
    return _listening;
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopScreenshotObserver');
    } catch (_) {}
    _channel.setMethodCallHandler(null);
    _listening = false;
  }

  void _ensureHandler() {
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
  }

  static List<String> _stringList(List<dynamic>? raw) {
    if (raw == null) return const [];
    return raw.whereType<String>().where((s) => s.isNotEmpty).toList();
  }
}
