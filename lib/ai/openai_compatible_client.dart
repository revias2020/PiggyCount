import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../services/system/logger_service.dart';
import 'ai_provider_config.dart';
import 'ai_vision_failure.dart';

/// OpenAI 兼容 Chat Completions（智谱与自定义共用）。
class OpenAiCompatibleClient {
  OpenAiCompatibleClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// 连接测试专用 Client；[cancelTests] 时 close，打断进行中的测连。
  http.Client? _testHttp;
  int _testGeneration = 0;

  static const testTimeout = Duration(seconds: 15);
  static const textTimeout = Duration(seconds: 30);
  static const visionTimeout = Duration(seconds: 60);

  /// 取消进行中的连接测试（改 Key/URL/模型时调用）。
  void cancelTests() {
    _testGeneration++;
    _testHttp?.close();
    _testHttp = null;
  }

  /// 纯文本对话。
  Future<String> chat({
    required AiServiceProvider provider,
    required String userPrompt,
    String? systemPrompt,
    double temperature = 0.3,
    Duration? timeout,
  }) async {
    final messages = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ];
    return _postChat(
      provider: provider,
      model: provider.textModel,
      messages: messages,
      temperature: temperature,
      timeout: timeout ?? textTimeout,
    );
  }

  /// 图片理解：将 [imageBytes] 以 data URL 传入。
  Future<String> vision({
    required AiServiceProvider provider,
    required Uint8List imageBytes,
    required String prompt,
    String mimeType = 'image/jpeg',
    Duration? timeout,
  }) async {
    final b64 = base64Encode(imageBytes);
    final messages = [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': prompt},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$b64'},
          },
        ],
      },
    ];
    return _postChat(
      provider: provider,
      model: provider.visionModel,
      messages: messages,
      temperature: 0.2,
      timeout: timeout ?? visionTimeout,
    );
  }

  /// 测试文本模型（timeout 15s）。
  Future<void> testText(AiServiceProvider provider) async {
    await _runTest((client, gen) async {
      if (!provider.isValid) {
        throw AiClientException('请先填写 API Key');
      }
      if (!provider.supportsText) {
        throw AiClientException('请先填写文本模型');
      }
      final text = await _postChat(
        provider: provider,
        model: provider.textModel,
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
        temperature: 0.3,
        timeout: testTimeout,
        httpClient: client,
      );
      _ensureNotCancelled(gen);
      if (text.trim().isEmpty) {
        throw AiClientException('文本模型返回空响应');
      }
    });
  }

  /// 测试视觉模型（timeout 15s）。
  Future<void> testVision(AiServiceProvider provider) async {
    await _runTest((client, gen) async {
      if (!provider.isValid) {
        throw AiClientException('请先填写 API Key');
      }
      if (!provider.supportsVision) {
        throw AiClientException('请先填写视觉模型');
      }
      final reply = await _postChat(
        provider: provider,
        model: provider.visionModel,
        messages: [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'hi'},
              {
                'type': 'image_url',
                'image_url': {
                  'url':
                      'data:image/jpeg;base64,${base64Encode(_testJpegBytes)}',
                },
              },
            ],
          },
        ],
        temperature: 0.2,
        timeout: testTimeout,
        httpClient: client,
      );
      _ensureNotCancelled(gen);
      if (reply.trim().isEmpty) {
        throw AiClientException('视觉模型返回空响应');
      }
    });
  }

  Future<void> _runTest(
    Future<void> Function(http.Client client, int gen) body,
  ) async {
    final gen = ++_testGeneration;
    final client = http.Client();
    _testHttp?.close();
    _testHttp = client;
    try {
      await body(client, gen);
      _ensureNotCancelled(gen);
    } on AiTestCancelledException {
      rethrow;
    } catch (e) {
      _ensureNotCancelled(gen);
      rethrow;
    } finally {
      if (identical(_testHttp, client)) {
        _testHttp = null;
      }
      client.close();
    }
  }

  void _ensureNotCancelled(int gen) {
    if (gen != _testGeneration) {
      throw AiTestCancelledException();
    }
  }

  /// 最小合法 JPEG（连接测试用）。
  static final List<int> _testJpegBytes = base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAUDBAQEAwUEBAQFBQUGBwwIBwcHBw8LCwkM'
    'EQ8SEhEPERETFhwXExQaFRERGCEYGh0dHx8fExciJCIeJBweHx7/2wBDAQUFBQcGBw4I'
    'CA4eFBEUHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4e'
    'Hh4eHh7/wAARCABAAEADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQF'
    'BgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEI'
    'I0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNk'
    'ZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLD'
    'xMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEB'
    'AQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJB'
    'UQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZH'
    'SElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaan'
    'qKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oA'
    'DAMBAAIRAxEAPwDyyiiivzo/ssKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiig'
    'AooooAKKKKACiiigAooooAKKKKACiiigAooooA//2Q==',
  );

  Future<String> _postChat({
    required AiServiceProvider provider,
    required String model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required Duration timeout,
    http.Client? httpClient,
  }) async {
    if (!provider.isValid) {
      throw AiClientException('未配置 API Key，请先到「我的 → AI 设置」填写');
    }
    final base = provider.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': temperature,
    });
    final client = httpClient ?? _http;
    late final http.Response response;
    try {
      response = await client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${provider.apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);
    } on http.ClientException catch (e) {
      // 测连专用 Client 被 cancelTests close 时常见
      if (httpClient != null &&
          (e.message.contains('closed') ||
              e.message.contains('Client is closed'))) {
        throw AiTestCancelledException();
      }
      logger.error('AI', '网络异常 model=$model', e);
      throw AiTransportException(e.message);
    } on TimeoutException catch (e) {
      logger.error('AI', '请求超时 model=$model', e);
      throw AiTransportException('请求超时');
    }

    // 部分厂商错误体为 UTF-8 但未声明 charset，response.body 会按 Latin-1 乱码。
    final responseText = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg =
          'AI 请求失败(${response.statusCode}): ${_shortBody(responseText)}';
      logger.error('AI', 'HTTP ${response.statusCode} model=$model');
      throw AiClientException(msg);
    }
    late final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(responseText) as Map<String, dynamic>;
    } catch (e) {
      throw AiClientException('AI 响应不是合法 JSON');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw AiClientException('AI 响应无 choices');
    }
    final message = choices.first['message'] as Map<String, dynamic>?;
    final content = message?['content'];
    if (content is String && content.trim().isNotEmpty) return content;
    if (content is List) {
      final buf = StringBuffer();
      for (final part in content) {
        if (part is Map && part['type'] == 'text') {
          buf.write(part['text'] ?? '');
        }
      }
      final text = buf.toString().trim();
      if (text.isNotEmpty) return text;
    }
    throw AiClientException('AI 响应内容为空');
  }

  String _shortBody(String body) {
    final t = sanitizeLogText(body.trim());
    return t.length > 200 ? '${t.substring(0, 200)}…' : t;
  }
}

class AiClientException implements Exception {
  AiClientException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 测连被用户取消（改凭证等）。
class AiTestCancelledException implements Exception {}
