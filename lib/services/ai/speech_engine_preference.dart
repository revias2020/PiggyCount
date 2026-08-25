import 'package:shared_preferences/shared_preferences.dart';

/// 语音识别引擎选择（ADR-052）。
enum SpeechRecognitionEngineKind {
  system,
  vosk,
  whisper,
  aiVoice,
}

extension SpeechRecognitionEngineKindCodec on SpeechRecognitionEngineKind {
  String get wire => switch (this) {
        SpeechRecognitionEngineKind.system => 'system',
        SpeechRecognitionEngineKind.vosk => 'vosk',
        SpeechRecognitionEngineKind.whisper => 'whisper',
        SpeechRecognitionEngineKind.aiVoice => 'ai_voice',
      };

  String get label => switch (this) {
        SpeechRecognitionEngineKind.system => '系统 ASR',
        SpeechRecognitionEngineKind.vosk => 'Vosk（离线）',
        SpeechRecognitionEngineKind.whisper => 'Whisper（离线）',
        SpeechRecognitionEngineKind.aiVoice => 'AI 语音模型',
      };

  /// 是否只做听写（再走文本结构化）。
  bool get isDictation => this != SpeechRecognitionEngineKind.aiVoice;

  static SpeechRecognitionEngineKind parse(String? raw) {
    return switch (raw) {
      'vosk' => SpeechRecognitionEngineKind.vosk,
      'whisper' => SpeechRecognitionEngineKind.whisper,
      'ai_voice' => SpeechRecognitionEngineKind.aiVoice,
      _ => SpeechRecognitionEngineKind.system,
    };
  }
}

/// 持久化当前语音识别引擎偏好。
class SpeechEnginePreferenceStore {
  static const prefsKey = 'speech_recognition_engine_v1';

  Future<SpeechRecognitionEngineKind> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SpeechRecognitionEngineKindCodec.parse(prefs.getString(prefsKey));
  }

  Future<void> save(SpeechRecognitionEngineKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, kind.wire);
  }
}
