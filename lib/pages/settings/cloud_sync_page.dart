import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/sync/cloud_sync_actions.dart';
import '../../services/sync/cloud_sync_config.dart';
import '../../services/sync/cloud_sync_providers.dart';
import '../../services/system/logger_service.dart';
import '../../styles/tokens.dart';
import '../../widgets/capsule_switcher.dart';

/// 云服务：WebDAV / S3 连接配置（不含上传/下载）。
class CloudSyncPage extends ConsumerStatefulWidget {
  const CloudSyncPage({super.key});

  @override
  ConsumerState<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends ConsumerState<CloudSyncPage> {
  CloudSyncKind _kind = CloudSyncKind.none;
  final _webdavUrl = TextEditingController();
  final _webdavUser = TextEditingController();
  final _webdavPass = TextEditingController();
  final _webdavPath = TextEditingController(text: '/piggy_count');
  final _s3Endpoint = TextEditingController();
  final _s3Region = TextEditingController(text: 'us-east-1');
  final _s3Access = TextEditingController();
  final _s3Secret = TextEditingController();
  final _s3Bucket = TextEditingController();
  bool _s3Ssl = true;
  bool _loading = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await ref.read(cloudSyncConfigStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _kind = c.kind;
      _webdavUrl.text = c.webdavUrl;
      _webdavUser.text = c.webdavUser;
      _webdavPass.text = c.webdavPassword;
      _webdavPath.text = c.webdavPath;
      _s3Endpoint.text = c.s3Endpoint;
      _s3Region.text = c.s3Region;
      _s3Access.text = c.s3AccessKey;
      _s3Secret.text = c.s3SecretKey;
      _s3Bucket.text = c.s3Bucket;
      _s3Ssl = c.s3UseSsl;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _webdavUrl.dispose();
    _webdavUser.dispose();
    _webdavPass.dispose();
    _webdavPath.dispose();
    _s3Endpoint.dispose();
    _s3Region.dispose();
    _s3Access.dispose();
    _s3Secret.dispose();
    _s3Bucket.dispose();
    super.dispose();
  }

  CloudSyncConfig _build() => CloudSyncConfig(
        kind: _kind,
        webdavUrl: _webdavUrl.text.trim(),
        webdavUser: _webdavUser.text.trim(),
        webdavPassword: _webdavPass.text,
        webdavPath: _webdavPath.text.trim().isEmpty
            ? '/piggy_count'
            : _webdavPath.text.trim(),
        s3Endpoint: _s3Endpoint.text.trim(),
        s3Region: _s3Region.text.trim(),
        s3AccessKey: _s3Access.text.trim(),
        s3SecretKey: _s3Secret.text,
        s3Bucket: _s3Bucket.text.trim(),
        s3UseSsl: _s3Ssl,
      );

  Future<void> _save() async {
    final store = ref.read(cloudSyncConfigStoreProvider);
    final previous = await store.load();
    final next = _build().withPreservedVerification(previous);
    await store.save(next);
    ref.invalidate(cloudSyncConfigProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next.isReadyForSync ? '云服务配置已保存' : '云服务配置已保存（尚未测通）',
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _testConnection() async {
    if (_kind == CloudSyncKind.none || _testing) return;
    setState(() => _testing = true);
    try {
      final draft = _build();
      await ref.read(cloudSyncServiceProvider).testConnection(draft);
      await persistCloudVerifiedAfterTest(ref: ref, draft: draft);
      if (!mounted) return;
      final saved = await ref.read(cloudSyncConfigStoreProvider).load();
      if (!mounted) return;
      final readyNow = saved.isReadyForSync &&
          draft.connectionFingerprint() == saved.verifiedFingerprint;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            readyNow ? '连接成功' : '连接成功，请点保存以启用同步',
          ),
        ),
      );
      setState(() {});
    } catch (e, st) {
      logger.error('Cloud', '连接测试失败', e, st);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('连接失败'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: const Text('云服务'),
        actions: [
          TextButton(onPressed: _loading ? null : _save, child: const Text('保存')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '默认仅本机存储。选择 WebDAV 或 S3 并测通后，可在「同步」对齐全部账本与分类/标签。\n'
                  '凭证只保存在本机。改凭证后需重新测通。',
                  style: TextStyle(fontSize: 13, color: PigTokens.textTertiary),
                ),
                const SizedBox(height: 12),
                _card(child: _kindPicker()),
                if (_kind == CloudSyncKind.webdav) ...[
                  const SizedBox(height: 12),
                  _card(child: _webdavFields()),
                ],
                if (_kind == CloudSyncKind.s3) ...[
                  const SizedBox(height: 12),
                  _card(child: _s3Fields()),
                ],
                if (_kind != CloudSyncKind.none) ...[
                  const SizedBox(height: 16),
                  _testButton(),
                ],
              ],
            ),
    );
  }

  Widget _testButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _testing ? null : _testConnection,
        child: _testing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('测试连接'),
      ),
    );
  }

  Widget _kindPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('同步方式', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        CapsuleSwitcher<CloudSyncKind>(
          selectedValue: _kind,
          onChanged: (v) => setState(() => _kind = v),
          options: const [
            CapsuleOption(value: CloudSyncKind.none, label: '关闭'),
            CapsuleOption(value: CloudSyncKind.webdav, label: 'WebDAV'),
            CapsuleOption(value: CloudSyncKind.s3, label: 'S3'),
          ],
        ),
      ],
    );
  }

  Widget _webdavFields() {
    return Column(
      children: [
        _field(_webdavUrl, '服务器地址', hint: 'https://dav.example.com'),
        _field(_webdavUser, '用户名'),
        _field(_webdavPass, '密码', obscure: true),
        _field(_webdavPath, '远端路径', hint: '/piggy_count'),
      ],
    );
  }

  Widget _s3Fields() {
    return Column(
      children: [
        _field(_s3Endpoint, 'Endpoint', hint: 's3.amazonaws.com'),
        _field(_s3Region, 'Region'),
        _field(_s3Bucket, 'Bucket'),
        _field(_s3Access, 'Access Key'),
        _field(_s3Secret, 'Secret Key', obscure: true),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('使用 SSL'),
          value: _s3Ssl,
          onChanged: (v) => setState(() => _s3Ssl = v),
        ),
        const Text(
          'MVP：S3 需端点支持简单 HTTP PUT/GET（如部分 MinIO/网关）。完整 SigV4 后续增强；推荐优先 WebDAV。',
          style: TextStyle(fontSize: 12, color: PigTokens.textTertiary),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) => Material(
        color: PigTokens.surface,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(width: double.infinity, child: child),
        ),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
