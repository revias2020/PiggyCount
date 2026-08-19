import 'dart:convert';

import '../../ai/ai_provider_config.dart';
import '../../ai/ai_provider_store.dart';
import '../../ai/openai_compatible_client.dart';
import '../../data/app_database.dart';
import '../../data/repositories/tag_repository.dart';
import 'csv_import_mapping.dart';
import 'csv_table.dart';

/// 用文本对话模型预填列名 / 分类 / 标签映射。失败抛给调用方提示。
class CsvAiMappingService {
  CsvAiMappingService({
    AiProviderStore? store,
    OpenAiCompatibleClient? client,
  })  : _store = store ?? AiProviderStore(),
        _client = client ?? OpenAiCompatibleClient();

  final AiProviderStore _store;
  final OpenAiCompatibleClient _client;

  static const _timeout = Duration(seconds: 60);

  Future<ColumnMapping> suggestColumns({
    required CsvTable table,
    required ColumnMapping current,
  }) async {
    final sample = table.rows.take(CsvImportMapping.previewLimit).map((row) {
      final map = <String, String>{};
      for (var i = 0; i < table.headers.length; i++) {
        map[table.headers[i]] = table.cell(row, i);
      }
      return map;
    }).toList();

    final prompt = '''
你是记账 CSV 导入助手。把 CSV 表头映射到目标字段。
目标字段（值为 CSV 表头原文，无法对应则省略该键）：
日期时间、类型、金额、主分类、子分类、标签、备注、账本名

CSV 表头：${jsonEncode(table.headers)}
样例行：${jsonEncode(sample)}

只返回一个 JSON 对象，例如：
{"日期时间":"交易时间","类型":"收/支","金额":"金额","主分类":"分类"}
''';
    final raw = await _chat(prompt);
    final json = _asObject(raw);
    final next = current.copy();
    const labels = {
      '日期时间': CsvImportField.happenedAt,
      '类型': CsvImportField.type,
      '金额': CsvImportField.amount,
      '主分类': CsvImportField.primaryCategory,
      '子分类': CsvImportField.secondaryCategory,
      '标签': CsvImportField.tags,
      '备注': CsvImportField.note,
      '账本名': CsvImportField.ledgerName,
    };
    final headerSet = {for (final h in table.headers) h.trim()};
    json.forEach((key, value) {
      final field = labels[key.toString().trim()];
      if (field == null) return;
      final header = value?.toString().trim() ?? '';
      if (header.isEmpty) return;
      if (headerSet.contains(header) || table.headers.contains(header)) {
        next[field] = header;
      }
    });
    return next;
  }

  Future<Map<CategoryMapKey, int?>> suggestCategories({
    required List<CategoryMapKey> keys,
    required List<Category> catalog,
  }) async {
    if (keys.isEmpty) return {};
    final tree = _categoryTreeText(catalog);
    final sources = [
      for (final k in keys)
        {
          'kind': k.kind,
          'primary': k.primary,
          'secondary': k.secondary,
        },
    ];
    final prompt = '''
你是记账分类映射助手。把 CSV 分类对到本机已有分类。
本机分类树：
$tree

CSV 分类（kind 为 expense 或 income）：
${jsonEncode(sources)}

只返回 JSON 数组。每项：
{"kind":"expense","primary":"餐饮","secondary":"外卖","targetPrimary":"餐饮","targetSecondary":"外卖"}
targetSecondary 可空，表示对到主分类。对不上则省略该项或令两个 target 都空。
''';
    final raw = await _chat(prompt);
    final list = _asList(raw);
    final byId = {for (final c in catalog) c.id: c};
    final result = <CategoryMapKey, int?>{};
    for (final item in list) {
      if (item is! Map) continue;
      final kind = (item['kind'] ?? 'expense').toString();
      final primary = (item['primary'] ?? '').toString().trim();
      final secondary = (item['secondary'] ?? '').toString().trim();
      final tp = (item['targetPrimary'] ?? '').toString().trim();
      final ts = (item['targetSecondary'] ?? '').toString().trim();
      final key = CategoryMapKey(
        kind: kind == 'income' ? 'income' : 'expense',
        primary: primary,
        secondary: secondary,
      );
      final id = _findCategory(
        catalog: catalog,
        byId: byId,
        kind: key.kind,
        primary: tp,
        secondary: ts,
      );
      if (id != null) result[key] = id;
    }
    return result;
  }

  Future<Map<String, int?>> suggestTags({
    required List<String> names,
    required List<TagGroupBundle> bundles,
  }) async {
    if (names.isEmpty) return {};
    final catalog = [
      for (final b in bundles)
        for (final t in b.tags)
          '${b.group.name} / ${t.name}',
    ];
    final prompt = '''
你是记账标签映射助手。把 CSV 标签名对到本机已有标签（名称全库唯一）。
本机标签（组 / 名称）：
${catalog.join('\n')}

CSV 标签名：
${jsonEncode(names)}

只返回 JSON 数组：[{"source":"微信","target":"微信"}]
对不上则省略。target 必须是本机已有标签名。
''';
    final raw = await _chat(prompt);
    final byName = <String, int>{
      for (final b in bundles)
        for (final t in b.tags) t.name: t.id,
    };
    final result = <String, int?>{};
    for (final item in _asList(raw)) {
      if (item is! Map) continue;
      final source = (item['source'] ?? '').toString().trim();
      final target = (item['target'] ?? '').toString().trim();
      if (source.isEmpty || target.isEmpty) continue;
      final id = byName[target];
      if (id != null) result[source] = id;
    }
    return result;
  }

  Future<String> _chat(String prompt) async {
    final provider = await _store.resolve(AiCapabilityKind.text);
    return _client.chat(
      provider: provider,
      userPrompt: prompt,
      systemPrompt: '只输出 JSON，不要 Markdown 说明。',
      temperature: 0.1,
      timeout: _timeout,
    );
  }

  String _categoryTreeText(List<Category> catalog) {
    final mains = catalog.where((c) => c.parentId == null).toList();
    final buf = StringBuffer();
    for (final kind in ['expense', 'income']) {
      buf.writeln(kind == 'income' ? '收入：' : '支出：');
      for (final m in mains.where((c) => c.kind == kind)) {
        buf.writeln('- ${m.name}');
        for (final child in catalog.where((c) => c.parentId == m.id)) {
          buf.writeln('  - ${child.name}');
        }
      }
    }
    return buf.toString();
  }

  int? _findCategory({
    required List<Category> catalog,
    required Map<int, Category> byId,
    required String kind,
    required String primary,
    required String secondary,
  }) {
    if (primary.isEmpty && secondary.isEmpty) return null;
    if (secondary.isNotEmpty) {
      final children = catalog.where(
        (c) =>
            c.kind == kind &&
            c.parentId != null &&
            c.name == secondary,
      );
      for (final c in children) {
        if (primary.isEmpty) return c.id;
        final p = byId[c.parentId];
        if (p?.name == primary) return c.id;
      }
    }
    if (primary.isNotEmpty) {
      final mains = catalog.where(
        (c) => c.kind == kind && c.parentId == null && c.name == primary,
      );
      if (mains.isNotEmpty) return mains.first.id;
      final any = catalog.where((c) => c.kind == kind && c.name == primary);
      if (any.isNotEmpty) return any.first.id;
    }
    return null;
  }

  Map<String, dynamic> _asObject(String raw) {
    final text = _extract(raw, '{', '}');
    if (text == null) return {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return {};
  }

  List<dynamic> _asList(String raw) {
    final text = _extract(raw, '[', ']');
    if (text != null) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    final obj = _asObject(raw);
    final mappings = obj['mappings'];
    if (mappings is List) return mappings;
    return const [];
  }

  String? _extract(String text, String open, String close) {
    final start = text.indexOf(open);
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }
}
