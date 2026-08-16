import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 云同步后端类型；默认关闭（仅本机）。
enum CloudSyncKind { none, webdav, s3 }

class CloudSyncConfig {
  const CloudSyncConfig({
    this.kind = CloudSyncKind.none,
    this.webdavUrl = '',
    this.webdavUser = '',
    this.webdavPassword = '',
    this.webdavPath = '/piggy_count',
    this.s3Endpoint = '',
    this.s3Region = 'us-east-1',
    this.s3AccessKey = '',
    this.s3SecretKey = '',
    this.s3Bucket = '',
    this.s3UseSsl = true,
    this.verifiedFingerprint = '',
  });

  final CloudSyncKind kind;
  final String webdavUrl;
  final String webdavUser;
  final String webdavPassword;
  final String webdavPath;
  final String s3Endpoint;
  final String s3Region;
  final String s3AccessKey;
  final String s3SecretKey;
  final String s3Bucket;
  final bool s3UseSsl;

  /// 已测通时的连接指纹；空表示尚未测通。
  final String verifiedFingerprint;

  bool get isEnabled => kind != CloudSyncKind.none;

  /// WebDAV：URL；S3：endpoint + bucket + access + secret。
  bool get hasRequiredFields {
    switch (kind) {
      case CloudSyncKind.none:
        return false;
      case CloudSyncKind.webdav:
        return webdavUrl.trim().isNotEmpty;
      case CloudSyncKind.s3:
        return s3Endpoint.trim().isNotEmpty &&
            s3Bucket.trim().isNotEmpty &&
            s3AccessKey.trim().isNotEmpty &&
            s3SecretKey.isNotEmpty;
    }
  }

  /// 连接相关字段指纹（改凭证即变）。
  String connectionFingerprint() {
    switch (kind) {
      case CloudSyncKind.none:
        return 'none';
      case CloudSyncKind.webdav:
        return [
          'webdav',
          webdavUrl.trim(),
          webdavUser.trim(),
          webdavPassword,
          webdavPath.trim().isEmpty ? '/piggy_count' : webdavPath.trim(),
        ].join('|');
      case CloudSyncKind.s3:
        return [
          's3',
          s3Endpoint.trim(),
          s3Region.trim(),
          s3Bucket.trim(),
          s3AccessKey.trim(),
          s3SecretKey,
          s3UseSsl ? '1' : '0',
        ].join('|');
    }
  }

  /// 已保存配置可用于快捷同步 / 云页操作区。
  bool get isReadyForSync {
    if (!hasRequiredFields) return false;
    final fp = connectionFingerprint();
    return verifiedFingerprint.isNotEmpty && verifiedFingerprint == fp;
  }

  String get kindLabel {
    switch (kind) {
      case CloudSyncKind.none:
        return '关闭';
      case CloudSyncKind.webdav:
        return 'WebDAV';
      case CloudSyncKind.s3:
        return 'S3';
    }
  }

  /// 「我的 · 云服务」副标题。
  String get mineSubtitle {
    if (kind == CloudSyncKind.none) return '默认仅本机';
    if (!hasRequiredFields) return '$kindLabel · 配置不完整';
    if (!isReadyForSync) return '$kindLabel · 未测通';
    return kindLabel;
  }

  CloudSyncConfig copyWith({
    CloudSyncKind? kind,
    String? webdavUrl,
    String? webdavUser,
    String? webdavPassword,
    String? webdavPath,
    String? s3Endpoint,
    String? s3Region,
    String? s3AccessKey,
    String? s3SecretKey,
    String? s3Bucket,
    bool? s3UseSsl,
    String? verifiedFingerprint,
  }) {
    return CloudSyncConfig(
      kind: kind ?? this.kind,
      webdavUrl: webdavUrl ?? this.webdavUrl,
      webdavUser: webdavUser ?? this.webdavUser,
      webdavPassword: webdavPassword ?? this.webdavPassword,
      webdavPath: webdavPath ?? this.webdavPath,
      s3Endpoint: s3Endpoint ?? this.s3Endpoint,
      s3Region: s3Region ?? this.s3Region,
      s3AccessKey: s3AccessKey ?? this.s3AccessKey,
      s3SecretKey: s3SecretKey ?? this.s3SecretKey,
      s3Bucket: s3Bucket ?? this.s3Bucket,
      s3UseSsl: s3UseSsl ?? this.s3UseSsl,
      verifiedFingerprint: verifiedFingerprint ?? this.verifiedFingerprint,
    );
  }

  /// 保存表单时：指纹未变则保留已测通，否则清除。
  CloudSyncConfig withPreservedVerification(CloudSyncConfig previous) {
    final fp = connectionFingerprint();
    if (previous.verifiedFingerprint.isNotEmpty &&
        previous.verifiedFingerprint == fp) {
      return copyWith(verifiedFingerprint: previous.verifiedFingerprint);
    }
    return copyWith(verifiedFingerprint: '');
  }

  CloudSyncConfig markedVerified() =>
      copyWith(verifiedFingerprint: connectionFingerprint());

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'webdavUrl': webdavUrl,
        'webdavUser': webdavUser,
        'webdavPassword': webdavPassword,
        'webdavPath': webdavPath,
        's3Endpoint': s3Endpoint,
        's3Region': s3Region,
        's3AccessKey': s3AccessKey,
        's3SecretKey': s3SecretKey,
        's3Bucket': s3Bucket,
        's3UseSsl': s3UseSsl,
        'verifiedFingerprint': verifiedFingerprint,
      };

  factory CloudSyncConfig.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'none';
    final kind = CloudSyncKind.values.firstWhere(
      (e) => e.name == kindName,
      orElse: () => CloudSyncKind.none,
    );
    return CloudSyncConfig(
      kind: kind,
      webdavUrl: json['webdavUrl'] as String? ?? '',
      webdavUser: json['webdavUser'] as String? ?? '',
      webdavPassword: json['webdavPassword'] as String? ?? '',
      webdavPath: json['webdavPath'] as String? ?? '/piggy_count',
      s3Endpoint: json['s3Endpoint'] as String? ?? '',
      s3Region: json['s3Region'] as String? ?? 'us-east-1',
      s3AccessKey: json['s3AccessKey'] as String? ?? '',
      s3SecretKey: json['s3SecretKey'] as String? ?? '',
      s3Bucket: json['s3Bucket'] as String? ?? '',
      s3UseSsl: json['s3UseSsl'] as bool? ?? true,
      verifiedFingerprint: json['verifiedFingerprint'] as String? ?? '',
    );
  }
}

class CloudSyncConfigStore {
  static const _key = 'cloud_sync_config_v1';

  Future<CloudSyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const CloudSyncConfig();
    try {
      return CloudSyncConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const CloudSyncConfig();
    }
  }

  Future<void> save(CloudSyncConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }

  /// 只更新已测通标记（不改写连接字段）；用于测连成功且用户尚未点保存。
  Future<CloudSyncConfig> markVerifiedFingerprint(String fingerprint) async {
    final current = await load();
    final next = current.copyWith(verifiedFingerprint: fingerprint);
    await save(next);
    return next;
  }
}
