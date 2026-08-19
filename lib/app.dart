import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'pages/main/home_shell.dart';
import 'pages/transaction/record_editor_sheet.dart';
import 'providers/automation_providers.dart';
import 'providers/database_provider.dart';
import 'providers/deep_link_providers.dart';
import 'providers/report_providers.dart';
import 'providers/tab_index_provider.dart';
import 'providers/widget_providers.dart';
import 'services/automation/billing_notification_service.dart';
import 'services/automation/image_share_handler.dart';
import 'services/platform/app_link_service.dart';
import 'styles/tokens.dart';
import 'utils/report_period.dart';
import 'utils/report_route_observer.dart';
import 'widget/widget_privacy.dart';

/// 根导航 Key：通知点击弹 Dialog 等需要在 Service 层拿到 Context。
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 根 Widget：主题 + 中文本地化；启动后恢复截图监听 / 绑定分享。
class PiggyApp extends ConsumerStatefulWidget {
  const PiggyApp({super.key});

  @override
  ConsumerState<PiggyApp> createState() => _PiggyAppState();
}

class _PiggyAppState extends ConsumerState<PiggyApp>
    with WidgetsBindingObserver {
  late final ImageShareHandler _shareHandler;
  PiggyAppLinkListener? _appLinkListener;
  var _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifications = ref.read(billingNotificationServiceProvider);
    notifications.onAction = _onBillingNotificationAction;
    _shareHandler = ImageShareHandler(
      autoBilling: ref.read(autoBillingServiceProvider),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appLinkListener?.dispose();
    super.dispose();
  }

  /// 吞掉 Flutter 内置深链，避免 Navigator.pushNamed('/?type=expense')。
  /// 真正的 `piggycount://` 由 [PiggyAppLinkListener] 处理。
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final uri = routeInformation.uri;
    if (uri.scheme == 'piggycount') return true;
    if (uri.hasQuery && (uri.path.isEmpty || uri.path == '/')) return true;
    return false;
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final notifications = ref.read(billingNotificationServiceProvider);
    await notifications.ensureInitialized();
    await notifications.consumeLaunchAction();

    if (Platform.isAndroid) {
      await HomeWidget.registerInteractivityCallback(
        widgetInteractivityCallback,
      );
      await _shareHandler.bind();
      final enabled =
          await ref.read(settingsRepositoryProvider).screenshotAutoBilling();
      if (enabled) {
        try {
          await ref.read(screenshotMonitorServiceProvider).start();
        } catch (e) {
          debugPrint('恢复截图监听失败: $e');
        }
      }

      _appLinkListener = PiggyAppLinkListener(onAction: _onDeepLink);
      await _appLinkListener!.start();
    }
  }

  void _onDeepLink(PiggyDeepLinkAction action) {
    switch (action) {
      case PiggyDeepLinkAction.newExpense:
      case PiggyDeepLinkAction.newIncome:
        final type =
            action == PiggyDeepLinkAction.newIncome ? 'income' : 'expense';
        ref.read(pendingWidgetNewTypeProvider.notifier).state = type;
        ref.read(tabIndexProvider.notifier).state = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final nav = rootNavigatorKey.currentState;
          final ctx = rootNavigatorKey.currentContext;
          if (nav == null || ctx == null || !ctx.mounted) return;
          nav.popUntil((r) => r.isFirst);
          final pending = ref.read(pendingWidgetNewTypeProvider);
          if (pending == null) return;
          ref.read(pendingWidgetNewTypeProvider.notifier).state = null;
          showRecordEditorSheet(ctx, initialType: pending);
        });
      case PiggyDeepLinkAction.openDetails:
        ref.read(tabIndexProvider.notifier).state = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
        });
      case PiggyDeepLinkAction.openReportCustom7d:
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        ref.read(reportScopeProvider.notifier).state = ReportScope.custom;
        ref.read(reportCustomStartProvider.notifier).state =
            today.subtract(const Duration(days: 6));
        ref.read(reportCustomEndProvider.notifier).state = today;
        ref.read(tabIndexProvider.notifier).state = 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
        });
      case PiggyDeepLinkAction.privacySmall:
      case PiggyDeepLinkAction.privacyMedium:
        // 正常由 BackgroundIntent 处理；若误走 Activity 则兜底。
        final size =
            action == PiggyDeepLinkAction.privacySmall ? 'small' : 'medium';
        WidgetPrivacy.toggleAndRerender(size);
    }
  }

  void _onBillingNotificationAction(BillingNotificationAction action) {
    ref.read(tabIndexProvider.notifier).state = 0;
    final nav = rootNavigatorKey.currentState;
    nav?.popUntil((r) => r.isFirst);

    if (action != BillingNotificationAction.failure) return;

    final body = ref.read(billingNotificationServiceProvider).lastFailureBody;
    if (body == null || body.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      showDialog<void>(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('记账失败'),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('确认'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小猪记账',
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [reportRouteObserver],
      debugShowCheckedModeBanner: false,
      theme: PigTokens.lightTheme(),
      themeMode: ThemeMode.light,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const WidgetRefreshHost(child: HomeShell()),
    );
  }
}
