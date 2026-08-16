import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/bill_info.dart';
import '../../providers/ai_providers.dart';
import '../../providers/ledger_session_provider.dart';
import '../../styles/tokens.dart';
import '../../widgets/ai/bill_confirm_card.dart';
import '../ai/ai_settings_page.dart';

/// 语音记账确认流：系统 ASR → AI 结构化 → 用户确认落库。
Future<void> showVoiceBillingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PigTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _VoiceBillingSheet(),
  );
}

class _VoiceBillingSheet extends ConsumerStatefulWidget {
  const _VoiceBillingSheet();

  @override
  ConsumerState<_VoiceBillingSheet> createState() => _VoiceBillingSheetState();
}

class _VoiceBillingSheetState extends ConsumerState<_VoiceBillingSheet> {
  String _transcript = '';
  bool _listening = false;
  bool _extracting = false;
  List<BillInfo> _bills = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListen());
  }

  @override
  void dispose() {
    // 尽量停掉识别，避免离开后仍占麦；失败忽略。
    try {
      ref.read(speechAsrServiceProvider).cancel();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _startListen() async {
    final cfg = await ref.read(aiConfigStoreProvider).load();
    if (!cfg.isConfigured) {
      setState(() {
        _error = '请先配置 AI API Key';
      });
      return;
    }
    try {
      setState(() {
        _listening = true;
        _error = null;
      });
      await ref.read(speechAsrServiceProvider).start(
            onPartial: (t) {
              if (!mounted) return;
              setState(() => _transcript = t);
            },
          );
    } catch (e) {
      setState(() {
        _listening = false;
        _error = '$e';
      });
    }
  }

  Future<void> _stopAndExtract() async {
    final text = (await ref.read(speechAsrServiceProvider).stop()).trim();
    setState(() {
      _listening = false;
      _transcript = text.isEmpty ? _transcript : text;
      _extracting = true;
    });
    if (_transcript.trim().isEmpty) {
      setState(() {
        _extracting = false;
        _error = '没有听清内容，请重试';
      });
      return;
    }
    try {
      final bills =
          await ref.read(aiBookkeeperProvider).fromText(_transcript.trim());
      setState(() {
        _extracting = false;
        _bills = bills;
        if (bills.isEmpty) {
          _error = '未能识别为账单，请再说一次金额与用途';
        }
      });
    } catch (e) {
      setState(() {
        _extracting = false;
        _error = '识别失败：$e';
      });
    }
  }

  Future<void> _confirm(BillInfo bill) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    if (ledgerId == null) return;
    await ref.read(aiBookkeeperProvider).saveBills(
          bills: [bill],
          ledgerId: ledgerId,
          source: 'voice',
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('语音记账已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: PigTokens.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '语音记账',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _listening
                ? '正在聆听，说完后点「识别」'
                : (_extracting ? '正在结构化…' : '识别结果确认后才会入账'),
            style: const TextStyle(color: PigTokens.textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 64),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PigTokens.surfaceInput,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _transcript.isEmpty ? '例如：午餐花了三十五块' : _transcript,
              style: TextStyle(
                color: _transcript.isEmpty
                    ? PigTokens.textTertiary
                    : PigTokens.textPrimary,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: PigTokens.danger)),
            if (_error!.contains('API Key'))
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AiSettingsPage(),
                    ),
                  );
                },
                child: const Text('去配置'),
              ),
          ],
          for (final b in _bills)
            BillConfirmCard(
              bill: b,
              onConfirm: () => _confirm(b),
              onDiscard: () => setState(() {
                _bills = _bills.where((x) => x != b).toList();
              }),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
              const Spacer(),
              if (_listening)
                FilledButton(
                  onPressed: _extracting ? null : _stopAndExtract,
                  child: const Text('识别'),
                )
              else if (_bills.isEmpty)
                FilledButton(
                  onPressed: _extracting ? null : _startListen,
                  child: const Text('重新说'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
