import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_config.dart';

/// OpenAI 兼容 Chat Completions（智谱与自定义共用）。
class OpenAiCompatibleClient {
  OpenAiCompatibleClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// 纯文本对话。
  Future<String> chat({
    required AiConfig config,
    required String userPrompt,
    String? systemPrompt,
    double temperature = 0.3,
  }) async {
    final messages = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ];
    return _postChat(
      config: config,
      model: config.textModel,
      messages: messages,
      temperature: temperature,
    );
  }

  /// 图片理解：将 [imageBytes] 以 data URL 传入。
  Future<String> vision({
    required AiConfig config,
    required Uint8List imageBytes,
    required String prompt,
    String mimeType = 'image/jpeg',
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
      config: config,
      model: config.visionModel,
      messages: messages,
      temperature: 0.2,
    );
  }

  /// 连接测试：先文本短 chat，通过后再测视觉；任一项失败标明阶段。
  Future<void> testConnection(AiConfig config) async {
    if (!config.isConfigured) {
      throw AiClientException('请先填写 API Key');
    }
    try {
      final text = await chat(config: config, userPrompt: 'hi');
      if (text.trim().isEmpty) {
        throw AiClientException('文本模型返回空响应');
      }
    } on AiClientException catch (e) {
      throw AiClientException('文本模型：${e.message}');
    } catch (e) {
      throw AiClientException('文本模型：$e');
    }

    try {
      final visionReply = await vision(
        config: config,
        imageBytes: Uint8List.fromList(_testJpegBytes),
        prompt: 'hi',
      );
      if (visionReply.trim().isEmpty) {
        throw AiClientException('视觉模型返回空响应');
      }
    } on AiClientException catch (e) {
      throw AiClientException('视觉模型：${e.message}');
    } catch (e) {
      throw AiClientException('视觉模型：$e');
    }
  }

  /// 最小合法 JPEG（连接测试用，64×64）。
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
    required AiConfig config,
    required String model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
  }) async {
    if (!config.isConfigured) {
      throw AiClientException('未配置 API Key，请先到「我的 → AI 模型配置」填写');
    }
    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': temperature,
    });
    final response = await _http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer ${config.apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiClientException(
        'AI 请求失败(${response.statusCode}): ${_shortBody(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw AiClientException('AI 响应无 choices');
    }
    final message = choices.first['message'] as Map<String, dynamic>?;
    final content = message?['content'];
    if (content is String && content.trim().isNotEmpty) return content;
    // 部分兼容实现把 content 做成多段
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
    final t = body.trim();
    return t.length > 200 ? '${t.substring(0, 200)}…' : t;
  }
}

class AiClientException implements Exception {
  AiClientException(this.message);
  final String message;

  @override
  String toString() => message;
}
