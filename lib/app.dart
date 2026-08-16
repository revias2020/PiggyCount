import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/main/home_shell.dart';
import 'providers/automation_providers.dart';
import 'providers/database_provider.dart';
import 'services/automation/image_share_handler.dart';
import 'styles/tokens.dart';

/// 根导航 Key：分享入账弹层等需要在 Service 层拿到 Context。
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 根 Widget：主题 + 中文本地化；启动后恢复截图监听 / 绑定分享。
class PiggyApp extends ConsumerStatefulWidget {
  const PiggyApp({super.key});

  @override
  ConsumerState<PiggyApp> createState() => _PiggyAppState();
}

class _PiggyAppState extends ConsumerState<PiggyApp> {
  late final ImageShareHandler _shareHandler;
  var _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _shareHandler = ImageShareHandler(
      autoBilling: ref.read(autoBillingServiceProvider),
      navigatorKey: rootNavigatorKey,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    if (Platform.isAndroid) {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小猪记账',
      navigatorKey: rootNavigatorKey,
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
      home: const HomeShell(),
    );
  }
}
