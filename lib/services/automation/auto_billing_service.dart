import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ai/ai_config_store.dart';
import '../ai/ai_bookkeeper.dart';
import 'billing_notification_service.dart';

/// 截图/分享图片 → Vision 提取 → 自动落库（后台渠道；前台分享可另走确认弹层）。
class AutoBillingService {
  AutoBillingService({
    required this.bookkeeper,
    required this.resolveLedgerId,
    BillingNotificationService? notifications,
    AiConfigStore? configStore,
  })  : notifications = notifications ?? BillingNotificationService(),
        _configStore = configStore ?? AiConfigStore();

  final AiBookkeeper bookkeeper;
  final Future<int?> Function() resolveLedgerId;
  final BillingNotificationService notifications;
  final AiConfigStore _configStore;

  static const _processedKey = 'piggy_processed_screenshots';
  static const _dupWindowMs = 5000;
  static const _fileWaitMs = 3000;

  final Set<String> _processed = {};
  String? _lastPath;
  int _lastTime = 0;
  bool _loaded = false;

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
  }) async {
    await _ensureCache();
    if (_processed.contains(imagePath)) return const [];

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastPath == imagePath && now - _lastTime < _dupWindowMs) {
      return const [];
    }
    _lastPath = imagePath;
    _lastTime = now;

    final cfg = await _configStore.load();
    if (!cfg.isConfigured) {
      if (showNotification) {
        await notifications.showResult(
          title: '无法自动记账',
          body: '请先在「我的 → AI 模型配置」填写 API Key（需视觉模型）',
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
      if (showNotification) {
        await notifications.showResult(
          title: '文件不可用',
          body: '截图尚未可读，请稍后在「选择截图识别」中重试。系统截图需自行清理。',
        );
      }
      return const [];
    }

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
        if (showNotification) {
          await notifications.showResult(
            title: '未识别到账单',
            body: '该图可能不是支付截图',
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
        if (showNotification) {
          await notifications.showResult(title: '记账失败', body: '未找到账本');
        }
        return const [];
      }

      final ids = await bookkeeper.saveBills(
        bills: bills,
        ledgerId: ledgerId,
        source: source,
      );

      if (showNotification) {
        final total = bills.fold<double>(0, (a, b) => a + (b.amount ?? 0));
        await notifications.showResult(
          title: ids.isEmpty ? '保存失败' : '自动记账成功',
          body: ids.isEmpty
              ? '请打开 App 手动确认'
              : '已入账 ${ids.length} 笔，合计 ¥${total.toStringAsFixed(2)}',
        );
      }
      return ids;
    } catch (e) {
      debugPrint('AutoBilling failed: $e');
      if (showNotification) {
        await notifications.showResult(title: '识别失败', body: '$e');
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
