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

/// 批次内账单分桶 + 整图未入账（ADR-056）。
class _BatchTallies {
  int success = 0;
  int skip = 0;
  int fail = 0;
  double successAmount = 0;
  final List<({String title, String body})> imagesUnsaved = [];

  bool get isEmpty =>
      success == 0 && skip == 0 && fail == 0 && imagesUnsaved.isEmpty;
}

/// 结果正文（单张 / 合并共用；供测试）。
String formatAutoBillingResultBody({
  required int success,
  required int skip,
  required int fail,
  required int imagesUnsaved,
  double? successAmount,
  String? singleUnsavedBody,
  String? batchNote,
}) {
  final hasBills = success > 0 || skip > 0 || fail > 0;
  String body;
  if (!hasBills) {
    if (imagesUnsaved == 1 &&
        singleUnsavedBody != null &&
        singleUnsavedBody.isNotEmpty) {
      body = singleUnsavedBody;
    } else if (imagesUnsaved > 0) {
      body = '另有 $imagesUnsaved 张未入账';
    } else {
      body = '';
    }
  } else {
    final parts = <String>[];
    if (success > 0 && skip == 0 && fail == 0 && imagesUnsaved == 0) {
      final amount = successAmount ?? 0;
      parts.add('已入账 $success 笔，合计 ¥${amount.toStringAsFixed(2)}');
    } else {
      parts.add('成功 $success 笔，跳过 $skip 笔，失败 $fail 笔');
      if (imagesUnsaved > 0) {
        parts.add('另有 $imagesUnsaved 张未入账');
      }
    }
    body = parts.join('，');
  }
  final note = batchNote?.trim();
  if (note == null || note.isEmpty) return body;
  if (body.isEmpty) return note;
  return '$body（$note）';
}

/// 结果标题（供测试）。
String formatAutoBillingResultTitle({
  required int success,
  required int skip,
  required int fail,
  required int imagesUnsaved,
  String? singleUnsavedTitle,
}) {
  final hasBills = success > 0 || skip > 0 || fail > 0;
  if (!hasBills &&
      imagesUnsaved == 1 &&
      singleUnsavedTitle != null &&
      singleUnsavedTitle.isNotEmpty) {
    return singleUnsavedTitle;
  }
  if (success > 0 && fail == 0) return '自动记账成功';
  if (success == 0 &&
      fail == 0 &&
      skip > 0 &&
      imagesUnsaved == 0) {
    return '记账取消';
  }
  return '自动记账完成';
}

/// 点击是否走成功路径（ADR-056 / F2）。
bool autoBillingResultClickSuccess(int successCount) => successCount > 0;

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
    if (ForegroundBillingBridge.isActive) return;
    await ForegroundBillingBridge.start(
      title: '智能记账',
      body: '准备识别…',
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
      '传输失败已入待重试队列 source=$source file=${p.basename(imagePath)}',
    );
    if (showNotification) {
      await _showProgress(
        title: '待继续识别',
        body: '打开 App 后将自动重试',
      );
    }
    return true;
  }

  /// App 回前台时重试后台直存传输失败项（ADR-054）。
  Future<void> retryPendingOnResume() async {
    if (_retryDrainRunning) return;
    _retryDrainRunning = true;
    try {
      final items = await _retryStore.load();
      if (items.isEmpty) return;
      logger.info('AutoBilling', '回前台重试 ${items.length} 项');
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
    required int fail,
    double successAmount = 0,
  }) {
    _batchTallies.success += success;
    _batchTallies.skip += skip;
    _batchTallies.fail += fail;
    _batchTallies.successAmount += successAmount;
  }

  void _recordImageUnsaved({required String title, required String body}) {
    _batchTallies.imagesUnsaved.add((title: title, body: body));
  }

  Future<void> _flushBatchResults() async {
    final t = _BatchTallies()
      ..success = _batchTallies.success
      ..skip = _batchTallies.skip
      ..fail = _batchTallies.fail
      ..successAmount = _batchTallies.successAmount
      ..imagesUnsaved.addAll(_batchTallies.imagesUnsaved);
    final batchNote = _pendingBatchNote;
    _pendingBatchNote = null;
    _batchTallies
      ..success = 0
      ..skip = 0
      ..fail = 0
      ..successAmount = 0
      ..imagesUnsaved.clear();

    if (t.isEmpty) {
      if (_inflightPath == null && _awaitingScreenshotPath == null) {
        await _cancelProgress();
      }
      return;
    }

    final unsaved = t.imagesUnsaved;
    final singleUnsaved = unsaved.length == 1 ? unsaved.first : null;
    final body = formatAutoBillingResultBody(
      success: t.success,
      skip: t.skip,
      fail: t.fail,
      imagesUnsaved: unsaved.length,
      successAmount: t.successAmount,
      singleUnsavedBody: singleUnsaved?.body,
      batchNote: batchNote,
    );
    final title = formatAutoBillingResultTitle(
      success: t.success,
      skip: t.skip,
      fail: t.fail,
      imagesUnsaved: unsaved.length,
      singleUnsavedTitle: singleUnsaved?.title,
    );
    await notifications.showResult(
      title: title,
      body: body,
      success: autoBillingResultClickSuccess(t.success),
    );
  }

  /// 稳定期满、关联窗未到：早期进度（不 Vision / 不落库）。
  Future<void> showScreenshotEarlyProgress(String imagePath) async {
    if (_superseded.contains(imagePath)) return;
    logger.info(
      'AutoBilling',
      '早期进度 source=screenshot file=${p.basename(imagePath)}',
    );
    await notifications.showProgress(
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
    logger.info(
      'AutoBilling',
      '截图替换 old=${p.basename(oldPath)} '
      'new=${newPath == null || newPath.isEmpty ? "-" : p.basename(newPath)}',
    );
    await notifications.showProgress(
      title: '截图已更新',
      body: '改用编辑后的图片识别…',
    );
  }

  /// 预览删除且无后继：清早期进度。
  Future<void> cancelScreenshotProgress(String imagePath) async {
    _superseded.add(imagePath);
    if (_awaitingScreenshotPath == imagePath) {
      _awaitingScreenshotPath = null;
    }
    logger.info(
      'AutoBilling',
      '截图取消 file=${p.basename(imagePath)}',
    );
    await notifications.cancelProgress();
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
            _batchTallies
              ..success = 0
              ..skip = 0
              ..fail = 0
              ..successAmount = 0
              ..imagesUnsaved.clear();
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
      logger.info(
        'AutoBilling',
        '已替换跳过 source=$source file=${p.basename(imagePath)}',
      );
      return const [];
    }

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
        _recordImageUnsaved(
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
        logger.info('AutoBilling', '等待文件时被替换 file=$fileName');
        return const [];
      }
      if (!ready) {
        logger.warning('AutoBilling', '文件不可读 source=$source file=$fileName');
        if (showNotification) {
          _recordImageUnsaved(
            title: '文件不可用',
            body: '截图尚未可读，请稍后通过记一笔扇形「图片」重试。',
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
        await _showProgress(title: '正在识别', body: 'AI 分析账单中…');
      }

      try {
        final rawBytes = await file.readAsBytes();
        if (_superseded.contains(imagePath)) {
          logger.info('AutoBilling', '读图后被替换，放弃 file=$fileName');
          return const [];
        }
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
        if (_superseded.contains(imagePath)) {
          logger.info('AutoBilling', '识别中被替换，放弃落库 file=$fileName');
          return const [];
        }
        await _mark(imagePath);

        if (bills.isEmpty) {
          logger.warning('AutoBilling', '非账单 source=$source file=$fileName');
          if (showNotification) {
            _recordImageUnsaved(
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
            _recordBillTallies(
              success: 0,
              skip: 0,
              fail: bills.length,
            );
          }
          return const [];
        }

        if (_superseded.contains(imagePath)) {
          logger.info('AutoBilling', '落库前被替换，放弃 file=$fileName');
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
          logger.info(
            'AutoBilling',
            '自动入账 ${saved.ids.length} 笔 source=$source '
            'skip=${saved.skipped} fail=${saved.failed}',
          );
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
            fail: saved.failed,
            successAmount: saved.savedAmount,
          );
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
          _recordImageUnsaved(
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
            _recordBillTallies(success: 0, skip: 1, fail: 0);
          } else {
            _recordImageUnsaved(title: failTitle, body: msg);
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
