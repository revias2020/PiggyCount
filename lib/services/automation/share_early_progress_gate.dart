/// ADR-063：分享已收到进度最短展示（回源后起算），避免栏里只看见「正在识别」。
class ShareEarlyProgressGate {
  ShareEarlyProgressGate._();

  /// 自回源且通知可被看到起，至少保留多久再允许切到后续进度。
  static const minDisplay = Duration(seconds: 1);

  /// [moveTaskToBack] 返回后到 Activity `visibility=false` 的沉降（热启实测约 300ms）。
  static const backgroundSettle = Duration(milliseconds: 300);

  static DateTime? _shownAt;

  /// 在回源并 [backgroundSettle] 之后调用；[alreadyVisible] 默认 0（不再把前台 Relay 时段计入）。
  static void markShown({Duration alreadyVisible = Duration.zero}) {
    _shownAt = DateTime.now().subtract(alreadyVisible);
  }

  static Future<void> awaitMinDisplay() async {
    final at = _shownAt;
    if (at == null) return;
    final elapsed = DateTime.now().difference(at);
    final remaining = minDisplay - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  static void reset() {
    _shownAt = null;
  }
}
