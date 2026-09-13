import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/ai/ai_provider_config.dart';
import 'package:piggy_count/ai/ai_provider_config_package.dart';

void main() {
  group('AiProviderConfigPackage', () {
    AiProviderConfigPackage validPackage({
      List<AiServiceProvider>? providers,
      AiCapabilityBinding? binding,
    }) {
      final list = providers ??
          [
            AiServiceProvider.zhipuDefault.copyWith(apiKey: 'zk'),
            AiServiceProvider.agnesDefault.copyWith(apiKey: 'ak'),
            AiServiceProvider(
              id: 'provider_custom_1',
              name: 'Custom',
              isBuiltIn: false,
              apiKey: 'ck',
              baseUrl: 'https://example.com/v1',
              textModel: 'm1',
              visionModel: 'm2',
              voiceModel: '',
              createdAt: DateTime(2025, 1, 1),
              textTestStatus: AiModelTestStatus.success,
            ),
          ];
      return AiProviderConfigPackage(
        version: AiProviderConfigPackage.currentVersion,
        providers: list,
        binding: binding ??
            const AiCapabilityBinding(
              textProviderId: 'provider_custom_1',
              visionProviderId: AiServiceProvider.zhipuId,
              voiceProviderId: AiServiceProvider.zhipuId,
            ),
      );
    }

    test('round-trip encode/parse keeps key models and binding', () {
      final pkg = validPackage();
      final again = AiProviderConfigPackage.parse(pkg.encode());
      expect(again.version, 1);
      expect(again.providers.length, 3);
      expect(again.providers[2].apiKey, 'ck');
      expect(again.providers[2].textModel, 'm1');
      expect(again.providers[2].textTestStatus, AiModelTestStatus.success);
      expect(again.binding.textProviderId, 'provider_custom_1');
    });

    test('rejects unknown version', () {
      final raw = validPackage().encode().replaceFirst(
            '"version": 1',
            '"version": 99',
          );
      expect(
        () => AiProviderConfigPackage.parse(raw),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects binding to missing provider', () {
      final pkg = validPackage(
        binding: const AiCapabilityBinding(
          textProviderId: 'missing_id',
          visionProviderId: AiServiceProvider.zhipuId,
          voiceProviderId: AiServiceProvider.zhipuId,
        ),
      );
      expect(
        () => AiProviderConfigPackage.parse(pkg.encode()),
        throwsA(isA<FormatException>()),
      );
    });

    test('strips forged isBuiltIn on custom id', () {
      final forged = AiServiceProvider(
        id: 'provider_fake',
        name: 'Fake',
        isBuiltIn: true,
        apiKey: 'x',
        baseUrl: 'https://example.com/v1',
        textModel: 't',
        visionModel: 'v',
        voiceModel: '',
        createdAt: DateTime(2025, 1, 1),
      );
      final pkg = validPackage(
        providers: [
          AiServiceProvider.zhipuDefault,
          AiServiceProvider.agnesDefault,
          forged,
        ],
        binding: const AiCapabilityBinding(
          textProviderId: 'provider_fake',
          visionProviderId: AiServiceProvider.zhipuId,
          voiceProviderId: AiServiceProvider.zhipuId,
        ),
      );
      final parsed = AiProviderConfigPackage.parse(pkg.encode());
      expect(parsed.providers.last.isBuiltIn, isFalse);
    });

    test('rejects more than 5 customs', () {
      final customs = List.generate(
        6,
        (i) => AiServiceProvider(
          id: 'provider_c_$i',
          name: 'C$i',
          isBuiltIn: false,
          apiKey: 'k',
          baseUrl: 'https://example.com/v1',
          textModel: 't',
          visionModel: 'v',
          voiceModel: '',
          createdAt: DateTime(2025, 1, 1),
        ),
      );
      final pkg = validPackage(
        providers: [
          AiServiceProvider.zhipuDefault,
          AiServiceProvider.agnesDefault,
          ...customs,
        ],
        binding: const AiCapabilityBinding(
          textProviderId: AiServiceProvider.zhipuId,
          visionProviderId: AiServiceProvider.zhipuId,
          voiceProviderId: AiServiceProvider.zhipuId,
        ),
      );
      expect(
        () => AiProviderConfigPackage.parse(pkg.encode()),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
