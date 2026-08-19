import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_provider_config.dart';
import '../../ai/openai_compatible_client.dart';
import '../../providers/ai_providers.dart';
import '../../services/system/logger_service.dart';
import '../../styles/tokens.dart';
import '../../widgets/ai/ai_setup_helpers.dart';

enum _TestStatus { idle, testing, success, failed }

/// 服务商编辑：凭证块 + 模型块；内联测连；保存自动测连（ADR-009 / ADR-032）。
class AiProviderEditPage extends ConsumerStatefulWidget {
  const AiProviderEditPage({super.key, this.provider});

  /// null = 新建自定义服务商。
  final AiServiceProvider? provider;

  @override
  ConsumerState<AiProviderEditPage> createState() =>
      _AiProviderEditPageState();
}

class _AiProviderEditPageState extends ConsumerState<AiProviderEditPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _baseCtrl;
  late final TextEditingController _textModelCtrl;
  late final TextEditingController _visionModelCtrl;
  final _client = OpenAiCompatibleClient();

  bool _obscure = true;
  bool _saving = false;
  _TestStatus _textStatus = _TestStatus.idle;
  _TestStatus _visionStatus = _TestStatus.idle;
  String? _textError;
  String? _visionError;

  bool get _isBuiltIn => widget.provider?.isBuiltIn ?? false;
  bool get _isEditing => widget.provider != null;
  bool get _isTesting =>
      _textStatus == _TestStatus.testing ||
      _visionStatus == _TestStatus.testing;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _nameCtrl = TextEditingController(
      text: p?.name ?? '',
    );
    _keyCtrl = TextEditingController(text: p?.apiKey ?? '');
    _baseCtrl = TextEditingController(
      text: p?.baseUrl ??
          (p?.isBuiltIn == true
              ? AiServiceProvider.zhipuDefaultBaseUrl
              : 'https://api.openai.com/v1'),
    );
    _textModelCtrl = TextEditingController(
      text: p?.textModel ??
          (p?.isBuiltIn == true
              ? AiServiceProvider.zhipuDefaultTextModel
              : 'gpt-4o-mini'),
    );
    _visionModelCtrl = TextEditingController(
      text: p?.visionModel ??
          (p?.isBuiltIn == true
              ? AiServiceProvider.zhipuDefaultVisionModel
              : 'gpt-4o-mini'),
    );
    _keyCtrl.addListener(_onCredentialsChanged);
    _baseCtrl.addListener(_onCredentialsChanged);
    _textModelCtrl.addListener(_onTextModelChanged);
    _visionModelCtrl.addListener(_onVisionModelChanged);
  }

  void _onCredentialsChanged() {
    _client.cancelTests();
    setState(() {
      _textStatus = _TestStatus.idle;
      _visionStatus = _TestStatus.idle;
      _textError = null;
      _visionError = null;
    });
  }

  void _onTextModelChanged() {
    _client.cancelTests();
    setState(() {
      if (_textStatus != _TestStatus.idle) {
        _textStatus = _TestStatus.idle;
        _textError = null;
      }
    });
  }

  void _onVisionModelChanged() {
    _client.cancelTests();
    setState(() {
      if (_visionStatus != _TestStatus.idle) {
        _visionStatus = _TestStatus.idle;
        _visionError = null;
      }
    });
  }

  @override
  void dispose() {
    _client.cancelTests();
    _keyCtrl.removeListener(_onCredentialsChanged);
    _baseCtrl.removeListener(_onCredentialsChanged);
    _textModelCtrl.removeListener(_onTextModelChanged);
    _visionModelCtrl.removeListener(_onVisionModelChanged);
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    _baseCtrl.dispose();
    _textModelCtrl.dispose();
    _visionModelCtrl.dispose();
    super.dispose();
  }

  AiServiceProvider _draft({
    AiModelTestStatus? textTestStatus,
    AiModelTestStatus? visionTestStatus,
  }) {
    final existing = widget.provider;
    final textModel = _textModelCtrl.text.trim();
    final visionModel = _visionModelCtrl.text.trim();
    // 新建时空模型与 addCustomProvider 默认一致，保证测连与落库同值。
    final persistText = !_isEditing && textModel.isEmpty
        ? 'gpt-4o-mini'
        : textModel;
    final persistVision = !_isEditing && visionModel.isEmpty
        ? 'gpt-4o-mini'
        : visionModel;

    if (_isBuiltIn && existing != null) {
      return existing.copyWith(
        apiKey: _keyCtrl.text.trim(),
        textModel: persistText,
        visionModel: persistVision,
        textTestStatus: textTestStatus,
        visionTestStatus: visionTestStatus,
      );
    }
    return AiServiceProvider(
      id: existing?.id ?? 'draft',
      name: _nameCtrl.text.trim().isEmpty
          ? '自定义服务商'
          : _nameCtrl.text.trim(),
      isBuiltIn: false,
      apiKey: _keyCtrl.text.trim(),
      baseUrl: _baseCtrl.text.trim().isEmpty
          ? 'https://api.openai.com/v1'
          : _baseCtrl.text.trim(),
      textModel: persistText,
      visionModel: persistVision,
      createdAt: existing?.createdAt ?? DateTime.now(),
      textTestStatus: textTestStatus ?? AiModelTestStatus.untested,
      visionTestStatus: visionTestStatus ?? AiModelTestStatus.untested,
    );
  }

  /// 本页已成功，或入库未脏且已成功 → 跳过打网（ADR-032）。
  bool _canTrustText(AiServiceProvider draft) {
    if (_textStatus == _TestStatus.success) return true;
    if (draft.textModel.trim().isEmpty) return true;
    final existing = widget.provider;
    if (existing == null) return false;
    return existing.textTestStatus == AiModelTestStatus.success &&
        existing.apiKey.trim() == draft.apiKey.trim() &&
        existing.baseUrl.trim() == draft.baseUrl.trim() &&
        existing.textModel.trim() == draft.textModel.trim();
  }

  bool _canTrustVision(AiServiceProvider draft) {
    if (_visionStatus == _TestStatus.success) return true;
    if (draft.visionModel.trim().isEmpty) return true;
    final existing = widget.provider;
    if (existing == null) return false;
    return existing.visionTestStatus == AiModelTestStatus.success &&
        existing.apiKey.trim() == draft.apiKey.trim() &&
        existing.baseUrl.trim() == draft.baseUrl.trim() &&
        existing.visionModel.trim() == draft.visionModel.trim();
  }

  AiModelTestStatus _statusFromUi(_TestStatus s, {required bool hasModel}) {
    if (!hasModel) return AiModelTestStatus.untested;
    return switch (s) {
      _TestStatus.success => AiModelTestStatus.success,
      _TestStatus.failed => AiModelTestStatus.failed,
      _ => AiModelTestStatus.untested,
    };
  }

  Future<void> _ensureTestsBeforeSave() async {
    final draft = _draft();

    if (draft.textModel.trim().isEmpty) {
      if (_textStatus != _TestStatus.idle || _textError != null) {
        setState(() {
          _textStatus = _TestStatus.idle;
          _textError = null;
        });
      }
    } else if (_canTrustText(draft)) {
      if (_textStatus != _TestStatus.success) {
        setState(() {
          _textStatus = _TestStatus.success;
          _textError = null;
        });
      }
    } else {
      await _testText();
    }

    if (!mounted) return;

    if (draft.visionModel.trim().isEmpty) {
      if (_visionStatus != _TestStatus.idle || _visionError != null) {
        setState(() {
          _visionStatus = _TestStatus.idle;
          _visionError = null;
        });
      }
    } else if (_canTrustVision(draft)) {
      if (_visionStatus != _TestStatus.success) {
        setState(() {
          _visionStatus = _TestStatus.success;
          _visionError = null;
        });
      }
    } else {
      await _testVision();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _ensureTestsBeforeSave();
      if (!mounted) return;

      final normalized = _draft();
      final textFailed = normalized.textModel.isNotEmpty &&
          _textStatus == _TestStatus.failed;
      final visionFailed = normalized.visionModel.isNotEmpty &&
          _visionStatus == _TestStatus.failed;

      // 测连被取消或仍 idle（非空模型）则中止保存。
      if (normalized.textModel.isNotEmpty &&
          _textStatus != _TestStatus.success &&
          _textStatus != _TestStatus.failed) {
        return;
      }
      if (normalized.visionModel.isNotEmpty &&
          _visionStatus != _TestStatus.success &&
          _visionStatus != _TestStatus.failed) {
        return;
      }

      final toSave = _draft(
        textTestStatus: _statusFromUi(
          _textStatus,
          hasModel: normalized.textModel.isNotEmpty,
        ),
        visionTestStatus: _statusFromUi(
          _visionStatus,
          hasModel: normalized.visionModel.isNotEmpty,
        ),
      );

      final store = ref.read(aiProviderStoreProvider);
      if (_isEditing) {
        await store.updateProvider(toSave);
      } else {
        await store.addCustomProvider(
          name: toSave.name,
          apiKey: toSave.apiKey,
          baseUrl: toSave.baseUrl,
          textModel: toSave.textModel,
          visionModel: toSave.visionModel,
          textTestStatus: toSave.textTestStatus,
          visionTestStatus: toSave.visionTestStatus,
        );
      }
      ref.invalidate(aiProvidersListProvider);
      ref.invalidate(aiMineSubtitleProvider);
      ref.invalidate(aiCapabilityBindingProvider);
      if (!mounted) return;

      if (textFailed || visionFailed) {
        final parts = <String>[
          if (textFailed) '文本模型',
          if (visionFailed) '视觉模型',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${parts.join('、')}不可用，已保存但对应能力不可选',
            ),
          ),
        );
        return;
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testText() async {
    setState(() {
      _textStatus = _TestStatus.testing;
      _textError = null;
    });
    try {
      await _client.testText(_draft());
      if (!mounted) return;
      setState(() => _textStatus = _TestStatus.success);
    } on AiTestCancelledException {
      if (!mounted) return;
      setState(() {
        _textStatus = _TestStatus.idle;
        _textError = null;
      });
    } catch (e) {
      logger.warning('AiTest', '文本模型测连失败: $e');
      if (!mounted) return;
      setState(() {
        _textStatus = _TestStatus.failed;
        _textError = '$e';
      });
    }
  }

  Future<void> _testVision() async {
    setState(() {
      _visionStatus = _TestStatus.testing;
      _visionError = null;
    });
    try {
      await _client.testVision(_draft());
      if (!mounted) return;
      setState(() => _visionStatus = _TestStatus.success);
    } on AiTestCancelledException {
      if (!mounted) return;
      setState(() {
        _visionStatus = _TestStatus.idle;
        _visionError = null;
      });
    } catch (e) {
      logger.warning('AiTest', '视觉模型测连失败: $e');
      if (!mounted) return;
      setState(() {
        _visionStatus = _TestStatus.failed;
        _visionError = '$e';
      });
    }
  }

  Future<void> _testAll() async {
    // 顺序测：client 的 generation 会使并行测连互相取消。
    await _testText();
    if (!mounted) return;
    await _testVision();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: Text(_isEditing ? '编辑服务商' : '添加服务商'),
        actions: [
          TextButton(
            onPressed: _saving || _isTesting ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(PigTokens.spaceLg),
        children: [
          aiSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '凭证',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: PigTokens.spaceMd),
                if (!_isBuiltIn) ...[
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: PigTokens.spaceMd),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: PigTokens.spaceMd),
                    child: Text(
                      widget.provider!.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                TextField(
                  controller: _keyCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: PigTokens.spaceMd),
                TextField(
                  controller: _baseCtrl,
                  enabled: !_isBuiltIn,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PigTokens.spaceMd),
          aiSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '模型',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: PigTokens.spaceMd),
                _ModelField(
                  label: '文本模型',
                  controller: _textModelCtrl,
                  status: _textStatus,
                  error: _textError,
                  onTest: _testText,
                  enabled: _keyCtrl.text.trim().isNotEmpty &&
                      _textModelCtrl.text.trim().isNotEmpty,
                ),
                const SizedBox(height: PigTokens.spaceMd),
                _ModelField(
                  label: '视觉模型',
                  controller: _visionModelCtrl,
                  status: _visionStatus,
                  error: _visionError,
                  onTest: _testVision,
                  enabled: _keyCtrl.text.trim().isNotEmpty &&
                      _visionModelCtrl.text.trim().isNotEmpty,
                ),
                const SizedBox(height: PigTokens.spaceLg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isTesting ||
                            _keyCtrl.text.trim().isEmpty
                        ? null
                        : _testAll,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _textStatus == _TestStatus.success &&
                                    _visionStatus == _TestStatus.success
                                ? Icons.check_circle
                                : Icons.play_arrow,
                            color: _textStatus == _TestStatus.success &&
                                    _visionStatus == _TestStatus.success
                                ? Colors.green
                                : null,
                          ),
                    label: Text(
                      _textStatus == _TestStatus.success &&
                              _visionStatus == _TestStatus.success
                          ? '测试通过'
                          : '一键测试',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelField extends StatelessWidget {
  const _ModelField({
    required this.label,
    required this.controller,
    required this.status,
    required this.error,
    required this.onTest,
    required this.enabled,
  });

  final String label;
  final TextEditingController controller;
  final _TestStatus status;
  final String? error;
  final VoidCallback onTest;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            _InlineTestButton(
              status: status,
              onTest: onTest,
              enabled: enabled && status != _TestStatus.testing,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        if (status == _TestStatus.failed && error != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              error!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        ],
      ],
    );
  }
}

class _InlineTestButton extends StatelessWidget {
  const _InlineTestButton({
    required this.status,
    required this.onTest,
    required this.enabled,
  });

  final _TestStatus status;
  final VoidCallback onTest;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (status == _TestStatus.testing) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (status == _TestStatus.success) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 22);
    }
    return TextButton(
      onPressed: enabled ? onTest : null,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('测试'),
    );
  }
}
