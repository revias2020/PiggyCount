import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/settings_repository.dart';
import '../../widgets/share_after_action_dialog.dart';
import '../platform/android_activity_bridge.dart';
import '../platform/foreground_billing_bridge.dart';
import 'auto_billing_service.dart';
import 'billing_image_limits.dart';
import 'share_after_action.dart';
import 'share_early_progress_gate.dart';

/// 系统分享图片入账：冷/热启动均由原生写入临时文件后经 MethodChannel 通知。
///
/// Android 热启动经透明 ShareRelayActivity 转发，避免主界面再闪启动页。
/// 始终走后台智能记账（通知 + 自动落库），不打开确认弹层（ADR-018）。
/// 支持单张与多选（`SEND_MULTIPLE`，ADR-058）。
///
/// ShareRelay 拷图成功即贴同 id 进度并起 FGS（ADR-063 / 069；冷启先直发通知，
/// 且等 startForeground 或短超时后再进 MainActivity）；Dart 接手时
/// [ForegroundBillingBridge.acquire] `share`，**先**入队 Vision（前台建连），
/// 再按「分享入账后」策略决定是否 [AndroidActivityBridge.moveTaskToBack] 回源；
/// 结束 [release] `share`（ADR-076）。直存期间返回键由 [AutoBillingService] 保活，
/// 不 finish。
class ImageShareHandler {
  ImageShareHandler({
    required this.autoBilling,
    required this.settings,
    required this.navigatorKey,
  });

  static const _channel = MethodChannel('com.xiaozhu.piggy_count/share');

  final AutoBillingService autoBilling;
  final SettingsRepository settings;
  final GlobalKey<NavigatorState> navigatorKey;

  bool _bound = false;
  Completer<ShareAfterPromptResult?>? _askInflight;

  Future<void> bind() async {
    if (_bound) return;
    _bound = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onImagesShared') {
        final args = call.arguments;
        if (args is Map) {
          await _handlePayload(args);
        }
      }
    });

    // 冷启动：原生已拷好文件，pending 等此处取走（ADR-063，无固定 delay）
    try {
      final pending =
          await _channel.invokeMethod<dynamic>('getPendingSharedImages');
      if (pending is Map) {
        await _handlePayload(pending);
      }
    } catch (_) {}
  }

  Future<void> _handlePayload(Map<dynamic, dynamic> args) async {
    final raw = args['paths'];
    final paths = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String && e.isNotEmpty) paths.add(e);
      }
    }
    final truncated = args['truncated'] == true;
    if (paths.isEmpty) return;
    await _handle(paths: paths, truncated: truncated);
  }

  Future<void> _handle({
    required List<String> paths,
    required bool truncated,
  }) async {
    // 原生 copyUrisToCache 已截断；此处只消费 truncated 标志做文案/批次注记。
    final progressBody = shareReceivedProgressBody(truncated: truncated);

    // 始终 acquire(share)，不假设 Relay 已成功（ADR-063 / 076）。
    await ForegroundBillingBridge.acquire(
      BillingFgsOwner.share,
      title: kShareBillingProgressTitle,
      body: progressBody,
    );
    await AndroidActivityBridge.setRetainOnBack(true);

    if (truncated) {
      autoBilling.setBatchNote(kBillingImagesTruncatedHint);
    }

    try {
      // 前台先入队 Vision，避免「先回源再识别」时新建大 POST 被
      // Software caused connection abort。
      final jobs = <Future<List<int>>>[
        for (final path in paths)
          autoBilling.processImagePath(
            path,
            source: 'share',
            showNotification: true,
            autoSave: true,
          ),
      ];

      // 回源不阻塞识别；短预热让泵有机会在 resumed 下开始 POST。
      unawaited(_resolveAfterShareIngress());

      await Future.wait(jobs);
    } finally {
      await ForegroundBillingBridge.release(BillingFgsOwner.share);
    }
  }

  /// 按设置 / 弹窗决定是否回源；选返回时仍保证前台预热窗口。
  Future<void> _resolveAfterShareIngress() async {
    final started = DateTime.now();
    final preference = await settings.shareAfterAction();
    var decision = preference;

    if (preference == ShareAfterAction.ask) {
      final prompted = await _promptShareAfterAction();
      if (prompted == null) {
        decision = ShareAfterAction.retreat;
      } else {
        decision = prompted.action;
        if (prompted.setAsDefault &&
            (decision == ShareAfterAction.stay ||
                decision == ShareAfterAction.retreat)) {
          await settings.setShareAfterAction(decision);
        }
      }
    }

    if (decision == ShareAfterAction.stay) return;

    final elapsed = DateTime.now().difference(started);
    final remaining =
        ShareEarlyProgressGate.foregroundNetworkWarmup - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    await AndroidActivityBridge.moveTaskToBack();
    // moveTaskToBack 返回早于 visibility=false（热启实测约 300ms）
    await Future<void>.delayed(ShareEarlyProgressGate.backgroundSettle);
  }

  Future<ShareAfterPromptResult?> _promptShareAfterAction() async {
    if (_askInflight != null) return _askInflight!.future;
    final gate = Completer<ShareAfterPromptResult?>();
    _askInflight = gate;
    try {
      final result = await _showAskDialogWhenReady();
      gate.complete(result);
      return result;
    } catch (_) {
      gate.complete(null);
      return null;
    } finally {
      _askInflight = null;
    }
  }

  Future<ShareAfterPromptResult?> _showAskDialogWhenReady() async {
    for (var i = 0; i < 40; i++) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        return showShareAfterActionAskDialog(ctx);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }
}
