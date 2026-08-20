import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai/ai_provider_store.dart';
import '../../ai/ai_vision_failure.dart';
import '../ai/ai_bookkeeper.dart';
import '../system/logger_service.dart';
import 'billing_notification_service.dart';
import 'vision_image_prep.dart';

/// 单张图在批次中的结果档（静默去重不入档）。
enum _BillingOutcomeKind { success, skip, fail }

class _PendingOutcome {
  const _PendingOutcome({
    required this.kind,
    required this.title,
    required this.body,
  });

  final _BillingOutcomeKind kind;
  final String title;
  final String body;
}

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

  /// 当前串行批次仍在排队/执行的任务数；归零时刷新结果通知。
  int _batchInflight = 0;
  final List<_PendingOutcome> _batchOutcomes = [];

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

  void _recordOutcome(_PendingOutcome outcome) {
    _batchOutcomes.add(outcome);
  }

  Future<void> _flushBatchResults() async {
    final outcomes = List<_PendingOutcome>.from(_batchOutcomes);
    _batchOutcomes.clear();
    if (outcomes.isEmpty) {
      await notifications.cancelProgress();
      return;
    }

    if (outcomes.length == 1) {
      final o = outcomes.first;
      await notifications.showResult(
        title: o.title,
        body: o.body,
        success: o.kind == _BillingOutcomeKind.success,
      );
      return;
    }

    var success = 0;
    var skip = 0;
    var fail = 0;
    for (final o in outcomes) {
      switch (o.kind) {
        case _BillingOutcomeKind.success:
          success++;
        case _BillingOutcomeKind.skip:
          skip++;
        case _BillingOutcomeKind.fail:
          fail++;
      }
    }

    final body = '成功 $success 笔，跳过 $skip 笔，失败 $fail 笔';
    final title = fail > 0
        ? '自动记账完成'
        : (success > 0 ? '自动记账成功' : '记账取消');
    // 仅失败 > 0 走失败点击路径；仅跳过仍算成功路径。
    await notifications.showResult(
      title: title,
      body: body,
      success: fail == 0,
    );
  }

  /// 处理本地图片路径；成功返回交易 id 列表。
  Future<List<int>> processImagePath(
    String imagePath, {
    required String source,
    bool showNotification = true,
    bool autoSave = true,
  }) {
    final done = Completer<List<int>>();
    _batchInflight++;
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
      } finally {
        _batchInflight--;
        if (_batchInflight == 0) {
          try {
            await _flushBatchResults();
          } catch (_) {
            _batchOutcomes.clear();
          }
        }
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

    final fallbackProviders = await _providerStore.listVisionFallbackProviders();
    if (fallbackProviders.isEmpty) {
      logger.warning('AutoBilling', '能力未就绪 source=$source');
      if (showNotification) {
        _recordOutcome(
          const _PendingOutcome(
            kind: _BillingOutcomeKind.fail,
            title: '无法自动记账',
            body: '未绑定已测通的视觉服务商，请到「我的 → AI 设置」配置',
          ),
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
        _recordOutcome(
          const _PendingOutcome(
            kind: _BillingOutcomeKind.fail,
            title: '文件不可用',
            body: '截图尚未可读，请稍后通过记一笔扇形「图片」重试。',
          ),
        );
      }
      return const [];
    }

    logger.info(
      'AutoBilling',
      '开始识别 source=$source providers=${fallbackProviders.length} '
      'primary=${fallbackProviders.first.name}',
    );

    if (showNotification) {
      await notifications.showProgress(title: '正在识别', body: 'AI 分析账单中…');
    }

    try {
      final rawBytes = await file.readAsBytes();
      final mime = imagePath.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      final prepared = await prepareVisionImageForUpload(
        rawBytes,
        mimeType: mime,
      );
      if (prepared.bytes.length != rawBytes.length ||
          prepared.mimeType != mime) {
        logger.info(
          'AutoBilling',
          '图片已压缩 source=$source '
          '${rawBytes.length}→${prepared.bytes.length} bytes',
        );
      }
      final bills = await bookkeeper.fromImageWithFallback(
        prepared.bytes,
        mimeType: prepared.mimeType,
      );
      await _mark(imagePath);

      if (bills.isEmpty) {
        logger.warning('AutoBilling', '非账单 source=$source file=$fileName');
        if (showNotification) {
          _recordOutcome(
            const _PendingOutcome(
              kind: _BillingOutcomeKind.fail,
              title: '未识别到账单',
              body: '该图可能不是支付截图',
            ),
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
          _recordOutcome(
            const _PendingOutcome(
              kind: _BillingOutcomeKind.fail,
              title: '记账失败',
              body: '未找到账本',
            ),
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
        _recordOutcome(
          _PendingOutcome(
            kind: ok ? _BillingOutcomeKind.success : _BillingOutcomeKind.fail,
            title: ok ? '自动记账成功' : '保存失败',
            body: ok
                ? '已入账 ${ids.length} 笔，合计 ¥${total.toStringAsFixed(2)}'
                : '请打开 App 手动确认',
          ),
        );
      }
      return ids;
    } on AiVisionExhaustedException catch (e, st) {
      logger.error(
        'AutoBilling',
        '${e.notificationTitle} source=$source',
        e,
        st,
      );
      if (showNotification) {
        _recordOutcome(
          _PendingOutcome(
            kind: _BillingOutcomeKind.fail,
            title: e.notificationTitle,
            body: e.notificationBody(),
          ),
        );
      }
      return const [];
    } catch (e, st) {
      final msg = '$e';
      final isDuplicate = msg.contains('已存在相同账本');
      final isTransport = isAiTransportFailure(e);
      final failTitle = isDuplicate
          ? '记账取消'
          : (isTransport ? '网络异常' : '识别失败');
      logger.error(
        'AutoBilling',
        isDuplicate ? '记账取消 source=$source' : '$failTitle source=$source',
        e,
        st,
      );
      debugPrint('AutoBilling failed: $e');
      if (showNotification) {
        _recordOutcome(
          _PendingOutcome(
            kind: isDuplicate
                ? _BillingOutcomeKind.skip
                : _BillingOutcomeKind.fail,
            title: isDuplicate ? '记账取消' : failTitle,
            body: msg,
          ),
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
