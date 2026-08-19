import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai/ai_provider_config.dart';
import '../../ai/ai_provider_store.dart';
import '../ai/ai_bookkeeper.dart';
import '../system/logger_service.dart';
import 'billing_notification_service.dart';

/// 截图/分享图片 → Vision 提取 → 自动落库（后台通知渠道，ADR-018）。
class AutoBillingService {
  AutoBillingService({
    required this.bookkeeper,
    required this.resolveLedgerId,
    BillingNotificationService? notifications,
    AiProviderStore? providerStore,
  })  : notifications = notifications ?? BillingNotificationService(),
        _providerStore = providerStore ?? AiProviderStore();

  final AiBookkeeper bookkeeper;
  final Future<int?> Function() resolveLedgerId;
  final BillingNotificationService notifications;
  final AiProviderStore _providerStore;

  static const _processedKey = 'piggy_processed_screenshots';
  static const _dupWindowMs = 5000;
  static const _fileWaitMs = 3000;

  final Set<String> _processed = {};
  String? _lastPath;
  int _lastTime = 0;
  bool _loaded = false;

  /// 多张串行：后一张等前一张结束（ADR-018）。
  Future<void> _queue = Future.value();

  Future<void> _ensureCache() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _processed.addAll(prefs.getStringList(_processedKey) ?? const []);
    _loaded = true;
  }

  Future<void> _mark(String path) async {
    _processed.add(path);
    final prefs = await SharedPreferences.getInstance();
    var list = _processed.toList();
    if (list.length > 100) {
      list = list.sublist(list.length - 100);
      _processed
        ..clear()
        ..addAll(list);
    }
    await prefs.setStringList(_processedKey, list);
  }

  /// 处理本地图片路径；成功返回交易 id 列表。
  Future<List<int>> processImagePath(
    String imagePath, {
    required String source,
    bool showNotification = true,
    bool autoSave = true,
  }) {
    final done = Completer<List<int>>();
    _queue = _queue.then((_) async {
      try {
        final ids = await _processImagePathLocked(
          imagePath,
          source: source,
          showNotification: showNotification,
          autoSave: autoSave,
        );
        done.complete(ids);
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  Future<List<int>> _processImagePathLocked(
    String imagePath, {
    required String source,
    required bool showNotification,
    required bool autoSave,
  }) async {
    await _ensureCache();
    // 已处理 / 短窗去重：静默跳过，不打点（ADR-022）
    if (_processed.contains(imagePath)) return const [];

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastPath == imagePath && now - _lastTime < _dupWindowMs) {
      return const [];
    }
    _lastPath = imagePath;
    _lastTime = now;

    final fileName = p.basename(imagePath);
    logger.info('AutoBilling', '触发 source=$source file=$fileName');

    late final AiServiceProvider provider;
    try {
      provider = await _providerStore.resolve(AiCapabilityKind.vision);
    } on AiCapabilityNotReadyException catch (e) {
      logger.warning('AutoBilling', '能力未就绪 source=$source: ${e.message}');
      if (showNotification) {
        await notifications.showResult(
          title: '无法自动记账',
          body: e.message,
          success: false,
        );
      }
      return const [];
    }

    final file = File(imagePath);
    if (showNotification) {
      await notifications.showProgress(title: '检测到图片', body: '等待文件就绪…');
    }

    final ready = await _waitFile(file);
    if (!ready) {
      logger.warning('AutoBilling', '文件不可读 source=$source file=$fileName');
      if (showNotification) {
        await notifications.showResult(
          title: '文件不可用',
          body: '截图尚未可读，请稍后通过记一笔扇形「图片」重试。',
          success: false,
        );
      }
      return const [];
    }

    logger.info(
      'AutoBilling',
      '开始识别 source=$source provider=${provider.name} '
      'model=${provider.visionModel}',
    );

    if (showNotification) {
      await notifications.showProgress(title: '正在识别', body: 'AI 分析账单中…');
    }

    try {
      final bytes = await file.readAsBytes();
      final mime = imagePath.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      final bills = await bookkeeper.fromImage(bytes, mimeType: mime);
      await _mark(imagePath);

      if (bills.isEmpty) {
        logger.warning('AutoBilling', '非账单 source=$source file=$fileName');
        if (showNotification) {
          await notifications.showResult(
            title: '未识别到账单',
            body: '该图可能不是支付截图',
            success: false,
          );
        }
        return const [];
      }

      if (!autoSave) {
        if (showNotification) await notifications.cancelProgress();
        return const [];
      }

      final ledgerId = await resolveLedgerId();
      if (ledgerId == null) {
        logger.error('AutoBilling', '未找到账本 source=$source');
        if (showNotification) {
          await notifications.showResult(
            title: '记账失败',
            body: '未找到账本',
            success: false,
          );
        }
        return const [];
      }

      final ids = await bookkeeper.saveBills(
        bills: bills,
        ledgerId: ledgerId,
        source: source,
      );

      if (ids.isEmpty) {
        logger.warning('AutoBilling', '保存失败 source=$source');
      } else {
        logger.info('AutoBilling', '自动入账 ${ids.length} 笔 source=$source');
      }

      if (showNotification) {
        final total = bills.fold<double>(0, (a, b) => a + (b.amount ?? 0));
        final ok = ids.isNotEmpty;
        await notifications.showResult(
          title: ok ? '自动记账成功' : '保存失败',
          body: ok
              ? '已入账 ${ids.length} 笔，合计 ¥${total.toStringAsFixed(2)}'
              : '请打开 App 手动确认',
          success: ok,
        );
      }
      return ids;
    } catch (e, st) {
      logger.error('AutoBilling', '识别失败 source=$source', e, st);
      debugPrint('AutoBilling failed: $e');
      if (showNotification) {
        await notifications.showResult(
          title: '识别失败',
          body: '$e',
          success: false,
        );
      }
      return const [];
    }
  }

  Future<bool> _waitFile(File file) async {
    final start = DateTime.now().millisecondsSinceEpoch;
    while (DateTime.now().millisecondsSinceEpoch - start < _fileWaitMs) {
      if (await file.exists() && await file.length() > 0) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return await file.exists() && await file.length() > 0;
  }
}
