import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/seed_service.dart';
import 'providers/database_provider.dart';

/// 小猪记账入口：先打开数据库并播种，再挂载 UI。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  final db = await AppDatabase.open();
  await SeedService(db).ensureSeeded();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: const PiggyApp(),
    ),
  );
}
