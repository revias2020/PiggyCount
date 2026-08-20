import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'openai_compatible_client.dart';

/// Vision 请求失败根因（后台直存结果通知标题依据）。
enum AiVisionFailureKind {
  /// 断连、超时等传输问题 → 「网络异常」
  transport,

  /// HTTP / 解析等 API 问题 → 「识别失败」
  api,
}

/// 全部视觉服务商尝试耗尽。
class AiVisionExhaustedException implements Exception {
  AiVisionExhaustedException({
    required this.kind,
    required this.message,
    required this.providersAttempted,
  });

  final AiVisionFailureKind kind;
  final String message;
  final int providersAttempted;

  String get notificationTitle => switch (kind) {
        AiVisionFailureKind.transport => '网络异常',
        AiVisionFailureKind.api => '识别失败',
      };

  String notificationBody() =>
      '$message（已尝试 $providersAttempted 个服务商）';

  @override
  String toString() => notificationBody();
}

/// 是否属于传输层失败（可 3s 后重试同服务商）。
bool isAiTransportFailure(Object error) {
  if (error is AiTestCancelledException) return false;
  if (error is TimeoutException) return true;
  if (error is SocketException) return true;
  if (error is http.ClientException) return true;
  if (error is AiTransportException) return true;
  return false;
}

String aiVisionErrorMessage(Object error) {
  if (error is AiClientException) return error.message;
  if (error is AiTransportException) return error.message;
  if (error is AiVisionExhaustedException) return error.message;
  return '$error';
}

/// 传输层 Vision 失败（区别于 [AiClientException]）。
class AiTransportException implements Exception {
  AiTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}
