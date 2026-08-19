import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/seed_service.dart';
import 'providers/database_provider.dart';
import 'services/system/logger_service.dart';

/// 小猪记账入口：先打开数据库并播种，再挂载 UI。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await logger.init();
  _installErrorHooks();

  // 旧版 Android 系统自带 SQLite 过旧；走 sqlite3_flutter_libs 捆绑库
  if (Platform.isAndroid) {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  try {
    final db = await AppDatabase.open();
    await SeedService(db).ensureSeeded();
    logger.info('App', '应用启动完成');

    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
        child: const PiggyApp(),
      ),
    );
  } catch (e, st) {
    logger.error('App', '应用启动失败', e, st);
    rethrow;
  }
}

void _installErrorHooks() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logger.error(
      'Flutter',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    logger.error('Platform', '未捕获异步错误', error, stack);
    return true;
  };
}
