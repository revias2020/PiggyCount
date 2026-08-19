import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_sync_config.dart';

/// 远端工作区文件尚未被别人改掉时的条件写失败（需重新拉云再合并）。
class CloudPreconditionFailed implements Exception {
  @override
  String toString() => '云端已被更新，正在重试合并';
}

/// 远端工作区文档（404 时 [body] 为空）。
class CloudRemoteDocument {
  const CloudRemoteDocument({this.body, this.etag});

  final String? body;
  final String? etag;

  bool get isMissing => body == null;
}

/// 云存储：同步工作区 JSON 的 GET/条件 PUT；连接测试仍走 OPTIONS / HEAD。
class CloudSyncService {
  CloudSyncService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const remoteFile = 'piggy_workspace.json';

  /// 连接测试：WebDAV `OPTIONS`；S3 对对象 URL `HEAD`（必要时回退 `GET`）。
  /// 不读写工作区正文；对象尚未存在（404）仍视为连通成功。
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

  Future<CloudRemoteDocument> downloadWorkspace(CloudSyncConfig config) async {
    if (config.kind == CloudSyncKind.none) {
      throw StateError('云同步未开启');
    }
    if (config.kind == CloudSyncKind.webdav) {
      return _get(config, webdav: true);
    }
    return _get(config, webdav: false);
  }

  /// [ifMatch] 为上次 GET 的 ETag；空表示远端还没有这份文件。
  Future<void> uploadWorkspace({
    required CloudSyncConfig config,
    required String body,
    String? ifMatch,
  }) async {
    if (config.kind == CloudSyncKind.none) {
      throw StateError('云同步未开启');
    }
    final bytes = utf8.encode(body);
    if (config.kind == CloudSyncKind.webdav) {
      await _put(config, bytes, ifMatch: ifMatch, webdav: true);
      return;
    }
    await _put(config, bytes, ifMatch: ifMatch, webdav: false);
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
    final url = _objectUrl(c, webdav: false);
    final headers = <String, String>{
      if (c.s3AccessKey.isNotEmpty) 'Authorization': 'Bearer ${c.s3AccessKey}',
    };

    http.Response resp;
    try {
      resp = await _http
          .head(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
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
    if ((resp.statusCode >= 200 && resp.statusCode < 300) ||
        resp.statusCode == 404) {
      return;
    }
    throw StateError('S3 响应异常（${resp.statusCode}）');
  }

  Future<CloudRemoteDocument> _get(
    CloudSyncConfig c, {
    required bool webdav,
  }) async {
    final url = _objectUrl(c, webdav: webdav);
    final resp = await _http
        .get(Uri.parse(url), headers: _authHeaders(c, webdav: webdav))
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode == 404) {
      return const CloudRemoteDocument();
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('${webdav ? 'WebDAV' : 'S3'} 下载失败(${resp.statusCode})');
    }
    return CloudRemoteDocument(
      body: utf8.decode(resp.bodyBytes, allowMalformed: true),
      etag: _etagOf(resp),
    );
  }

  Future<void> _put(
    CloudSyncConfig c,
    List<int> bytes, {
    required bool webdav,
    String? ifMatch,
  }) async {
    final url = _objectUrl(c, webdav: webdav);
    final headers = <String, String>{
      ..._authHeaders(c, webdav: webdav),
      'Content-Type': 'application/json; charset=utf-8',
      if (ifMatch != null && ifMatch.isNotEmpty) 'If-Match': ifMatch,
    };
    final resp = await _http
        .put(Uri.parse(url), headers: headers, body: bytes)
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode == 412) {
      throw CloudPreconditionFailed();
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError(
        webdav
            ? 'WebDAV 上传失败(${resp.statusCode})'
            : 'S3 上传失败(${resp.statusCode})。若使用标准 AWS，请配置支持匿名/网关 PUT 的兼容端点，或改用 WebDAV。',
      );
    }
  }

  Map<String, String> _authHeaders(
    CloudSyncConfig c, {
    required bool webdav,
  }) {
    if (webdav) {
      return {'Authorization': _basic(c.webdavUser, c.webdavPassword)};
    }
    return {
      if (c.s3AccessKey.isNotEmpty) 'Authorization': 'Bearer ${c.s3AccessKey}',
    };
  }

  String _objectUrl(CloudSyncConfig c, {required bool webdav}) {
    if (webdav) {
      return _join(c.webdavUrl, c.webdavPath, remoteFile);
    }
    final endpoint = c.s3Endpoint.replaceAll(RegExp(r'/+$'), '');
    final bucket = c.s3Bucket.trim();
    if (endpoint.contains('://')) {
      return '$endpoint/$bucket/$remoteFile';
    }
    final scheme = c.s3UseSsl ? 'https' : 'http';
    return '$scheme://$endpoint/$bucket/$remoteFile';
  }

  String? _etagOf(http.Response resp) {
    return resp.headers['etag'] ?? resp.headers['ETag'];
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
