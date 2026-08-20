/// 生成 Android 系统微件选择器预览图（非 CI 回归）。
///
/// ```bash
/// # Windows PowerShell
/// $env:GEN_WIDGET_PREVIEWS='1'; flutter test test/widget/widget_preview_generator_test.dart
/// ```
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/styles/tokens.dart';
import 'package:piggy_count/widget/views/glance_view.dart';
import 'package:piggy_count/widget/widget_data_service.dart';

final bool _enabled = Platform.environment['GEN_WIDGET_PREVIEWS'] == '1';

const _outDir = 'android/app/src/main/res/drawable-nodpi';

Future<void> _loadCjkAsDefault() async {
  final candidates = <String>[
    r'C:\Windows\Fonts\msyh.ttc',
    r'C:\Windows\Fonts\msyh.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ];
  File? fontFile;
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) {
      fontFile = f;
      break;
    }
  }
  if (fontFile == null) return;

  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(fontFile.readAsBytesSync().buffer)));
  await loader.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final otf = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (otf.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(otf.readAsBytesSync().buffer)));
      await iconLoader.load();
    }
  }
}

Future<void> _capture(
  WidgetTester tester,
  Widget view,
  Size logical,
  String outName,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Roboto', color: Colors.black),
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: logical.width,
              height: logical.height,
              child: view,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull, reason: '$outName render error');

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('$_outDir/$outName.png');
    out.createSync(recursive: true);
    out.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    // ignore: avoid_print
    print('生成 ${out.path} (${image.width}x${image.height})');
  });
}

List<GlanceDayPoint> _demoDays() {
  final today = DateTime.now();
  final start = today.subtract(const Duration(days: 6));
  const expenses = [20.0, 0.0, 45.0, 200.0, 80.0, 0.0, 200.0];
  const incomes = [0.0, 0.0, 0.0, 0.0, 120.0, 0.0, 0.0];
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return List.generate(7, (i) {
    final day = start.add(Duration(days: i));
    return GlanceDayPoint(
      day: day,
      label: i == 6 ? '今日' : weekdays[day.weekday - 1],
      expense: expenses[i],
      income: incomes[i],
    );
  });
}

void main() {
  testWidgets('generate glance widget previews', (tester) async {
    if (!_enabled) {
      // ignore: avoid_print
      print('跳过：设置 GEN_WIDGET_PREVIEWS=1 后重跑以生成预览图');
      return;
    }

    await _loadCjkAsDefault();

    await _capture(
      tester,
      GlanceView.medium(
        todayExpense: '¥200.00',
        todayIncome: '¥0.00',
        themeColor: PigTokens.primary,
        width: 360,
        height: 152,
        last7Days: _demoDays(),
      ),
      const Size(360, 152),
      'widget_preview_glance',
    );

    await _capture(
      tester,
      GlanceView.small(
        todayExpense: '¥88.50',
        monthExpense: '¥3.20k',
        monthIncome: '¥8.00k',
        themeColor: PigTokens.primary,
        width: 110,
        height: 110,
      ),
      const Size(110, 110),
      'widget_preview_glance_small',
    );
  });
}
