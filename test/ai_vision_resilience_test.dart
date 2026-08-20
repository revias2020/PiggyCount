import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:piggy_count/ai/ai_provider_config.dart';
import 'package:piggy_count/ai/ai_provider_store.dart';
import 'package:piggy_count/ai/ai_vision_failure.dart';
import 'package:piggy_count/ai/openai_compatible_client.dart';

void main() {
  group('isAiTransportFailure', () {
    test('ClientException / TimeoutException / AiTransportException', () {
      expect(isAiTransportFailure(http.ClientException('connection abort')), isTrue);
      expect(isAiTransportFailure(TimeoutException('x')), isTrue);
      expect(isAiTransportFailure(AiTransportException('x')), isTrue);
    });

    test('AiClientException 属于 API 失败', () {
      expect(isAiTransportFailure(AiClientException('401')), isFalse);
    });

    test('测连取消不算传输失败', () {
      expect(isAiTransportFailure(AiTestCancelledException()), isFalse);
    });
  });

  group('orderVisionFallbackProviders', () {
    AiServiceProvider ready(String id, String name) => AiServiceProvider(
          id: id,
          name: name,
          isBuiltIn: false,
          apiKey: 'k',
          baseUrl: 'https://example.com/v1',
          textModel: 't',
          visionModel: 'v',
          createdAt: DateTime(2024),
          visionTestStatus: AiModelTestStatus.success,
        );

    test('主绑定优先，其余保持列表顺序', () {
      final a = ready('a', 'A');
      final b = ready('b', 'B');
      final c = ready('c', 'C');
      final ordered = AiProviderStore.orderVisionFallbackProviders(
        [a, b, c],
        'b',
      );
      expect(ordered.map((p) => p.id).toList(), ['b', 'a', 'c']);
    });

    test('未测通的不纳入', () {
      final readyOne = ready('a', 'A');
      final untested = ready('b', 'B').copyWith(
        visionTestStatus: AiModelTestStatus.untested,
      );
      final ordered = AiProviderStore.orderVisionFallbackProviders(
        [readyOne, untested],
        'b',
      );
      expect(ordered.map((p) => p.id).toList(), ['a']);
    });
  });

  group('AiVisionExhaustedException', () {
    test('通知标题与正文', () {
      final e = AiVisionExhaustedException(
        kind: AiVisionFailureKind.transport,
        message: 'connection abort',
        providersAttempted: 2,
      );
      expect(e.notificationTitle, '网络异常');
      expect(e.notificationBody(), 'connection abort（已尝试 2 个服务商）');
    });
  });
}
