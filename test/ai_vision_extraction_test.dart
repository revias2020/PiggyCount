import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/ai/ai_provider_config.dart';
import 'package:piggy_count/ai/ai_provider_store.dart';
import 'package:piggy_count/ai/ai_vision_failure.dart';
import 'package:piggy_count/ai/ai_vision_failure.dart';
import 'package:piggy_count/ai/extraction_context.dart';
import 'package:piggy_count/ai/extraction_engine.dart';
import 'package:piggy_count/ai/openai_compatible_client.dart';

class _FakeVisionStore extends AiProviderStore {
  _FakeVisionStore(this._providers);

  final List<AiServiceProvider> _providers;

  @override
  Future<List<AiServiceProvider>> listVisionFallbackProviders() async =>
      _providers;
}

class _FakeVisionClient extends OpenAiCompatibleClient {
  _FakeVisionClient(this._handlers) : super(httpClient: null);

  final List<Future<String> Function()> _handlers;
  var _index = 0;

  @override
  Future<String> vision({
    required AiServiceProvider provider,
    required Uint8List imageBytes,
    required String prompt,
    String mimeType = 'image/jpeg',
    Duration? timeout,
  }) async {
    if (_index >= _handlers.length) {
      throw StateError('no handler');
    }
    final handler = _handlers[_index++];
    return handler();
  }
}

AiServiceProvider _provider(String id) => AiServiceProvider(
      id: id,
      name: id,
      isBuiltIn: false,
      apiKey: 'k',
      baseUrl: 'https://example.com/v1',
      textModel: 't',
      visionModel: 'v',
      voiceModel: '',
      createdAt: DateTime(2024),
      visionTestStatus: AiModelTestStatus.success,
    );

const _ctx = AiExtractionContext.fallback;

void main() {
  test('传输失败重试后换下一个服务商', () async {
    final engine = AiExtractionEngine(
      providerStore: _FakeVisionStore([_provider('a'), _provider('b')]),
      client: _FakeVisionClient([
        () => throw AiTransportException('abort'),
        () => throw AiTransportException('abort again'),
        () async =>
            '[{"amount":12,"type":"expense","time":"2026-08-20T00:00:00"}]',
      ]),
    );

    final bills = await engine.extractFromImageWithFallback(
      imageBytes: Uint8List.fromList([1, 2, 3]),
      context: _ctx,
    );
    expect(bills.length, 1);
    expect(bills.first.amount, 12);
  });

  test('全部耗尽时按最后失败根因抛 AiVisionExhaustedException', () async {
    final engine = AiExtractionEngine(
      providerStore: _FakeVisionStore([_provider('a')]),
      client: _FakeVisionClient([
        () => throw AiTransportException('abort'),
        () => throw AiTransportException('abort again'),
      ]),
    );

    expect(
      () => engine.extractFromImageWithFallback(
        imageBytes: Uint8List.fromList([1]),
        context: _ctx,
      ),
      throwsA(
        isA<AiVisionExhaustedException>().having(
          (e) => e.kind,
          'kind',
          AiVisionFailureKind.transport,
        ),
      ),
    );
  });

  test('API 失败不重试，直接换下一个服务商', () async {
    final engine = AiExtractionEngine(
      providerStore: _FakeVisionStore([_provider('a'), _provider('b')]),
      client: _FakeVisionClient([
        () => throw AiClientException('401'),
        () async =>
            '[{"amount":8,"type":"expense","time":"2026-08-20T00:00:00"}]',
      ]),
    );

    final bills = await engine.extractFromImageWithFallback(
      imageBytes: Uint8List.fromList([1]),
      context: _ctx,
    );
    expect(bills.single.amount, 8);
  });

  test('前台路径每服务商仅 1 次，失败立即切换', () async {
    final switches = <AiVisionSwitchEvent>[];
    final engine = AiExtractionEngine(
      providerStore: _FakeVisionStore([_provider('a'), _provider('b')]),
      client: _FakeVisionClient([
        () => throw AiTransportException('abort'),
        () async =>
            '[{"amount":5,"type":"expense","time":"2026-08-20T00:00:00"}]',
      ]),
    );

    final bills = await engine.extractFromImage(
      imageBytes: Uint8List.fromList([1]),
      context: _ctx,
      onSwitch: switches.add,
    );
    expect(bills.single.amount, 5);
    expect(switches.length, 1);
    expect(switches.single.nextProviderName, 'b');
    expect(switches.single.failureMessage, 'abort');
  });
}
