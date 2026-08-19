import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_provider_config.dart';
import '../../ai/ai_provider_store.dart';
import '../../providers/ai_providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/ai/ai_setup_helpers.dart';
import '../../widgets/page_status.dart';
import 'ai_provider_edit_page.dart';

/// 服务商列表：内置智谱 + 最多 5 个自定义。
class AiProviderManagePage extends ConsumerWidget {
  const AiProviderManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(aiProvidersListProvider);
    final bindingAsync = ref.watch(aiCapabilityBindingProvider);

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: const Text('服务商管理'),
        actions: [
          IconButton(
            tooltip: '添加',
            icon: const Icon(Icons.add),
            onPressed: () => _add(context, ref),
          ),
        ],
      ),
      body: providersAsync.when(
        loading: () => const AppLoading(message: '加载…'),
        error: (e, _) => Center(child: Text('$e')),
        data: (providers) {
          final binding = bindingAsync.valueOrNull;
          return ListView.separated(
            padding: const EdgeInsets.all(PigTokens.spaceLg),
            itemCount: providers.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: PigTokens.spaceMd),
            itemBuilder: (context, i) {
              final p = providers[i];
              return _ProviderCard(
                provider: p,
                binding: binding,
                onTap: () => _edit(context, ref, p),
                onDelete: p.isBuiltIn
                    ? null
                    : () => _delete(context, ref, p),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final store = ref.read(aiProviderStoreProvider);
    if (!await store.canAddCustomProvider()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '自定义服务商最多 ${AiProviderStore.maxCustomProviders} 个',
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AiProviderEditPage(),
      ),
    );
    ref.invalidate(aiProvidersListProvider);
    ref.invalidate(aiMineSubtitleProvider);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AiServiceProvider provider,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiProviderEditPage(provider: provider),
      ),
    );
    ref.invalidate(aiProvidersListProvider);
    ref.invalidate(aiMineSubtitleProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AiServiceProvider provider,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务商'),
        content: Text('确定删除「${provider.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(aiProviderStoreProvider).deleteProvider(provider.id);
      ref.invalidate(aiProvidersListProvider);
      ref.invalidate(aiMineSubtitleProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除')),
      );
    } on AiProviderInUseException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.binding,
    required this.onTap,
    required this.onDelete,
  });

  final AiServiceProvider provider;
  final AiCapabilityBinding? binding;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  /// 已填模型均测连成功才算已连接；未测、失败、无 Key 均为未连通。
  bool get _connected {
    final hasText = provider.supportsText;
    final hasVision = provider.supportsVision;
    if (!provider.isValid || (!hasText && !hasVision)) return false;
    if (hasText && provider.textTestStatus != AiModelTestStatus.success) {
      return false;
    }
    if (hasVision &&
        provider.visionTestStatus != AiModelTestStatus.success) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final used = binding?.isBoundTo(provider.id) ?? false;
    return aiSectionCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  provider.isBuiltIn
                      ? Icons.verified
                      : Icons.cloud_outlined,
                  color: provider.isBuiltIn
                      ? PigTokens.primary
                      : PigTokens.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          provider.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _connectionBadge(),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _trailingAction(),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip('文本', provider.supportsText),
                _chip('视觉', provider.supportsVision),
                if (used)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: PigTokens.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '使用中',
                      style: TextStyle(fontSize: 12, color: PigTokens.primary),
                    ),
                  ),
              ],
            ),
            if (!provider.isValid) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '尚未填写 API Key',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trailingAction() {
    const slotWidth = 44.0;
    const slotHeight = 28.0;
    final Widget? child;
    if (provider.isBuiltIn) {
      child = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: PigTokens.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          '内置',
          style: TextStyle(
            fontSize: 11,
            color: PigTokens.primary,
          ),
        ),
      );
    } else if (onDelete != null) {
      child = IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        color: PigTokens.textTertiary,
        onPressed: onDelete,
        tooltip: '删除',
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(
          width: slotHeight,
          height: slotHeight,
        ),
      );
    } else {
      child = null;
    }
    return SizedBox(
      width: slotWidth,
      height: slotHeight,
      child: child == null ? null : Center(child: child),
    );
  }

  Widget _connectionBadge() {
    final connected = _connected;
    final color = connected ? const Color(0xFF16A34A) : PigTokens.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        connected ? '已连接' : '未连通',
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }

  Widget _chip(String label, bool on) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: on
            ? PigTokens.primary.withValues(alpha: 0.1)
            : PigTokens.scaffoldBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: on ? PigTokens.primary : PigTokens.textTertiary,
        ),
      ),
    );
  }
}
