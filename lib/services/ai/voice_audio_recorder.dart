import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../utils/app_permissions.dart';

/// 短录音（Vosk 实时听写除外；Whisper / AI 语音共用）。
class VoiceAudioRecorder {
  VoiceAudioRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;

  Future<void> start() async {
    final mic = await AppPermissions.requestMicrophone();
    if (!mic.granted) {
      throw StateError(mic.message ?? '需要麦克风权限');
    }
    if (!await _recorder.hasPermission()) {
      throw StateError('需要麦克风权限');
    }
    final dir = await getTemporaryDirectory();
    _path = p.join(
      dir.path,
      'piggy_voice_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );
  }

  Future<Uint8List> stop() async {
    final path = await _recorder.stop() ?? _path;
    _path = null;
    if (path == null || path.isEmpty) {
      throw StateError('没有录到声音，请重试');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('没有录到声音，请重试');
    }
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}
    if (bytes.isEmpty) {
      throw StateError('没有录到声音，请重试');
    }
    return bytes;
  }

  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
    final path = _path;
    _path = null;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }
}
