import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

/// 小组件 / 深链动作（ADR-024）。
enum PiggyDeepLinkAction {
  newExpense,
  newIncome,
  openDetails,
  openReportCustom7d,
  privacySmall,
  privacyMedium,
}

/// 解析 `piggycount://…`。
abstract final class AppLinkService {
  static PiggyDeepLinkAction? parse(Uri uri) {
    if (uri.scheme != 'piggycount') return null;
    switch (uri.host) {
      case 'new':
        final type = uri.queryParameters['type'];
        if (type == 'income') return PiggyDeepLinkAction.newIncome;
        return PiggyDeepLinkAction.newExpense;
      case 'details':
        return PiggyDeepLinkAction.openDetails;
      case 'report':
        final mode = uri.queryParameters['mode'];
        if (mode == 'custom7d') return PiggyDeepLinkAction.openReportCustom7d;
        return PiggyDeepLinkAction.openReportCustom7d;
      case 'privacy':
        final size = uri.queryParameters['size'];
        if (size == 'small') return PiggyDeepLinkAction.privacySmall;
        return PiggyDeepLinkAction.privacyMedium;
      default:
        return null;
    }
  }
}

/// 监听 piggycount:// 深链。
class PiggyAppLinkListener {
  PiggyAppLinkListener({required this.onAction});

  final void Function(PiggyDeepLinkAction action) onAction;
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> start() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      debugPrint('getInitialLink failed: $e');
    }
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => debugPrint('uriLinkStream error: $e'),
    );
  }

  void _handle(Uri uri) {
    final action = AppLinkService.parse(uri);
    if (action != null) onAction(action);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
