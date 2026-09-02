/// 截图监听目录路径规范化（ADR-070 · 方案 A；与原生 ScreenshotWatchPaths 对齐）。
abstract final class ScreenshotWatchPath {
  static const _roots = [
    '/storage/emulated/0/',
    '/sdcard/',
    '/mnt/sdcard/',
    '/storage/self/primary/',
  ];

  /// 转为相对键（如 `Pictures/Screenshots`）；content URI 或空串返回 null。
  static String? normalize(String raw) {
    var s = raw.trim().replaceAll('\\', '/');
    if (s.isEmpty) return null;
    if (s.toLowerCase().startsWith('content:')) return null;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final lower = s.toLowerCase();
    for (final root in _roots) {
      if (lower.startsWith(root)) {
        s = s.substring(root.length);
        break;
      }
    }
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s.isEmpty ? null : s;
  }
}
