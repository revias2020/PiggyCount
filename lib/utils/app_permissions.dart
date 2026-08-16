import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 权限申请结果，带中文可读原因。
class PermissionOutcome {
  const PermissionOutcome({
    required this.granted,
    this.message,
    this.canOpenSettings = false,
  });

  final bool granted;
  final String? message;
  final bool canOpenSettings;
}

/// 统一权限文案与「去设置」引导，避免各入口各自拼失败提示。
abstract final class AppPermissions {
  static Future<PermissionOutcome> requestPhotos() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const PermissionOutcome(granted: true);
    }
    var status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) {
      return const PermissionOutcome(granted: true);
    }
    if (Platform.isAndroid) {
      status = await Permission.storage.request();
      if (status.isGranted) {
        return const PermissionOutcome(granted: true);
      }
    }
    final deniedForever = status.isPermanentlyDenied;
    return PermissionOutcome(
      granted: false,
      canOpenSettings: deniedForever,
      message: deniedForever
          ? '相册权限已被关闭，请到系统设置中开启后重试'
          : '需要相册权限才能读取截图或选图记账',
    );
  }

  static Future<PermissionOutcome> requestMicrophone() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      return const PermissionOutcome(granted: true);
    }
    final deniedForever = status.isPermanentlyDenied;
    return PermissionOutcome(
      granted: false,
      canOpenSettings: deniedForever,
      message: deniedForever
          ? '麦克风权限已被关闭，请到系统设置中开启后使用语音记账'
          : '需要麦克风权限才能语音记账',
    );
  }

  static Future<PermissionOutcome> requestCamera() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      return const PermissionOutcome(granted: true);
    }
    final deniedForever = status.isPermanentlyDenied;
    return PermissionOutcome(
      granted: false,
      canOpenSettings: deniedForever,
      message: deniedForever
          ? '相机权限已被关闭，请到系统设置中开启后拍照记账'
          : '需要相机权限才能拍照记账',
    );
  }

  static Future<PermissionOutcome> requestNotification() async {
    if (!Platform.isAndroid) {
      return const PermissionOutcome(granted: true);
    }
    final status = await Permission.notification.request();
    if (status.isGranted) {
      return const PermissionOutcome(granted: true);
    }
    // 通知非强依赖：失败不阻断主流程
    return const PermissionOutcome(
      granted: false,
      message: '未开启通知权限，自动记账进度将无法在通知栏提示',
    );
  }

  /// SnackBar + 可选「去设置」。
  static void showDenied(
    BuildContext context,
    PermissionOutcome outcome,
  ) {
    if (outcome.granted || outcome.message == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(outcome.message!),
        action: outcome.canOpenSettings
            ? SnackBarAction(
                label: '去设置',
                onPressed: openAppSettings,
              )
            : null,
      ),
    );
  }
}
