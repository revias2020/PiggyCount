import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/repositories/ledger_repository.dart';
import '../csv/csv_service.dart';
import 'cloud_sync_config.dart';

/// MVP 云同步：整账本 CSV 快照上传/下载（冲突时由用户选择保留本地或使用云端）。
///
/// WebDAV 使用 Basic Auth + PUT/GET；S3 走预签名复杂度高，MVP 用
/// 兼容「S3 风格 HTTP PUT」或提示用户优先 WebDAV。
class CloudSyncService {
  CloudSyncService({
    required this.csv,
    required this.ledgers,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final CsvService csv;
  final LedgerRepository ledgers;
  final http.Client _http;

  /// 上传当前（或全部）账本 CSV 快照。
  Future<String> uploadSnapshot({
    required CloudSyncConfig config,
    int? ledgerId,
  }) async {
    if (config.kind == CloudSyncKind.none) {
      throw StateError('云同步未开启');
    }
    final body = await csv.exportCsv(ledgerId: ledgerId);
    final bytes = utf8.encode(body);
    if (config.kind == CloudSyncKind.webdav) {
      return _webdavPut(config, bytes);
    }
    return _s3Put(config, bytes);
  }

  /// 下载云端快照原文（CSV）。
  Future<String> downloadSnapshot({
    required CloudSyncConfig config,
  }) async {
    if (config.kind == CloudSyncKind.none) {
      throw StateError('云同步未开启');
    }
    if (config.kind == CloudSyncKind.webdav) {
      return _webdavGet(config);
    }
    return _s3Get(config);
  }

  /// 连接测试：WebDAV `OPTIONS`；S3 对对象 URL `HEAD`（必要时回退 `GET`）。
  /// 不读写快照正文；对象尚未存在（404）仍视为连通成功。
  Future<void> testConnection(CloudSyncConfig config) async {
    if (config.kind == CloudSyncKind.none) {
      throw StateError('请先选择 WebDAV 或 S3');
    }
    if (config.kind == CloudSyncKind.webdav) {
      await _testWebdav(config);
      return;
    }
    await _testS3(config);
  }

  Future<void> _testWebdav(CloudSyncConfig c) async {
    final url = c.webdavUrl.trim();
    if (url.isEmpty) {
      throw StateError('请填写服务器地址');
    }
    final request = http.Request('OPTIONS', Uri.parse(url));
    request.headers['Authorization'] = _basic(c.webdavUser, c.webdavPassword);
    final streamed =
        await _http.send(request).timeout(const Duration(seconds: 15));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 401) {
      throw StateError('鉴权失败，请检查用户名或密码');
    }
    if (resp.statusCode == 403) {
      throw StateError('访问被拒绝（403）');
    }
    if (resp.statusCode == 404) {
      throw StateError('路径不存在（404）');
    }
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw StateError('WebDAV 响应异常（${resp.statusCode}）');
    }
    final headers = resp.headers;
    final hasDav = headers.containsKey('dav') || headers.containsKey('allow');
    if (!hasDav) {
      throw StateError('该地址似乎不支持 WebDAV');
    }
  }

  Future<void> _testS3(CloudSyncConfig c) async {
    if (c.s3Endpoint.trim().isEmpty) {
      throw StateError('请填写 Endpoint');
    }
    if (c.s3Bucket.trim().isEmpty) {
      throw StateError('请填写 Bucket');
    }
    final url = _s3ObjectUrl(c);
    final headers = <String, String>{
      if (c.s3AccessKey.isNotEmpty) 'Authorization': 'Bearer ${c.s3AccessKey}',
    };

    http.Response resp;
    try {
      resp = await _http
          .head(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      // 部分兼容端点不支持 HEAD
      if (resp.statusCode == 405 || resp.statusCode == 501) {
        resp = await _http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 15));
      }
    } catch (_) {
      resp = await _http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw StateError('鉴权失败（${resp.statusCode}），请检查 Access Key');
    }
    // 2xx：对象存在；404：尚未上传快照，仍说明端点可达
    if ((resp.statusCode >= 200 && resp.statusCode < 300) ||
        resp.statusCode == 404) {
      return;
    }
    throw StateError('S3 响应异常（${resp.statusCode}）');
  }

  Future<String> _webdavPut(CloudSyncConfig c, List<int> bytes) async {
    final url = _join(c.webdavUrl, c.webdavPath, 'piggy_snapshot.csv');
    final resp = await _http.put(
      Uri.parse(url),
      headers: {
        'Authorization': _basic(c.webdavUser, c.webdavPassword),
        'Content-Type': 'text/csv; charset=utf-8',
      },
      body: bytes,
    ).timeout(const Duration(seconds: 60));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('WebDAV 上传失败(${resp.statusCode})');
    }
    return url;
  }

  Future<String> _webdavGet(CloudSyncConfig c) async {
    final url = _join(c.webdavUrl, c.webdavPath, 'piggy_snapshot.csv');
    final resp = await _http.get(
      Uri.parse(url),
      headers: {'Authorization': _basic(c.webdavUser, c.webdavPassword)},
    ).timeout(const Duration(seconds: 60));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('WebDAV 下载失败(${resp.statusCode})');
    }
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  /// 简化 S3：对 `https://{bucket}.{endpoint}/{key}` 或 path-style
  /// `https://{endpoint}/{bucket}/{key}` 做匿名/签名外的 PUT（需公开或网关）。
  ///
  /// 完整 AWS SigV4 签名较重，MVP 要求用户填写可直接 HTTP PUT/GET 的兼容端点
  ///（如部分自建 MinIO 预签名 URL 根路径）。若失败给出明确中文提示。
  Future<String> _s3Put(CloudSyncConfig c, List<int> bytes) async {
    final url = _s3ObjectUrl(c);
    final resp = await _http.put(
      Uri.parse(url),
      headers: {
        'Content-Type': 'text/csv; charset=utf-8',
        if (c.s3AccessKey.isNotEmpty)
          'Authorization': 'Bearer ${c.s3AccessKey}',
      },
      body: bytes,
    ).timeout(const Duration(seconds: 60));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError(
        'S3 上传失败(${resp.statusCode})。若使用标准 AWS，请配置支持匿名/网关 PUT 的兼容端点，或改用 WebDAV。',
      );
    }
    return url;
  }

  Future<String> _s3Get(CloudSyncConfig c) async {
    final url = _s3ObjectUrl(c);
    final resp = await _http.get(
      Uri.parse(url),
      headers: {
        if (c.s3AccessKey.isNotEmpty)
          'Authorization': 'Bearer ${c.s3AccessKey}',
      },
    ).timeout(const Duration(seconds: 60));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('S3 下载失败(${resp.statusCode})');
    }
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  String _s3ObjectUrl(CloudSyncConfig c) {
    final endpoint = c.s3Endpoint.replaceAll(RegExp(r'/+$'), '');
    final bucket = c.s3Bucket.trim();
    final key = 'piggy_snapshot.csv';
    if (endpoint.contains('://')) {
      return '$endpoint/$bucket/$key';
    }
    final scheme = c.s3UseSsl ? 'https' : 'http';
    return '$scheme://$endpoint/$bucket/$key';
  }

  String _join(String base, String path, String file) {
    final b = base.replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    final cleaned = p.replaceAll(RegExp(r'/+$'), '');
    return '$b$cleaned/$file';
  }

  String _basic(String user, String pass) {
    final token = base64Encode(utf8.encode('$user:$pass'));
    return 'Basic $token';
  }
}
