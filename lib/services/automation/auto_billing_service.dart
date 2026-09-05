import 'dart:async';
import 'dart:collection';
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
import 'billing_image_limits.dart';
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

  void copyFrom(_BatchTallies other) {
    success = other.success;
    skip = other.skip;
    successAmount = other.successAmount;
    blocked = other.blocked;
    failureReasons
      ..clear()
      ..addAll(other.failureReasons);
  }
}

class _BillingJob {
  _BillingJob({
    required this.imagePath,
    required this.source,
    required this.showNotification,
    required this.autoSave,
    this.fromRetry = false,
  });

  final String imagePath;
  final String source;
  final bool showNotification;
  final bool autoSave;
  /// 来自阻塞队列回前台重试（ADR-076：仅此类 job 用「识别继续」文案）。
  final bool fromRetry;
  final Completer<List<int>> done = Completer<List<int>>();

  bool get isShare => source == 'share';
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
  /// 当前 inflight 的 source（ADR-075 等待提示 / 段切换）。
  String? _inflightSource;
  /// 当前 inflight 是否来自阻塞重试（ADR-076）。
  var _inflightFromRetry = false;
  /// 替换后尚未收到门闩回调的新路径；避免空批次把进度通知清掉。
  String? _awaitingScreenshotPath;
  /// 关联窗内路径（多候选共用一个 assoc holder；ADR-076）。
  final Set<String> _assocPaths = {};

  /// 高优先级：share；低优先级：screenshot 等（ADR-075）。
  final Queue<_BillingJob> _highQueue = Queue<_BillingJob>();
  final Queue<_BillingJob> _lowQueue = Queue<_BillingJob>();
  var _pumpRunning = false;

  final _BatchTallies _screenshotTallies = _BatchTallies();
  final _BatchTallies _shareTallies = _BatchTallies();
  /// 记录 tallies 时的 source（由 pump 设置）。
  String? _recordingSource;
  /// 分享批次附加说明（如多选截取，ADR-058）；随整批结果通知展示后清空。
  String? _pendingShareBatchNote;
  var _retryDrainRunning = false;

  static const _shareWaitBody = '等待当前识别结束后处理分享…';

  bool _isAppResumed() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  _BatchTallies _talliesFor(String? source) =>
      source == 'share' ? _shareTallies : _screenshotTallies;

  /// 分享插队等待提示（扩 ADR-075 / ADR-076）：inflight 截图、关联窗、或低优队将被挡住。
  bool _needsShareWaitHint() {
    return _inflightSource == 'screenshot' ||
        _assocPaths.isNotEmpty ||
        ForegroundBillingBridge.hasOwner(BillingFgsOwner.assoc) ||
        _lowQueue.isNotEmpty;
  }

  Future<void> _showProgress({
    required String title,
    required String body,
  }) async {
    // ADR-076：不再用 _retryDrainRunning 全局劫持文案。
    if (ForegroundBillingBridge.isActive) {
      await ForegroundBillingBridge.update(title: title, body: body);
      return;
    }
    await notifications.showProgress(title: title, body: body);
  }

  Future<void> _cancelProgress() async {
    if (ForegroundBillingBridge.isActive) return;
    await notifications.cancelProgress();
  }

  Future<void> _startBatchForeground() async {
    if (!Platform.isAndroid) return;
    final keepRetryCopy =
        ForegroundBillingBridge.hasOwner(BillingFgsOwner.retry);
    await ForegroundBillingBridge.acquire(
      BillingFgsOwner.batch,
      title: keepRetryCopy ? '识别继续' : '智能记账',
      body: keepRetryCopy ? '继续调用AI分析' : '准备识别…',
      updateText: !keepRetryCopy,
    );
  }

  Future<void> _stopBatchForeground() async {
    // ADR-076：整批结束清空全部 holder 再发结果，避免残留 share/assoc。
    await ForegroundBillingBridge.releaseAll();
  }

  Future<void> _refreshProgressAfterAssocCancel() async {
    if (!ForegroundBillingBridge.isActive) return;
    if (_needsShareWaitHint() &&
        (ForegroundBillingBridge.hasOwner(BillingFgsOwner.share) ||
            _highQueue.isNotEmpty)) {
      await _showProgress(
        title: kShareBillingProgressTitle,
        body: _shareWaitBody,
      );
      return;
    }
    if (ForegroundBillingBridge.hasOwner(BillingFgsOwner.share)) {
      await _showProgress(
        title: kShareBillingProgressTitle,
        body: shareReceivedProgressBody(truncated: false),
      );
      return;
    }
    if (ForegroundBillingBridge.hasOwner(BillingFgsOwner.retry) ||
        _inflightFromRetry) {
      await _showProgress(title: '识别继续', body: '继续调用AI分析');
      return;
    }
    if (_inflightPath != null) {
      await _showProgress(title: '正在识别', body: 'AI 分析账单中…');
    }
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
      _talliesFor(source).blocked++;
    }
    return true;
  }

  /// App 回前台时重试后台直存阻塞项（ADR-054 / 076）。
  Future<void> retryPendingOnResume() async {
    if (_retryDrainRunning) return;
    _retryDrainRunning = true;
    try {
      final items = await _retryStore.load();
      if (items.isEmpty) return;
      logger.info('AutoBilling', '回前台重试 ${items.length} 项');
      await ForegroundBillingBridge.acquire(
        BillingFgsOwner.retry,
        title: '识别继续',
        body: '继续调用AI分析',
      );
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
          fromRetry: true,
        );
      }
    } finally {
      _retryDrainRunning = false;
      await ForegroundBillingBridge.release(BillingFgsOwner.retry);
    }
  }

  /// 为即将开始的分享结果附加通知文案（ADR-058）。
  void setBatchNote(String? note) {
    final t = note?.trim();
    _pendingShareBatchNote = (t == null || t.isEmpty) ? null : t;
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
    final t = _talliesFor(_recordingSource);
    t.success += success;
    t.skip += skip;
    t.successAmount += successAmount;
  }

  void _recordFailedImage({required String title, required String body}) {
    final bucket = _talliesFor(_recordingSource);
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty) {
      bucket.failureReasons.add(b.isEmpty ? '识别失败' : b);
    } else if (b.isEmpty || b == t) {
      bucket.failureReasons.add(t);
    } else {
      bucket.failureReasons.add('$t：$b');
    }
  }

  Future<void> _flushTallies(
    _BatchTallies bucket, {
    String? batchNote,
    bool? clearProgress,
  }) async {
    final t = _BatchTallies()..copyFrom(bucket);
    bucket.clear();

    if (t.isEmpty) {
      if (_inflightPath == null &&
          _awaitingScreenshotPath == null &&
          _assocPaths.isEmpty &&
          _highQueue.isEmpty &&
          _lowQueue.isEmpty &&
          !_pumpRunning) {
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
    final shouldClear =
        clearProgress ?? !ForegroundBillingBridge.isActive;
    await notifications.showResult(
      title: title,
      body: body,
      success: opensDetails,
      clearProgress: shouldClear,
    );
    if (!opensDetails) {
      notifications.lastFailureTitle = title;
      notifications.lastFailureBody = t.failureReasons.join('\n');
    }
  }

  /// ADR-076 方案 A：整批合并一条「识别结果」。
  Future<void> _flushMergedBatchResult() async {
    final merged = _BatchTallies()
      ..success = _shareTallies.success + _screenshotTallies.success
      ..skip = _shareTallies.skip + _screenshotTallies.skip
      ..successAmount =
          _shareTallies.successAmount + _screenshotTallies.successAmount
      ..blocked = _shareTallies.blocked + _screenshotTallies.blocked;
    merged.failureReasons
      ..addAll(_shareTallies.failureReasons)
      ..addAll(_screenshotTallies.failureReasons);
    final note = _pendingShareBatchNote;
    _pendingShareBatchNote = null;
    _shareTallies.clear();
    _screenshotTallies.clear();
    try {
      await _flushTallies(
        merged,
        batchNote: note,
        clearProgress: !ForegroundBillingBridge.isActive,
      );
    } catch (_) {
      merged.clear();
    }
  }

  /// 检出即早期进度（关联窗未满；不 Vision / 不落库）。
  /// 原生已先起 FGS；此处再 [ForegroundBillingBridge.acquire] 对齐持有者（ADR-076）。
  /// [resume]：回前台补扫，用 batch + 补扫文案，不走 assoc。
  Future<void> showScreenshotEarlyProgress(
    String imagePath, {
    bool resume = false,
  }) async {
    if (_superseded.contains(imagePath)) return;
    if (resume) {
      await ForegroundBillingBridge.acquire(
        BillingFgsOwner.batch,
        title: '补扫到截图',
        body: '正在补识别…',
      );
      return;
    }
    _assocPaths.add(imagePath);
    await ForegroundBillingBridge.acquire(
      BillingFgsOwner.assoc,
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
    _assocPaths.remove(oldPath);
    if (newPath != null && newPath.isNotEmpty) {
      _assocPaths.add(newPath);
    }
    _awaitingScreenshotPath = newPath;
    if (_assocPaths.isEmpty) {
      await ForegroundBillingBridge.release(BillingFgsOwner.assoc);
    }
    await _showProgress(
      title: '截图已更新',
      body: '改用编辑后的图片识别…',
    );
  }

  /// 预览删除且删原短等无后继 / 门闩丢原：清进度并结果通知（ADR-068 / 076）。
  Future<void> cancelScreenshotProgress(String imagePath) async {
    final alreadySuperseded = _superseded.contains(imagePath);
    if (!alreadySuperseded) {
      _superseded.add(imagePath);
      if (_superseded.length > 40) {
        final drop = _superseded.take(20).toList();
        _superseded.removeAll(drop);
      }
      if (_awaitingScreenshotPath == imagePath) {
        _awaitingScreenshotPath = null;
      }
    }

    _assocPaths.remove(imagePath);
    final keptAlive = ForegroundBillingBridge.hasOwner(BillingFgsOwner.share) ||
        ForegroundBillingBridge.hasOwner(BillingFgsOwner.retry) ||
        _pumpRunning ||
        _highQueue.isNotEmpty ||
        _lowQueue.isNotEmpty ||
        _inflightPath != null;

    if (_assocPaths.isEmpty) {
      await ForegroundBillingBridge.release(BillingFgsOwner.assoc);
    }

    // 补扫早期 acquire(batch) 但未入队时，取消需放掉 batch，避免 FGS 残留。
    if (!keptAlive &&
        _assocPaths.isEmpty &&
        ForegroundBillingBridge.hasOwner(BillingFgsOwner.batch)) {
      await ForegroundBillingBridge.release(BillingFgsOwner.batch);
    }

    if (alreadySuperseded) {
      return;
    }

    if (keptAlive || ForegroundBillingBridge.isActive) {
      if (keptAlive) {
        logger.info(
          'AutoBilling',
          'assoc cancel during share/batch; FGS kept '
          'file=${p.basename(imagePath)}',
        );
      }
      await _refreshProgressAfterAssocCancel();
    }

    await notifications.showResult(
      title: '截图已取消，未入账',
      body: '编辑超时或原图已删除',
      success: false,
      clearProgress: !ForegroundBillingBridge.isActive,
    );
  }

  /// 处理本地图片路径；成功返回交易 id 列表。
  ///
  /// 调度：`share` 优先于 `screenshot`，不打断 inflight（ADR-075）。
  Future<List<int>> processImagePath(
    String imagePath, {
    required String source,
    bool showNotification = true,
    bool autoSave = true,
    bool fromRetry = false,
  }) {
    if (_awaitingScreenshotPath == imagePath) {
      _awaitingScreenshotPath = null;
    }
    if (source == 'screenshot') {
      _assocPaths.remove(imagePath);
      if (_assocPaths.isEmpty) {
        unawaited(ForegroundBillingBridge.release(BillingFgsOwner.assoc));
      }
    }
    final job = _BillingJob(
      imagePath: imagePath,
      source: source,
      showNotification: showNotification,
      autoSave: autoSave,
      fromRetry: fromRetry,
    );
    if (job.isShare) {
      _highQueue.addLast(job);
      if (_needsShareWaitHint()) {
        unawaited(
          _showProgress(
            title: kShareBillingProgressTitle,
            body: _shareWaitBody,
          ),
        );
        logger.info(
          'AutoBilling',
          '分享已插队，等待截图 inflight/关联窗/低优队结束后处理',
        );
      }
    } else {
      _lowQueue.addLast(job);
    }
    unawaited(_ensurePump());
    return job.done.future;
  }

  _BillingJob? _takeNextJob() {
    if (_highQueue.isNotEmpty) return _highQueue.removeFirst();
    if (_lowQueue.isNotEmpty) return _lowQueue.removeFirst();
    return null;
  }

  Future<void> _ensurePump() async {
    if (_pumpRunning) return;
    _pumpRunning = true;
    unawaited(AndroidActivityBridge.setRetainOnBack(true));
    try {
      await _startBatchForeground();
      do {
        while (true) {
          final job = _takeNextJob();
          if (job == null) break;

          _inflightSource = job.source;
          _inflightFromRetry = job.fromRetry;
          _recordingSource = job.source;
          try {
            final ids = await _processImagePathLocked(
              job.imagePath,
              source: job.source,
              showNotification: job.showNotification,
              autoSave: job.autoSave,
              fromRetry: job.fromRetry,
            );
            if (!job.done.isCompleted) job.done.complete(ids);
          } catch (e, st) {
            if (!job.done.isCompleted) job.done.completeError(e, st);
          } finally {
            _recordingSource = null;
            _inflightSource = null;
            _inflightFromRetry = false;
          }
        }
        // 跑空后再看一眼：finally 前又入队则继续
      } while (_highQueue.isNotEmpty || _lowQueue.isNotEmpty);
    } finally {
      _pumpRunning = false;
      // ADR-076：先 stop FGS（releaseAll），再发整批「识别结果」。
      await _stopBatchForeground();
      try {
        await _flushMergedBatchResult();
      } catch (_) {
        _shareTallies.clear();
        _screenshotTallies.clear();
      }
      await AndroidActivityBridge.setRetainOnBack(false);
      if (_highQueue.isNotEmpty || _lowQueue.isNotEmpty) {
        unawaited(_ensurePump());
      }
    }
  }

  Future<List<int>> _processImagePathLocked(
    String imagePath, {
    required String source,
    required bool showNotification,
    required bool autoSave,
    bool fromRetry = false,
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
        if (fromRetry) {
          await _showProgress(title: '识别继续', body: '继续调用AI分析');
        } else {
          await _showProgress(title: '检测到图片', body: '等待文件就绪…');
        }
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
        if (fromRetry) {
          await _showProgress(title: '识别继续', body: '继续调用AI分析');
        } else {
          await _showProgress(title: '正在识别', body: 'AI 分析账单中…');
        }
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
          recreateHttpClientOnFirstTransport:
              source == 'screenshot' || source == 'share',
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
