import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 本地导出结果（ADR-022）。
class LocalExportResult {
  const LocalExportResult({
    required this.path,
    required this.sharedViaSheet,
  });

  /// 写入后的绝对路径。
  final String path;

  /// iOS 等走了系统分享面板。
  final bool sharedViaSheet;

  /// 给用户看的成功文案。
  String get successMessage {
    if (sharedViaSheet) {
      return '已导出，请选择保存位置\n$path';
    }
    return '已保存到\n$path';
  }
}

/// Android → `Download/PiggyCount`；iOS → 文档目录后分享（ADR-022）。
class LocalExportService {
  LocalExportService._();

  static const androidDownloadDir = '/storage/emulated/0/Download/PiggyCount';

  /// `yyyyMMdd_HHmmss`
  static String fileStamp([DateTime? at]) {
    final t = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// 解析导出目录（确保存在）。
  static Future<Directory> resolveDirectory() async {
    if (Platform.isAndroid) {
      final dir = Directory(androidDownloadDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    return getApplicationDocumentsDirectory();
  }

  /// 文件已写入 [path] 后调用：Android 仅回报路径，iOS 拉起分享。
  static Future<LocalExportResult> finalize({
    required String path,
    String? mimeType,
    String? shareSubject,
  }) async {
    if (Platform.isIOS) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              path,
              mimeType: mimeType,
              name: p.basename(path),
            ),
          ],
          subject: shareSubject,
        ),
      );
      return LocalExportResult(path: path, sharedViaSheet: true);
    }
    return LocalExportResult(path: path, sharedViaSheet: false);
  }

  /// 写入字节；Android 直接落盘，iOS 落盘后拉起分享。
  static Future<LocalExportResult> exportBytes({
    required String fileName,
    required List<int> bytes,
    String? mimeType,
    String? shareSubject,
  }) async {
    final dir = await resolveDirectory();
    final path = p.join(dir.path, fileName);
    await File(path).writeAsBytes(Uint8List.fromList(bytes), flush: true);
    return finalize(
      path: path,
      mimeType: mimeType,
      shareSubject: shareSubject,
    );
  }

  /// 写入 UTF-8 文本。
  static Future<LocalExportResult> exportText({
    required String fileName,
    required String content,
    String? mimeType,
    String? shareSubject,
  }) {
    return exportBytes(
      fileName: fileName,
      bytes: utf8.encode(content),
      mimeType: mimeType ?? 'text/plain',
      shareSubject: shareSubject,
    );
  }
}
