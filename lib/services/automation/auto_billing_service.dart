import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai/ai_provider_store.dart';
import '../../ai/ai_vision_failure.dart';
import '../ai/ai_bookkeeper.dart';
import '../platform/android_activity_bridge.dart';
import '../platform/foreground_billing_bridge.dart';
import '../system/logger_service.dart';
import 'billing_notification_service.dart';
import 'pending_billing_retry_store.dart';
import 'vision_image_prep.dart';

/// 批次内分桶：入账/跳过按笔；失败/阻塞按张。
class _BatchTallies {
  int success = 0;
  int skip = 0;
  double successAmount = 0;
  int blocked = 0;
  /// 失败张原因（Dialog 换行合并）；length = 失败张数。
  final List<String> failureReasons = [];

  int get failImages => failureReasons.length;

  bool get isEmpty =>
      success == 0 &&
      skip == 0 &&
      failureReasons.isEmpty &&
      blocked == 0;

  void clear() {
    success = 0;
    skip = 0;
    successAmount = 0;
    blocked = 0;
    failureReasons.clear();
  }
}

/// 结果正文：省略为 0 的段；阻塞句见纯阻塞 / 「另有」。
String formatAutoBillingResultBody({
  required int success,
  required int skip,
  required int failImages,
  required int blocked,
  double? successAmount,
  String? batchNote,
}) {
  final parts = <String>[];
  if (success > 0) {
    final amount = successAmount ?? 0;
    parts.add('入账 $success 笔（¥${amount.toStringAsFixed(2)}）');
  }
  if (skip > 0) parts.add('跳过 $skip 笔');
  if (failImages > 0) parts.add('失败 $failImages 张');
  final main = parts.join('，');
  String body;
  if (blocked > 0) {
    final blockClause = main.isEmpty
        ? '$blocked 张阻塞，打开 App 后继续'
        : '另有 $blocked 张阻塞，打开 App 后继续';
    body = main.isEmpty ? blockClause : '$main；$blockClause';
  } else {
    body = main;
  }
  final note = batchNote?.trim();
  if (note == null || note.isEmpty) return body;
  if (body.isEmpty) return note;
  return '$body（$note）';
}

/// 结果标题固定「识别结果」（截图取消除外）。
String formatAutoBillingResultTitle() => '识别结果';

/// 无失败张 → success payload（进明细，可跳笔）；有失败张 → Dialog。
bool autoBillingResultClickSuccess(int failImages) => failImages == 0;

/// 截图/分享图片 → Vision 提取 → 自动落库（后台通知渠道，ADR-018）。
class AutoBillingService {
  AutoBillingService({
    required this.bookkeeper,
    required this.resolveLedgerId,
    BillingNotificationService? notifications,
    AiProviderStore? providerStore,
    PendingBillingRetryStore? retryStore,
    this.onAutoSaved,
  })  : notifications = notifications ?? BillingNotificationService(),
        _providerStore = providerStore ?? AiProviderStore(),
        _retryStore = retryStore ?? PendingBillingRetryStore();

  final AiBookkeeper bookkeeper;
  final Future<int?> Function() resolveLedgerId;
  final BillingNotificationService notifications;
  final AiProviderStore _providerStore;
  final PendingBillingRetryStore _retryStore;
  /// 后台直存成功后的钩子（待核对等）；参数为本地 id 列表、source、ledgerId。
  final Future<void> Function(
    List<int> ids,
    String source,
    int ledgerId,
  )? onAutoSaved;

  static const _processedKey = 'piggy_processed_screenshots';
  static const _dupWindowMs = 5000;
  static const _fileWaitMs = 3000;

  final Set<String> _processed = {};
  /// 被系统预览「另存新文件+删原」取代的路径；识别中遇到则放弃落库（ADR-048）。
  final Set<String> _superseded = {};
  String? _lastPath;
  int _lastTime = 0;
  bool _loaded = false;

  /// 当前正在 Vision/落库的图片路径（用于替换时取消进度）。
  String? _inflightPath;
  /// 替换后尚未收到门闩回调的新路径；避免空批次把进度通知清掉。
  String? _awaitingScreenshotPath;

  /// 多张串行：后一张等前一张结束（ADR-018）。
  Future<void> _queue = Future.value();

  /// 当前串行批次仍在排队/执行的任务数；归零时刷新结果通知。
  int _batchInflight = 0;
  final _BatchTallies _batchTallies = _BatchTallies();
  /// 本批次附加说明（如多选分享截取，ADR-058）；随结果通知一并展示后清空。
  String? _pendingBatchNote;
  var _retryDrainRunning = false;

  bool _isAppResumed() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  Future<void> _showProgress({
    required String title,
    required String body,
  }) async {
    final t = _retryDrainRunning ? '识别继续' : title;
    final b = _retryDrainRunning ? '继续调用AI分析' : body;
    if (ForegroundBillingBridge.isActive) {
      await ForegroundBillingBridge.update(title: t, body: b);
      return;
    }
    await notifications.showProgress(title: t, body: b);
  }

  Future<void> _cancelProgress() async {
    if (ForegroundBillingBridge.isActive) return;
    await notifications.cancelProgress();
  }

  Future<void> _startBatchForeground() async {
    if (!Platform.isAndroid) return;
    if (ForegroundBillingBridge.isActive) return;
    await ForegroundBillingBridge.start(
      title: _retryDrainRunning ? '识别继续' : '智能记账',
      body: _retryDrainRunning ? '继续调用AI分析' : '准备识别…',
    );
  }

  Future<void> _stopBatchForeground() async {
    await ForegroundBillingBridge.stop();
  }

  Future<bool> _maybeEnqueueTransportRetry({
    required String imagePath,
    required String source,
    required bool showNotification,
  }) async {
    if (_isAppResumed()) return false;
    if (source != 'screenshot' && source != 'share') return false;
    await _retryStore.enqueue(
      PendingBillingRetryItem(
        imagePath: imagePath,
        source: source,
        enqueuedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    logger.info(
      'AutoBilling',
      '传输失败已入阻塞队列 source=$source file=${p.basename(imagePath)}',
    );
    if (showNotification) {
      _batchTallies.blocked++;
    }
    return true;
  }

  /// App 回前台时重试后台直存阻塞项（ADR-054）。
  Future<void> retryPendingOnResume() async {
    if (_retryDrainRunning) return;
    _retryDrainRunning = true;
    try {
      final items = await _retryStore.load();
      if (items.isEmpty) return;
      logger.info('AutoBilling', '回前台重试 ${items.length} 项');
      await _showProgress(title: '识别继续', body: '继续调用AI分析');
      for (final item in items) {
        if (!await File(item.imagePath).exists()) {
          await _retryStore.remove(item.imagePath);
          continue;
        }
        await _retryStore.remove(item.imagePath);
        await processImagePath(
          item.imagePath,
          source: item.source,
          showNotification: true,
          autoSave: true,
        );
      }
    } finally {
      _retryDrainRunning = false;
    }
  }

  /// 为即将开始的串行批次附加结果通知文案（ADR-058）。
  void setBatchNote(String? note) {
    final t = note?.trim();
    _pendingBatchNote = (t == null || t.isEmpty) ? null : t;
  }

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

  void _recordBillTallies({
    required int success,
    required int skip,
    double successAmount = 0,
  }) {
    _batchTallies.success += success;
    _batchTallies.skip += skip;
    _batchTallies.successAmount += successAmount;
  }

  void _recordFailedImage({required String title, required String body}) {
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty) {
      _batchTallies.failureReasons.add(b.isEmpty ? '识别失败' : b);
    } else if (b.isEmpty || b == t) {
      _batchTallies.failureReasons.add(t);
    } else {
      _batchTallies.failureReasons.add('$t：$b');
    }
  }

  Future<void> _flushBatchResults() async {
    final t = _BatchTallies()
      ..success = _batchTallies.success
      ..skip = _batchTallies.skip
      ..successAmount = _batchTallies.successAmount
      ..blocked = _batchTallies.blocked
      ..failureReasons.addAll(_batchTallies.failureReasons);
    final batchNote = _pendingBatchNote;
    _pendingBatchNote = null;
    _batchTallies.clear();

    if (t.isEmpty) {
      if (_inflightPath == null && _awaitingScreenshotPath == null) {
        await _cancelProgress();
      }
      return;
    }

    final body = formatAutoBillingResultBody(
      success: t.success,
      skip: t.skip,
      failImages: t.failImages,
      blocked: t.blocked,
      successAmount: t.successAmount,
      batchNote: batchNote,
    );
    final title = formatAutoBillingResultTitle();
    final opensDetails = autoBillingResultClickSuccess(t.failImages);
    await notifications.showResult(
      title: title,
      body: body,
      success: opensDetails,
    );
    if (!opensDetails) {
      notifications.lastFailureTitle = title;
      notifications.lastFailureBody = t.failureReasons.join('\n');
    }
  }

  /// 检出即早期进度（关联窗未满；不 Vision / 不落库）。
  /// 原生已先起 FGS；此处再 [ForegroundBillingBridge.start] 对齐 [_active]（同 ADR-063 分享）。
  Future<void> showScreenshotEarlyProgress(String imagePath) async {
    if (_superseded.contains(imagePath)) return;
    await ForegroundBillingBridge.start(
      title: '检测到截图',
      body: '等待确认后识别…',
    );
  }

  /// 原生判定截图被编辑另存替换：取消旧路径入账意图。
  Future<void> supersedeScreenshot({
    required String oldPath,
    String? newPath,
  }) async {
    _superseded.add(oldPath);
    if (_superseded.length > 40) {
      final drop = _superseded.take(20).toList();
      _superseded.removeAll(drop);
    }
    _awaitingScreenshotPath = newPath;
    await _showProgress(
      title: '截图已更新',
      body: '改用编辑后的图片识别…',
    );
  }

  /// 预览删除且删原短等无后继 / 门闩丢原：清进度并结果通知（ADR-068）。
  Future<void> cancelScreenshotProgress(String imagePath) async {
    if (_superseded.contains(imagePath)) {
      if (ForegroundBillingBridge.isActive) {
        await ForegroundBillingBridge.stop();
      } else {
        await notifications.cancelProgress();
      }
      return;
    }
    _superseded.add(imagePath);
    if (_superseded.length > 40) {
      final drop = _superseded.take(20).toList();
      _superseded.removeAll(drop);
    }
    if (_awaitingScreenshotPath == imagePath) {
      _awaitingScreenshotPath = null;
    }
    if (ForegroundBillingBridge.isActive) {
      await ForegroundBillingBridge.stop();
    }
    await notifications.showResult(
      title: '截图已取消，未入账',
      body: '编辑超时或原图已删除',
      success: false,
    );
  }

  /// 处理本地图片路径；成功返回交易 id 列表。
  Future<List<int>> processImagePath(
    String imagePath, {
    required String source,
    bool showNotification = true,
    bool autoSave = true,
  }) {
    if (_awaitingScreenshotPath == imagePath) {
      _awaitingScreenshotPath = null;
    }
    final done = Completer<List<int>>();
    final startsBatch = _batchInflight == 0;
    _batchInflight++;
    if (_batchInflight == 1) {
      // 批次开始：返回键送后台，避免 finish 拆引擎
      unawaited(AndroidActivityBridge.setRetainOnBack(true));
    }
    _queue = _queue.then((_) async {
      try {
        if (startsBatch) {
          await _startBatchForeground();
        }
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
          await _stopBatchForeground();
          try {
            await _flushBatchResults();
          } catch (_) {
            _batchTallies.clear();
          }
          await AndroidActivityBridge.setRetainOnBack(false);
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
    if (_superseded.contains(imagePath)) {
      return const [];
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastPath == imagePath && now - _lastTime < _dupWindowMs) {
      return const [];
    }
    _lastPath = imagePath;
    _lastTime = now;

    final fileName = p.basename(imagePath);

    final fallbackProviders = await _providerStore.listVisionFallbackProviders();
    if (fallbackProviders.isEmpty) {
      logger.warning('AutoBilling', '能力未就绪 source=$source');
      if (showNotification) {
        _recordFailedImage(
          title: '无法自动记账',
          body: '未绑定已测通的视觉服务商，请到「我的 → AI 设置」配置',
        );
      }
      return const [];
    }

    final file = File(imagePath);
    _inflightPath = imagePath;
    try {
      if (showNotification) {
        await _showProgress(title: '检测到图片', body: '等待文件就绪…');
      }

      final ready = await _waitFile(file);
      if (_superseded.contains(imagePath)) {
        return const [];
      }
      if (!ready) {
        logger.warning('AutoBilling', '文件不可读 source=$source file=$fileName');
        if (showNotification) {
          _recordFailedImage(
            title: '文件不可用',
            body: '截图尚未可读，请稍后通过记一笔扇形「图片」重试。',
          );
        }
        return const [];
      }

      if (showNotification) {
        await _showProgress(title: '正在识别', body: 'AI 分析账单中…');
      }

      try {
        final rawBytes = await file.readAsBytes();
        if (_superseded.contains(imagePath)) {
          return const [];
        }
        final mime = imagePath.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        final prepared = await prepareVisionImageForUpload(
          rawBytes,
          mimeType: mime,
        );
        final bills = await bookkeeper.fromImageWithFallback(
          prepared.bytes,
          mimeType: prepared.mimeType,
        );
        if (_superseded.contains(imagePath)) {
          return const [];
        }
        await _mark(imagePath);

        if (bills.isEmpty) {
          logger.warning('AutoBilling', '非账单 source=$source file=$fileName');
          if (showNotification) {
            _recordFailedImage(
              title: '未识别到账单',
              body: '该图可能不是支付截图',
            );
          }
          return const [];
        }

        if (!autoSave) {
          if (showNotification) await _cancelProgress();
          return const [];
        }

        final ledgerId = await resolveLedgerId();
        if (ledgerId == null) {
          logger.error('AutoBilling', '未找到账本 source=$source');
          if (showNotification) {
            _recordFailedImage(
              title: '无法自动记账',
              body: '未找到账本',
            );
          }
          return const [];
        }

        if (_superseded.contains(imagePath)) {
          return const [];
        }

        final saved = await bookkeeper.saveBills(
          bills: bills,
          ledgerId: ledgerId,
          source: source,
        );

        if (saved.ids.isEmpty) {
          logger.warning(
            'AutoBilling',
            '保存无成功笔 source=$source '
            'skip=${saved.skipped} fail=${saved.failed}',
          );
        } else {
          try {
            await onAutoSaved?.call(saved.ids, source, ledgerId);
          } catch (e, st) {
            logger.error('AutoBilling', 'onAutoSaved 失败 source=$source', e, st);
          }
        }

        if (showNotification) {
          _recordBillTallies(
            success: saved.ids.length,
            skip: saved.skipped,
            successAmount: saved.savedAmount,
          );
          if (saved.failed > 0) {
            _recordFailedImage(
              title: '落库失败',
              body: '有 ${saved.failed} 笔未能保存',
            );
          }
        }
        return saved.ids;
      } on AiVisionExhaustedException catch (e, st) {
        if (_superseded.contains(imagePath)) return const [];
        if (e.kind == AiVisionFailureKind.transport &&
            await _maybeEnqueueTransportRetry(
              imagePath: imagePath,
              source: source,
              showNotification: showNotification,
            )) {
          return const [];
        }
        logger.error(
          'AutoBilling',
          '${e.notificationTitle} source=$source',
          e,
          st,
        );
        if (showNotification) {
          _recordFailedImage(
            title: e.notificationTitle,
            body: e.notificationBody(),
          );
        }
        return const [];
      } catch (e, st) {
        if (_superseded.contains(imagePath)) return const [];
        final msg = '$e';
        final isDuplicate = msg.contains('已存在相同账本');
        final isTransport = isAiTransportFailure(e);
        if (isTransport &&
            await _maybeEnqueueTransportRetry(
              imagePath: imagePath,
              source: source,
              showNotification: showNotification,
            )) {
          return const [];
        }
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
          if (isDuplicate) {
            // 理论上 saveBills 已分桶；外层仍见撞车则记 1 跳过
            _recordBillTallies(success: 0, skip: 1);
          } else {
            _recordFailedImage(title: failTitle, body: msg);
          }
        }
        return const [];
      }
    } finally {
      if (_inflightPath == imagePath) _inflightPath = null;
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
