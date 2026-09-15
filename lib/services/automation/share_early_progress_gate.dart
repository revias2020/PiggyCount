/// 分享入账：前台网络预热与回源沉降。
///
/// 历史上「先回源再 hold ≥1s 才 Vision」易在后台新建大 POST 时被系统
/// `Software caused connection abort`；现改为前台先开 Vision，短预热后再回源。
class ShareEarlyProgressGate {
  ShareEarlyProgressGate._();

  /// 入队 Vision 后、回源前保留的前台窗口，便于读图/压缩并开始 POST。
  static const foregroundNetworkWarmup = Duration(milliseconds: 1500);

  /// [moveTaskToBack] 返回后到 Activity `visibility=false` 的沉降（热启实测约 300ms）。
  static const backgroundSettle = Duration(milliseconds: 300);
}
