import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../ai/ai_provider_store.dart';
import '../../ai/ai_provider_config.dart';
import '../platform/voice_audio_session.dart';
import '../system/logger_service.dart';
import 'offline_asr_model_store.dart';
import 'speech_asr_service.dart';
import 'speech_engine_preference.dart';
import 'voice_audio_recorder.dart';

/// 一次「听 → 识别」的结果。
class VoiceListenOutcome {
  const VoiceListenOutcome.dictation(this.transcript)
      : audioBytes = null,
        isDirectBilling = false;

  const VoiceListenOutcome.directBilling(this.audioBytes)
      : transcript = null,
        isDirectBilling = true;

  final String? transcript;
  final Uint8List? audioBytes;
  final bool isDirectBilling;
}

/// 多引擎语音会话（ADR-052）：共用听/停交互，底层按引擎分流。
class VoiceRecognitionSession {
  VoiceRecognitionSession({
    required this.preferenceStore,
    required this.offlineStore,
    required this.aiStore,
    SpeechAsrService? systemAsr,
    VoiceAudioRecorder? recorder,
  })  : _systemAsr = systemAsr ?? SpeechAsrService(),
        _recorder = recorder ?? VoiceAudioRecorder();

  final SpeechEnginePreferenceStore preferenceStore;
  final OfflineAsrModelStore offlineStore;
  final AiProviderStore aiStore;
  final SpeechAsrService _systemAsr;
  final VoiceAudioRecorder _recorder;

  SpeechRecognitionEngineKind? _active;
  SpeechService? _voskSpeech;
  Recognizer? _voskRecognizer;
  Model? _voskModel;
  String _lastPartial = '';
  final List<StreamSubscription<dynamic>> _voskSubs = [];

  Future<bool> isSystemAvailable() async {
    try {
      final stt = SpeechToText();
      return await stt.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (e) {
      logger.warning('VoiceSession', '系统 ASR 不可用: $e');
      return false;
    }
  }

  Future<void> start({
    required SpeechRecognitionEngineKind engine,
    required void Function(String partial) onPartial,
  }) async {
    // 「重新说」走 cancel 但不还原音频（ADR-060）。
    await cancel(restoreAudio: false);
    _active = engine;
    _lastPartial = '';
    await VoiceAudioSession.begin();
    switch (engine) {
      case SpeechRecognitionEngineKind.system:
        await _systemAsr.start(onPartial: (t) {
          _lastPartial = t;
          onPartial(t);
        });
      case SpeechRecognitionEngineKind.vosk:
        await _startVosk(onPartial);
      case SpeechRecognitionEngineKind.whisper:
      case SpeechRecognitionEngineKind.aiVoice:
        onPartial('正在聆听…');
        await _recorder.start();
    }
    await VoiceAudioSession.captureLeft();
  }

  Future<VoiceListenOutcome> stop() async {
    final engine = _active;
    _active = null;
    if (engine == null) {
      throw StateError('未在聆听');
    }
    switch (engine) {
      case SpeechRecognitionEngineKind.system:
        final text = (await _systemAsr.stop()).trim();
        return VoiceListenOutcome.dictation(
          text.isEmpty ? _lastPartial.trim() : text,
        );
      case SpeechRecognitionEngineKind.vosk:
        final text = await _stopVosk();
        return VoiceListenOutcome.dictation(
          text.isEmpty ? _lastPartial.trim() : text,
        );
      case SpeechRecognitionEngineKind.whisper:
        final bytes = await _recorder.stop();
        final text = await _transcribeWhisper(bytes);
        return VoiceListenOutcome.dictation(text);
      case SpeechRecognitionEngineKind.aiVoice:
        final bytes = await _recorder.stop();
        return VoiceListenOutcome.directBilling(bytes);
    }
  }

  /// [restoreAudio]：仅弹层结束时为 true；「重新说」必须为 false（ADR-060）。
  Future<void> cancel({bool restoreAudio = false}) async {
    try {
      await _systemAsr.cancel();
    } catch (_) {}
    try {
      await _recorder.cancel();
    } catch (_) {}
    await _disposeVosk();
    _active = null;
    _lastPartial = '';
    if (restoreAudio) {
      await VoiceAudioSession.restoreIfNeeded();
    }
  }

  Future<void> _startVosk(void Function(String partial) onPartial) async {
    final path = await offlineStore.localPath(OfflineAsrModelCatalog.vosk);
    if (path == null) {
      throw StateError('请先下载 Vosk 中文小包（我的 → AI 设置 → 语音识别）');
    }
    final vosk = VoskFlutterPlugin.instance();
    _voskModel = await vosk.createModel(path);
    _voskRecognizer = await vosk.createRecognizer(
      model: _voskModel!,
      sampleRate: 16000,
    );
    _voskSpeech = await vosk.initSpeechService(_voskRecognizer!);
    void push(String raw) {
      final text = _parseVoskText(raw);
      if (text.isEmpty) return;
      _lastPartial = text;
      onPartial(text);
    }

    _voskSubs.add(_voskSpeech!.onPartial().listen(push));
    _voskSubs.add(_voskSpeech!.onResult().listen(push));
    await _voskSpeech!.start();
  }

  Future<String> _stopVosk() async {
    final speech = _voskSpeech;
    if (speech == null) return _lastPartial;
    await speech.stop();
    final kept = _lastPartial;
    await _disposeVosk();
    return kept.trim();
  }

  Future<void> _disposeVosk() async {
    for (final s in _voskSubs) {
      await s.cancel();
    }
    _voskSubs.clear();
    try {
      await _voskSpeech?.dispose();
    } catch (_) {}
    _voskSpeech = null;
    try {
      await _voskRecognizer?.dispose();
    } catch (_) {}
    _voskRecognizer = null;
    try {
      _voskModel?.dispose();
    } catch (_) {}
    _voskModel = null;
  }

  String _parseVoskText(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final partial = map['partial'] as String?;
      if (partial != null && partial.trim().isNotEmpty) return partial.trim();
      final text = map['text'] as String?;
      if (text != null) return text.trim();
    } catch (_) {
      return raw.trim();
    }
    return '';
  }

  Future<String> _transcribeWhisper(Uint8List wavBytes) async {
    final modelPath =
        await offlineStore.localPath(OfflineAsrModelCatalog.whisper);
    if (modelPath == null) {
      throw StateError('请先下载 Whisper base（我的 → AI 设置 → 语音识别）');
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(dir.path, 'piggy_whisper_${DateTime.now().millisecondsSinceEpoch}.wav'),
    );
    await file.writeAsBytes(wavBytes, flush: true);
    try {
      final whisper = Whisper(model: WhisperModel.base);
      final res = await whisper.transcribe(
        modelPath: modelPath,
        transcribeRequest: TranscribeRequest(
          audio: file.path,
          language: 'zh',
          isNoTimestamps: true,
          suppressNonSpeechTokens: true,
        ),
      );
      return res.text.trim();
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// 将系统 ASR 原始异常转成可读中文。
  static String friendlyError(Object error) {
    if (error is PlatformException) {
      if (error.code == 'recognizerNotAvailable') {
        return '本机系统语音识别不可用，请在 AI 设置中改用离线模型或 AI 语音模型';
      }
      return error.message?.isNotEmpty == true
          ? error.message!
          : '语音识别失败（${error.code}）';
    }
    return '$error';
  }
}

/// 引擎是否可选（设置页 / 打开语音前）。
class SpeechEngineReadiness {
  SpeechEngineReadiness({
    required this.offlineStore,
    required this.aiStore,
  });

  final OfflineAsrModelStore offlineStore;
  final AiProviderStore aiStore;

  Future<bool> isSelectable(
    SpeechRecognitionEngineKind kind, {
    required bool systemAvailable,
  }) async {
    switch (kind) {
      case SpeechRecognitionEngineKind.system:
        return systemAvailable;
      case SpeechRecognitionEngineKind.vosk:
        return offlineStore.isReady(OfflineAsrModelCatalog.vosk);
      case SpeechRecognitionEngineKind.whisper:
        return offlineStore.isReady(OfflineAsrModelCatalog.whisper);
      case SpeechRecognitionEngineKind.aiVoice:
        try {
          await aiStore.resolve(AiCapabilityKind.voice);
          return true;
        } on AiCapabilityNotReadyException {
          return false;
        }
    }
  }
}
