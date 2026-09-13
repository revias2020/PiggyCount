import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// 回前台补扫水位 W（ADR-077；修订 ADR-074）。
///
/// 仅在截图自动开始调用 Vision 时前进；`paused` / 补扫结束 / 分享 / 手动不写。
class ScreenshotResumeWatermark {
  ScreenshotResumeWatermark._();

  static const key = 'piggy_screenshot_resume_watermark_sec';

  /// 无水位时回退窗口（秒）。
  static const fallbackAgeSeconds = 300;

  /// 补扫时间封顶（秒）。
  static const capAgeSeconds = 24 * 60 * 60;

  /// 截图自动即将调 Vision：`W = max(旧W, now)`。
  static Future<void> advanceOnScreenshotAi() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final old = prefs.getInt(key);
    final next = old == null ? now : math.max(old, now);
    await prefs.setInt(key, next);
  }

  /// 读出水位；无则 null。
  static Future<int?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key);
  }

  /// 补扫下界：`max(W ?? now−5min, now−24h)`。
  static int sinceExclusive({required int now, int? watermark}) {
    final lower = watermark ?? (now - fallbackAgeSeconds);
    return math.max(lower, now - capAgeSeconds);
  }
}
