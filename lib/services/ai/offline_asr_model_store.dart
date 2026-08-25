import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../system/logger_service.dart';
import 'speech_engine_preference.dart';

/// 离线 ASR 模型目录（ADR-052；多源下载，国内镜像优先）。
enum OfflineAsrModelId { voskCnSmall, whisperBase }

/// 单个下载源；[requiresVpnHint] 为 true 时在 UI 提示可能需要代理。
class OfflineAsrDownloadSource {
  const OfflineAsrDownloadSource({
    required this.url,
    required this.label,
    this.requiresVpnHint = false,
  });

  final String url;
  final String label;
  final bool requiresVpnHint;
}

class OfflineAsrModelSpec {
  const OfflineAsrModelSpec({
    required this.id,
    required this.engine,
    required this.displayName,
    required this.downloadSources,
    required this.fileName,
    required this.sha256,
    required this.isZip,
  });

  final OfflineAsrModelId id;
  final SpeechRecognitionEngineKind engine;
  final String displayName;

  /// 按顺序尝试；首个为国内镜像，后续为官方源。
  final List<OfflineAsrDownloadSource> downloadSources;
  final String fileName;

  /// 空串表示下载后不校验（镜像若重打包可留空）。
  final String sha256;
  final bool isZip;

  bool get hasForeignFallback =>
      downloadSources.any((s) => s.requiresVpnHint);
}

/// 固定目录与 URL；镜像失效时只改此处。
class OfflineAsrModelCatalog {
  OfflineAsrModelCatalog._();

  static const vosk = OfflineAsrModelSpec(
    id: OfflineAsrModelId.voskCnSmall,
    engine: SpeechRecognitionEngineKind.vosk,
    displayName: 'Vosk 中文小包',
    downloadSources: [
      OfflineAsrDownloadSource(
        url:
            'https://hf-mirror.com/localstack/vosk-models/resolve/main/vosk-model-small-cn-0.22.zip',
        label: '国内镜像',
      ),
      OfflineAsrDownloadSource(
        url:
            'https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip',
        label: '官方源',
        requiresVpnHint: true,
      ),
    ],
    fileName: 'vosk-model-small-cn-0.22.zip',
    sha256: '',
    isZip: true,
  );

  static const whisper = OfflineAsrModelSpec(
    id: OfflineAsrModelId.whisperBase,
    engine: SpeechRecognitionEngineKind.whisper,
    displayName: 'Whisper base',
    downloadSources: [
      OfflineAsrDownloadSource(
        url:
            'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
        label: '国内镜像',
      ),
      OfflineAsrDownloadSource(
        url:
            'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
        label: '官方源',
        requiresVpnHint: true,
      ),
    ],
    fileName: 'ggml-base.bin',
    sha256: '',
    isZip: false,
  );

  static OfflineAsrModelSpec? forEngine(SpeechRecognitionEngineKind engine) {
    return switch (engine) {
      SpeechRecognitionEngineKind.vosk => vosk,
      SpeechRecognitionEngineKind.whisper => whisper,
      _ => null,
    };
  }

  static const all = [vosk, whisper];
}

/// 下载 / 校验 / 解压离线模型到应用文档目录。
class OfflineAsrModelStore {
  OfflineAsrModelStore({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'offline_asr_models'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _markerFile(OfflineAsrModelSpec spec) async {
    final root = await _root();
    return File(p.join(root.path, '${spec.id.name}.ready.json'));
  }

  Future<bool> isReady(OfflineAsrModelSpec spec) async {
    final marker = await _markerFile(spec);
    if (!await marker.exists()) return false;
    try {
      final map =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      final path = map['path'] as String?;
      if (path == null || path.isEmpty) return false;
      return File(path).existsSync() || Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 已就绪模型的本地路径（Whisper=bin 文件；Vosk=解压目录）。
  Future<String?> localPath(OfflineAsrModelSpec spec) async {
    final marker = await _markerFile(spec);
    if (!await marker.exists()) return null;
    try {
      final map =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      final path = map['path'] as String?;
      if (path == null) return null;
      if (File(path).existsSync() || Directory(path).existsSync()) return path;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(OfflineAsrModelSpec spec) async {
    final root = await _root();
    final marker = await _markerFile(spec);
    String? path;
    if (await marker.exists()) {
      try {
        final map =
            jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
        path = map['path'] as String?;
      } catch (_) {}
      await marker.delete();
    }
    if (path != null) {
      final f = File(path);
      final d = Directory(path);
      if (await f.exists()) await f.delete();
      if (await d.exists()) await d.delete(recursive: true);
    }
    final zipOrBin = File(p.join(root.path, spec.fileName));
    if (await zipOrBin.exists()) await zipOrBin.delete();
  }

  /// 下载并就绪；[onProgress] 为 0~1。
  Future<String> download(
    OfflineAsrModelSpec spec, {
    void Function(double progress)? onProgress,
    void Function(OfflineAsrDownloadSource source)? onSourceAttempt,
  }) async {
    final root = await _root();
    final dest = File(p.join(root.path, spec.fileName));
    logger.info('OfflineAsr', '开始下载 ${spec.displayName}');

    Object? lastError;
    for (final source in spec.downloadSources) {
      onSourceAttempt?.call(source);
      onProgress?.call(0);
      try {
        await _downloadFile(source, dest, onProgress: onProgress);
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        logger.warning(
          'OfflineAsr',
          '${spec.displayName} 源「${source.label}」失败: $e',
        );
        if (await dest.exists()) await dest.delete();
      }
    }
    if (lastError != null) {
      final hint = spec.hasForeignFallback
          ? '；已尝试全部下载源，访问国外源可能需要 VPN 或代理'
          : '';
      throw StateError('下载失败：${spec.displayName}$hint');
    }

    if (spec.sha256.isNotEmpty) {
      final digest = await sha256.bind(dest.openRead()).first;
      final hex = digest.toString();
      if (hex.toLowerCase() != spec.sha256.toLowerCase()) {
        await dest.delete();
        throw StateError('模型校验失败（哈希不匹配），请重试下载');
      }
    }

    late final String readyPath;
    if (spec.isZip) {
      final extractDir = Directory(p.join(root.path, spec.id.name));
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);
      final bytes = await dest.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final outPath = p.join(extractDir.path, file.name);
        if (file.isFile) {
          final out = File(outPath);
          await out.parent.create(recursive: true);
          await out.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      readyPath = _findVoskModelRoot(extractDir) ?? extractDir.path;
      await dest.delete();
    } else {
      readyPath = dest.path;
    }

    final marker = await _markerFile(spec);
    await marker.writeAsString(
      jsonEncode({
        'id': spec.id.name,
        'path': readyPath,
        'downloadedAt': DateTime.now().toIso8601String(),
      }),
    );
    onProgress?.call(1);
    logger.info('OfflineAsr', '已就绪 ${spec.displayName} → $readyPath');
    return readyPath;
  }

  Future<void> _downloadFile(
    OfflineAsrDownloadSource source,
    File dest, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(source.url));
    final streamed =
        await _http.send(request).timeout(const Duration(minutes: 30));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw StateError('HTTP ${streamed.statusCode}');
    }

    final total = streamed.contentLength ?? -1;
    final sink = dest.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();
    } catch (e) {
      await sink.close();
      if (await dest.exists()) await dest.delete();
      rethrow;
    }
  }

  String? _findVoskModelRoot(Directory extractDir) {
    try {
      for (final entity in extractDir.listSync(recursive: true)) {
        if (entity is! Directory) continue;
        final am = Directory(p.join(entity.path, 'am'));
        final conf = Directory(p.join(entity.path, 'conf'));
        if (am.existsSync() && conf.existsSync()) return entity.path;
      }
    } catch (_) {}
    final children = extractDir.listSync().whereType<Directory>().toList();
    if (children.length == 1) return children.first.path;
    return extractDir.path;
  }
}
