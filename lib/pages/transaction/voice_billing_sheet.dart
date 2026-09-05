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
import '../../widgets/pig_toast.dart';

/// 语音记账确认流：多引擎听写/直接记账 → 用户确认落库（ADR-052 / ADR-067）。
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
  static const _disabledMessage = '该功能未启用，请到 AI 设置中选择语音识别引擎';

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
      // 弹层结束：停麦并条件还原 Android 音频模式（ADR-060）。
      ref.read(voiceRecognitionSessionProvider).cancel(restoreAudio: true);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _startListen();
  }

  Future<void> _startListen() async {
    final engine =
        await ref.read(speechEnginePreferenceStoreProvider).load();
    if (!mounted) return;
    setState(() => _engine = engine);

    if (engine == SpeechRecognitionEngineKind.disabled) {
      setState(() {
        _listening = false;
        _error = _disabledMessage;
      });
      return;
    }

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
      PigToast.show(context, msg);
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    Navigator.of(context).pop();
    PigToast.showOn(overlay, '语音记账已保存');
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final engineLabel = _engine?.label;
    final disabled = _engine == SpeechRecognitionEngineKind.disabled;
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  '语音记账',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                tooltip: '关闭',
                visualDensity: VisualDensity.compact,
              ),
            ],
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
            disabled
                ? '请先在 AI 设置中启用语音识别'
                : (_listening
                    ? '正在聆听，说完后点「识别」'
                    : (_extracting ? '正在识别…' : '识别结果确认后才会入账')),
            style: const TextStyle(color: PigTokens.textSecondary),
          ),
          if (!disabled) ...[
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
          ],
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
          if (_listening || _bills.isEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: _extracting ? null : _startListen,
                  child: Text(disabled ? '重试' : '重新说'),
                ),
                const Spacer(),
                if (_listening)
                  FilledButton(
                    onPressed: _extracting ? null : _stopAndExtract,
                    child: const Text('识别'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
