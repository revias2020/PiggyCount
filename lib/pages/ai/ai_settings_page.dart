import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_config.dart';
import '../../ai/openai_compatible_client.dart';
import '../../providers/ai_providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/capsule_switcher.dart';
import '../../widgets/page_status.dart';

/// AI 模型配置：默认智谱，可切换 OpenAI 兼容。
class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _keyCtrl = TextEditingController();
  final _baseCtrl = TextEditingController();
  final _textModelCtrl = TextEditingController();
  final _visionModelCtrl = TextEditingController();
  final _client = OpenAiCompatibleClient();
  AiProviderKind _kind = AiProviderKind.zhipu;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await ref.read(aiConfigStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _kind = cfg.kind;
      _keyCtrl.text = cfg.apiKey;
      _baseCtrl.text = cfg.baseUrl;
      _textModelCtrl.text = cfg.textModel;
      _visionModelCtrl.text = cfg.visionModel;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _baseCtrl.dispose();
    _textModelCtrl.dispose();
    _visionModelCtrl.dispose();
    super.dispose();
  }

  AiConfig _build() => AiConfig(
        kind: _kind,
        apiKey: _keyCtrl.text.trim(),
        baseUrl: _baseCtrl.text.trim().isEmpty
            ? (_kind == AiProviderKind.zhipu
                ? AiConfig.zhipuDefaultBaseUrl
                : 'https://api.openai.com/v1')
            : _baseCtrl.text.trim(),
        textModel: _textModelCtrl.text.trim().isEmpty
            ? (_kind == AiProviderKind.zhipu
                ? AiConfig.zhipuDefaultTextModel
                : 'gpt-4o-mini')
            : _textModelCtrl.text.trim(),
        visionModel: _visionModelCtrl.text.trim().isEmpty
            ? (_kind == AiProviderKind.zhipu
                ? AiConfig.zhipuDefaultVisionModel
                : 'gpt-4o-mini')
            : _visionModelCtrl.text.trim(),
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(aiConfigStoreProvider).save(_build());
    ref.invalidate(aiConfigProvider);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存 AI 配置')),
    );
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      await _client.testConnection(_build());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接成功（文本与视觉均可用）')),
      );
    } catch (e) {
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

  void _applyKind(AiProviderKind kind) {
    setState(() {
      _kind = kind;
      if (kind == AiProviderKind.zhipu) {
        _baseCtrl.text = AiConfig.zhipuDefaultBaseUrl;
        if (_textModelCtrl.text.isEmpty ||
            _textModelCtrl.text.startsWith('gpt')) {
          _textModelCtrl.text = AiConfig.zhipuDefaultTextModel;
        }
        if (_visionModelCtrl.text.isEmpty ||
            _visionModelCtrl.text.startsWith('gpt')) {
          _visionModelCtrl.text = AiConfig.zhipuDefaultVisionModel;
        }
      } else {
        if (_baseCtrl.text.contains('bigmodel')) {
          _baseCtrl.text = 'https://api.openai.com/v1';
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: const Text('AI 模型配置'),
        actions: [
          TextButton(
            onPressed: _saving || _loading || _testing ? null : _save,
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
      body: _loading
          ? const AppLoading(message: '加载配置…')
          : ListView(
              padding: const EdgeInsets.all(PigTokens.spaceLg),
              children: [
                const Text(
                  '密钥仅保存在本机，不会上传到小猪记账服务器。',
                  style: TextStyle(fontSize: 13, color: PigTokens.textTertiary),
                ),
                const SizedBox(height: PigTokens.spaceMd),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('服务商',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: PigTokens.spaceSm),
                      CapsuleSwitcher<AiProviderKind>(
                        selectedValue: _kind,
                        onChanged: _applyKind,
                        options: const [
                          CapsuleOption(
                            value: AiProviderKind.zhipu,
                            label: '智谱',
                          ),
                          CapsuleOption(
                            value: AiProviderKind.openaiCompatible,
                            label: 'OpenAI 兼容',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PigTokens.spaceMd),
                _card(
                  child: Column(
                    children: [
                      TextField(
                        controller: _keyCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: PigTokens.spaceMd),
                      TextField(
                        controller: _baseCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Base URL',
                          border: OutlineInputBorder(),
                          helperText: '智谱默认 open.bigmodel.cn；兼容服务填 /v1 根路径',
                        ),
                      ),
                      const SizedBox(height: PigTokens.spaceMd),
                      TextField(
                        controller: _textModelCtrl,
                        decoration: const InputDecoration(
                          labelText: '文本模型',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: PigTokens.spaceMd),
                      TextField(
                        controller: _visionModelCtrl,
                        decoration: const InputDecoration(
                          labelText: '视觉模型（截图识别）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PigTokens.spaceLg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _saving || _testing ? null : _testConnection,
                    child: _testing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('测试连接'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PigTokens.spaceLg - 2),
      decoration: BoxDecoration(
        color: PigTokens.surface,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      ),
      child: child,
    );
  }
}
