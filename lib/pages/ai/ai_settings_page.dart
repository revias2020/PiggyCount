import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_provider_config.dart';
import '../../ai/ai_provider_store.dart';
import '../../providers/ai_providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/ai/ai_setup_helpers.dart';
import '../../widgets/page_status.dart';
import 'ai_provider_manage_page.dart';

/// AI 设置：服务商管理入口 + 文本/视觉能力绑定（ADR-009 / ADR-032）。
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
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
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
