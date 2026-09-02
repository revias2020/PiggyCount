import 'dart:io';

import 'package:flutter/services.dart';

import '../system/logger_service.dart';

/// Android 语音记账音频模式条件还原（ADR-060）。其它平台 no-op。
class VoiceAudioSession {
  VoiceAudioSession._();

  static const _channel = MethodChannel('com.xiaozhu.piggy_count/voice_audio');

  /// 开麦前快照当前 [AudioManager] mode。
  static Future<void> begin() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('begin');
    } catch (e) {
      logger.warning('VoiceAudio', 'begin failed: $e');
    }
  }

  /// 开麦后记下我们留下的 mode（可与原生短延迟补采并用）。
  static Future<void> captureLeft() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('captureLeft');
    } catch (e) {
      logger.warning('VoiceAudio', 'captureLeft failed: $e');
    }
  }

  /// 弹层结束时条件还原；「重新说」勿调用。
  static Future<void> restoreIfNeeded() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('restoreIfNeeded');
    } catch (e) {
      logger.warning('VoiceAudio', 'restoreIfNeeded failed: $e');
    }
  }
}
