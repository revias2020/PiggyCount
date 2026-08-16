import 'package:speech_to_text/speech_to_text.dart';

import '../../utils/app_permissions.dart';

/// 系统 ASR 封装（不走大模型语音接口）。
///
/// 失败时抛出中文说明，便于 UI 直接 SnackBar。
class SpeechAsrService {
  SpeechAsrService({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _ready = false;

  Future<bool> ensureInitialized() async {
    final mic = await AppPermissions.requestMicrophone();
    if (!mic.granted) {
      throw StateError(mic.message ?? '需要麦克风权限');
    }
    if (!_ready) {
      _ready = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
    }
    if (!_ready) {
      throw StateError('无法使用语音识别，请检查系统语音服务是否可用');
    }
    return true;
  }

  bool get isListening => _speech.isListening;

  /// 开始听写；[onPartial] 持续回调中间结果。
  Future<void> start({
    required void Function(String text) onPartial,
    String localeId = 'zh_CN',
  }) async {
    await ensureInitialized();
    await _speech.listen(
      onResult: (result) => onPartial(result.recognizedWords),
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
  }

  Future<String> stop() async {
    await _speech.stop();
    return _speech.lastRecognizedWords;
  }

  Future<void> cancel() => _speech.cancel();
}
