import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_provider_config.dart';
import '../../ai/ai_provider_store.dart';
import '../../providers/ai_providers.dart';
import '../../services/ai/offline_asr_model_store.dart';
import '../../services/ai/speech_engine_preference.dart';
import '../../styles/tokens.dart';
import '../../widgets/ai/ai_setup_helpers.dart';
import '../../widgets/page_status.dart';
import 'ai_provider_manage_page.dart';

/// AI 设置：服务商管理入口 + 文本/视觉/语音能力绑定 + 语音识别引擎（ADR-009 / ADR-032 / ADR-052）。
class AiSettingsPage extends ConsumerWidget {
  const AiSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(aiProvidersListProvider);
    final bindingAsync = ref.watch(aiCapabilityBindingProvider);

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: const Text('AI 设置')),
      body: providersAsync.when(
        loading: () => const AppLoading(message: '加载配置…'),
        error: (e, _) => Center(child: Text('$e')),
        data: (providers) => bindingAsync.when(
          loading: () => const AppLoading(message: '加载配置…'),
          error: (e, _) => Center(child: Text('$e')),
          data: (binding) {
            final keyed = providers.where((p) => p.isValid).length;
            return ListView(
              padding: const EdgeInsets.all(PigTokens.spaceLg),
              children: [
                const Text(
                  '密钥仅保存在本机，不会上传到小猪记账服务器。',
                  style: TextStyle(fontSize: 13, color: PigTokens.textTertiary),
                ),
                const SizedBox(height: PigTokens.spaceMd),
                aiSectionCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.cloud_outlined,
                      color: PigTokens.primary,
                    ),
                    title: const Text(
                      '服务商管理',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '$keyed/${AiProviderStore.maxCustomProviders} 已配置Key',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AiProviderManagePage(),
                        ),
                      );
                      ref.invalidate(aiProvidersListProvider);
                      ref.invalidate(aiCapabilityBindingProvider);
                      ref.invalidate(aiMineSubtitleProvider);
                    },
                  ),
                ),
                const SizedBox(height: PigTokens.spaceMd),
                aiSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '为每个AI能力选择服务商',
                        style: TextStyle(
                          fontSize: 12,
                          color: PigTokens.textTertiary,
                        ),
                      ),
                      const SizedBox(height: PigTokens.spaceMd),
                      _CapabilityTile(
                        icon: Icons.chat_outlined,
                        title: '文本对话',
                        currentId: binding.textProviderId,
                        allProviders: providers,
                        providers: providers
                            .where((p) => p.textReadyForCapability)
                            .toList(),
                        onSelected: (id) async {
                          await ref.read(aiProviderStoreProvider).saveBinding(
                                binding.copyWith(textProviderId: id),
                              );
                          ref.invalidate(aiCapabilityBindingProvider);
                        },
                      ),
                      const Divider(height: 24),
                      _CapabilityTile(
                        icon: Icons.image_outlined,
                        title: '图片理解',
                        currentId: binding.visionProviderId,
                        allProviders: providers,
                        providers: providers
                            .where((p) => p.visionReadyForCapability)
                            .toList(),
                        onSelected: (id) async {
                          await ref.read(aiProviderStoreProvider).saveBinding(
                                binding.copyWith(visionProviderId: id),
                              );
                          ref.invalidate(aiCapabilityBindingProvider);
                        },
                      ),
                      const Divider(height: 24),
                      _CapabilityTile(
                        icon: Icons.mic_outlined,
                        title: '语音记账',
                        currentId: binding.voiceProviderId,
                        allProviders: providers,
                        providers: providers
                            .where((p) => p.voiceReadyForCapability)
                            .toList(),
                        onSelected: (id) async {
                          await ref.read(aiProviderStoreProvider).saveBinding(
                                binding.copyWith(voiceProviderId: id),
                              );
                          ref.invalidate(aiCapabilityBindingProvider);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PigTokens.spaceMd),
                _SpeechRecognitionSection(providers: providers),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 语音识别引擎选择与离线模型下载（ADR-052）。
class _SpeechRecognitionSection extends ConsumerStatefulWidget {
  const _SpeechRecognitionSection({required this.providers});

  final List<AiServiceProvider> providers;

  @override
  ConsumerState<_SpeechRecognitionSection> createState() =>
      _SpeechRecognitionSectionState();
}

class _SpeechRecognitionSectionState
    extends ConsumerState<_SpeechRecognitionSection> {
  bool? _voskReady;
  bool? _whisperReady;

  @override
  void initState() {
    super.initState();
    _refreshOfflineReady();
  }

  Future<void> _refreshOfflineReady() async {
    final store = ref.read(offlineAsrModelStoreProvider);
    final vosk = await store.isReady(OfflineAsrModelCatalog.vosk);
    final whisper = await store.isReady(OfflineAsrModelCatalog.whisper);
    if (!mounted) return;
    setState(() {
      _voskReady = vosk;
      _whisperReady = whisper;
    });
  }

  Future<void> _saveEngine(SpeechRecognitionEngineKind kind) async {
    await ref.read(speechEnginePreferenceStoreProvider).save(kind);
    ref.invalidate(speechEngineKindProvider);
  }

  Future<void> _selectOffline(SpeechRecognitionEngineKind kind) async {
    final spec = OfflineAsrModelCatalog.forEngine(kind);
    if (spec == null) return;
    final store = ref.read(offlineAsrModelStoreProvider);
    final ready = await store.isReady(spec);
    if (!ready) {
      final ok = await _downloadWithProgress(spec);
      if (!ok || !mounted) return;
      await _refreshOfflineReady();
    }
    if (!mounted) return;
    await _saveEngine(kind);
  }

  Future<bool> _downloadWithProgress(OfflineAsrModelSpec spec) async {
    final progressNotifier = ValueNotifier<double>(0);
    final statusNotifier = ValueNotifier<String>('准备下载…');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('下载 ${spec.displayName}'),
            content: ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (_, value, __) {
                return ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (_, status, __) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LinearProgressIndicator(
                          value: value <= 0 ? null : value.clamp(0.0, 1.0),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          value <= 0
                              ? status
                              : '${(value * 100).clamp(0, 100).toStringAsFixed(0)}% · $status',
                          style: const TextStyle(
                            fontSize: 13,
                            color: PigTokens.textSecondary,
                          ),
                        ),
                        if (spec.hasForeignFallback) ...[
                          const SizedBox(height: 12),
                          const Text(
                            '优先国内镜像；若切换至官方源，可能需要 VPN 或代理。',
                            style: TextStyle(
                              fontSize: 12,
                              color: PigTokens.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );

    try {
      await ref.read(offlineAsrModelStoreProvider).download(
            spec,
            onProgress: (p) => progressNotifier.value = p,
            onSourceAttempt: (source) {
              statusNotifier.value = source.requiresVpnHint
                  ? '正在从${source.label}下载（可能需要 VPN）…'
                  : '正在从${source.label}下载…';
            },
          );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progressNotifier.dispose();
      statusNotifier.dispose();
      return true;
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progressNotifier.dispose();
      statusNotifier.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
      return false;
    }
  }

  Future<void> _selectAiVoice() async {
    final voiceReady =
        widget.providers.any((p) => p.voiceReadyForCapability);
    if (!voiceReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先配置并测通支持语音的服务商，再绑定「语音记账」'),
        ),
      );
      return;
    }
    await _saveEngine(SpeechRecognitionEngineKind.aiVoice);
  }

  @override
  Widget build(BuildContext context) {
    final engineAsync = ref.watch(speechEngineKindProvider);
    final systemAsync = ref.watch(systemAsrAvailableProvider);
    final current = engineAsync.valueOrNull;
    final systemOk = systemAsync.valueOrNull ?? false;

    return aiSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '语音识别',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            current == null
                ? '当前引擎：加载中…'
                : '当前引擎：${current.label}',
            style: const TextStyle(
              fontSize: 12,
              color: PigTokens.textTertiary,
            ),
          ),
          const SizedBox(height: PigTokens.spaceMd),
          const Text(
            '离线模型需单独下载，优先国内镜像；失败将自动尝试官方源，'
            '访问国外源可能需要 VPN 或代理。',
            style: TextStyle(
              fontSize: 12,
              color: PigTokens.textTertiary,
            ),
          ),
          const SizedBox(height: PigTokens.spaceMd),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: PigTokens.spaceSm,
              crossAxisSpacing: PigTokens.spaceSm,
              mainAxisExtent: 56,
            ),
            children: [
              _EngineTile(
                title: SpeechRecognitionEngineKind.system.label,
                selected: current == SpeechRecognitionEngineKind.system,
                enabled: systemOk,
                subtitle: systemOk ? null : '本机不可用',
                onTap: systemOk
                    ? () => _saveEngine(SpeechRecognitionEngineKind.system)
                    : null,
              ),
              _EngineTile(
                title: SpeechRecognitionEngineKind.vosk.label,
                selected: current == SpeechRecognitionEngineKind.vosk,
                subtitle: _offlineSubtitle(_voskReady),
                onTap: () => _selectOffline(SpeechRecognitionEngineKind.vosk),
              ),
              _EngineTile(
                title: SpeechRecognitionEngineKind.whisper.label,
                selected: current == SpeechRecognitionEngineKind.whisper,
                subtitle: _offlineSubtitle(_whisperReady),
                onTap: () => _selectOffline(SpeechRecognitionEngineKind.whisper),
              ),
              _EngineTile(
                title: SpeechRecognitionEngineKind.aiVoice.label,
                selected: current == SpeechRecognitionEngineKind.aiVoice,
                subtitle: widget.providers.any((p) => p.voiceReadyForCapability)
                    ? null
                    : '未配置',
                onTap: _selectAiVoice,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _offlineSubtitle(bool? ready) {
    if (ready == null) return '检查中…';
    return ready ? '已下载' : '未下载（点此下载）';
  }
}

class _EngineTile extends StatelessWidget {
  const _EngineTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final bool selected;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(PigTokens.radiusCard - 4);
    final tile = Material(
      color: selected ? PigTokens.primarySoft : PigTokens.surfaceSecondary,
      borderRadius: radius,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PigTokens.spaceSm,
            vertical: 6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: enabled ? null : PigTokens.textTertiary,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check,
                      size: 16,
                      color: PigTokens.primary,
                    ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: PigTokens.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (enabled) return tile;
    return Opacity(opacity: 0.45, child: tile);
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({
    required this.icon,
    required this.title,
    required this.currentId,
    required this.allProviders,
    required this.providers,
    required this.onSelected,
  });

  final IconData icon;
  final String title;
  final String? currentId;
  final List<AiServiceProvider> allProviders;
  final List<AiServiceProvider> providers;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    AiServiceProvider? current;
    for (final p in allProviders) {
      if (p.id == currentId) {
        current = p;
        break;
      }
    }
    final inPicker = providers.any((p) => p.id == currentId);
    final label = current == null
        ? (currentId == null || currentId!.isEmpty ? '未选择' : '（已失效，请重选）')
        : (inPicker ? current.name : '${current.name}（请重选）');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: PigTokens.primary),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              label,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: current == null
                    ? PigTokens.textTertiary
                    : PigTokens.textSecondary,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: PigTokens.textTertiary),
        ],
      ),
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    if (providers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暂无已测通的服务商，请先到服务商编辑页保存以完成连接测试'),
        ),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择服务商',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            for (final p in providers)
              ListTile(
                title: Text(p.name),
                subtitle: Text(
                  p.isValid ? '已配置 Key' : '未配置 Key',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: p.id == currentId
                    ? const Icon(Icons.check, color: PigTokens.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, p.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) onSelected(selected);
  }
}
