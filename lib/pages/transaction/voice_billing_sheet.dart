import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_provider_config.dart';
import '../../ai/bill_info.dart';
import '../../providers/ai_providers.dart';
import '../../providers/ledger_session_provider.dart';
import '../../services/ai/speech_engine_preference.dart';
import '../../services/ai/voice_recognition_session.dart';
import '../../services/system/logger_service.dart';
import '../../styles/tokens.dart';
import '../../widgets/ai/ai_setup_helpers.dart';
import '../../widgets/ai/bill_confirm_card.dart';
import '../ai/ai_settings_page.dart';

/// 语音记账确认流：多引擎听写/直接记账 → 用户确认落库（ADR-052）。
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
  SpeechRecognitionEngineKind? _engine;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    try {
      ref.read(voiceRecognitionSessionProvider).cancel();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final session = ref.read(voiceRecognitionSessionProvider);
    final prefStore = ref.read(speechEnginePreferenceStoreProvider);
    var engine = await prefStore.load();
    final systemOk = await session.isSystemAvailable();

    if (engine == SpeechRecognitionEngineKind.system && !systemOk) {
      if (!mounted) return;
      setState(() {
        _error = '本机系统语音识别不可用，请改用离线模型或 AI 语音模型';
      });
      final switched = await _promptPickEngine(systemOk: systemOk);
      if (switched == null) return;
      await prefStore.save(switched);
      ref.invalidate(speechEngineKindProvider);
      engine = switched;
    }

    _engine = engine;
    await _startListen();
  }

  Future<SpeechRecognitionEngineKind?> _promptPickEngine({
    required bool systemOk,
  }) async {
    final offline = ref.read(offlineAsrModelStoreProvider);
    final readiness = SpeechEngineReadiness(
      offlineStore: offline,
      aiStore: ref.read(aiProviderStoreProvider),
    );
    final options = <SpeechRecognitionEngineKind>[];
    for (final k in SpeechRecognitionEngineKind.values) {
      if (await readiness.isSelectable(k, systemAvailable: systemOk)) {
        options.add(k);
      }
    }
    if (!mounted) return null;
    if (options.isEmpty) {
      setState(() {
        _error = '暂无可用的语音识别引擎，请到 AI 设置下载离线模型或配置语音能力';
      });
      return null;
    }
    return showModalBottomSheet<SpeechRecognitionEngineKind>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择语音识别引擎',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            for (final k in options)
              ListTile(
                title: Text(k.label),
                onTap: () => Navigator.pop(ctx, k),
              ),
            ListTile(
              title: const Text('去 AI 设置'),
              leading: const Icon(Icons.settings_outlined),
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiSettingsPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _startListen() async {
    final engine = _engine;
    if (engine == null) return;

    if (engine == SpeechRecognitionEngineKind.aiVoice) {
      try {
        await ref.read(aiProviderStoreProvider).resolve(AiCapabilityKind.voice);
      } on AiCapabilityNotReadyException catch (e) {
        setState(() => _error = e.message);
        return;
      }
    } else if (engine.isDictation) {
      try {
        await ref.read(aiProviderStoreProvider).resolve(AiCapabilityKind.text);
      } on AiCapabilityNotReadyException catch (e) {
        setState(() => _error = e.message);
        return;
      }
    }

    try {
      setState(() {
        _listening = true;
        _error = null;
        _bills = const [];
        _transcript = '';
      });
      await ref.read(voiceRecognitionSessionProvider).start(
            engine: engine,
            onPartial: (t) {
              if (!mounted) return;
              setState(() => _transcript = t);
            },
          );
    } catch (e, st) {
      logger.error('VoiceBilling', '启动失败', e, st);
      setState(() {
        _listening = false;
        _error = VoiceRecognitionSession.friendlyError(e);
      });
    }
  }

  Future<void> _stopAndExtract() async {
    setState(() {
      _listening = false;
      _extracting = true;
    });
    try {
      final outcome = await ref.read(voiceRecognitionSessionProvider).stop();
      if (outcome.isDirectBilling) {
        final bytes = outcome.audioBytes;
        if (bytes == null || bytes.isEmpty) {
          setState(() {
            _extracting = false;
            _error = '没有录到声音，请重试';
          });
          return;
        }
        final bills =
            await ref.read(aiBookkeeperProvider).fromVoice(bytes);
        setState(() {
          _extracting = false;
          _bills = bills;
          if (bills.isEmpty) {
            _error = '未能识别为账单，请再说一次金额与用途';
          }
        });
        return;
      }

      final text = (outcome.transcript ?? _transcript).trim();
      setState(() => _transcript = text);
      if (text.isEmpty || text == '正在聆听…') {
        setState(() {
          _extracting = false;
          _error = '没有听清内容，请重试';
        });
        return;
      }
      final bills = await ref.read(aiBookkeeperProvider).fromText(text);
      setState(() {
        _extracting = false;
        _bills = bills;
        if (bills.isEmpty) {
          _error = '未能识别为账单，请再说一次金额与用途';
        }
      });
    } catch (e, st) {
      logger.error('VoiceBilling', '识别失败', e, st);
      setState(() {
        _extracting = false;
        _error = VoiceRecognitionSession.friendlyError(e);
      });
    }
  }

  Future<void> _confirm(BillInfo bill) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    if (ledgerId == null) return;
    final result = await ref.read(aiBookkeeperProvider).saveBills(
          bills: [bill],
          ledgerId: ledgerId,
          source: 'voice',
        );
    if (!mounted) return;
    if (result.ids.isEmpty) {
      final msg = result.skipped > 0
          ? '已存在相同账本、金额与时间的账单'
          : '保存失败';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('语音记账已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final engineLabel = _engine?.label;
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
          if (engineLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              '引擎：$engineLabel',
              style: const TextStyle(fontSize: 12, color: PigTokens.textTertiary),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _listening
                ? '正在聆听，说完后点「识别」'
                : (_extracting ? '正在识别…' : '识别结果确认后才会入账'),
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
            ?aiSetupTextButton(context, _error),
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
