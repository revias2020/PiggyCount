/// 前台多选与分享多选共用上限（ADR-058）。
const int kMaxBillingImages = 9;

/// 超出上限截取时的用户可见文案。
const String kBillingImagesTruncatedHint = '已截取前 9 张';

/// 分享入账早期进度标题（与原生 ShareRelay / MainActivity 兜底对齐）。
const String kShareBillingProgressTitle = '分享入账';

/// 分享已收到进度正文（与原生 [SharedImageIngress.earlyProgressBody] 对齐）。
String shareReceivedProgressBody({required bool truncated}) => truncated
    ? '已收到（$kBillingImagesTruncatedHint），准备识别…'
    : '已收到，准备识别…';
