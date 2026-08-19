import '../../data/app_database.dart';
import 'csv_codec.dart';
import 'csv_table.dart';

/// 数据导入可映射的账单字段。
enum CsvImportField {
  happenedAt,
  type,
  amount,
  primaryCategory,
  secondaryCategory,
  tags,
  note,
  ledgerName,
}

extension CsvImportFieldLabel on CsvImportField {
  String get label => switch (this) {
        CsvImportField.happenedAt => '日期时间',
        CsvImportField.type => '类型',
        CsvImportField.amount => '金额',
        CsvImportField.primaryCategory => '主分类',
        CsvImportField.secondaryCategory => '子分类',
        CsvImportField.tags => '标签',
        CsvImportField.note => '备注',
        CsvImportField.ledgerName => '账本名',
      };

  bool get required =>
      this == CsvImportField.happenedAt || this == CsvImportField.amount;

  List<String> get aliases => switch (this) {
        CsvImportField.happenedAt => const [
            '日期时间',
            '交易时间',
            '记账时间',
            '日期',
            '时间',
            'datetime',
            'date',
            'time',
            'happened_at',
          ],
        CsvImportField.type => const [
            '类型',
            '收/支',
            '收入/支出',
            '收支',
            'type',
          ],
        CsvImportField.amount => const [
            '金额',
            '数目',
            'amount',
            'money',
            'price',
          ],
        CsvImportField.primaryCategory => const [
            '主分类',
            '一级分类',
            '交易分类',
            '分类',
            'category_name',
            'category',
          ],
        CsvImportField.secondaryCategory => const [
            '子分类',
            '二级分类',
            'sub_category',
            'subcategory',
          ],
        CsvImportField.tags => const [
            '标签',
            'tags',
            'tag',
          ],
        CsvImportField.note => const [
            '备注',
            '商品说明',
            '说明',
            'note',
            'memo',
            'description',
          ],
        CsvImportField.ledgerName => const [
            '账本名',
            '账本',
            'ledger_name',
            'ledger',
          ],
      };
}

/// 列名映射：字段 → CSV 表头（null 表示不映射）。
class ColumnMapping {
  ColumnMapping([Map<CsvImportField, String?>? values])
      : values = {
          for (final f in CsvImportField.values) f: values?[f],
        };

  final Map<CsvImportField, String?> values;

  String? operator [](CsvImportField field) => values[field];

  void operator []=(CsvImportField field, String? header) {
    values[field] = header;
  }

  bool get isReady =>
      (values[CsvImportField.happenedAt]?.isNotEmpty ?? false) &&
      (values[CsvImportField.amount]?.isNotEmpty ?? false);

  String fingerprint() => CsvImportField.values
      .map((f) => '${f.name}:${values[f] ?? ''}')
      .join('|');

  ColumnMapping copy() => ColumnMapping(Map.of(values));

  /// 用表头别名预填；每个表头至多给一个字段。
  static ColumnMapping guess(List<String> headers) {
    final mapping = ColumnMapping();
    final used = <int>{};
    for (final field in CsvImportField.values) {
      for (final alias in field.aliases) {
        final needle = alias.toLowerCase();
        for (var i = 0; i < headers.length; i++) {
          if (used.contains(i)) continue;
          if (headers[i].trim().toLowerCase() == needle) {
            mapping[field] = headers[i];
            used.add(i);
            break;
          }
        }
        if (mapping[field] != null) break;
      }
    }
    return mapping;
  }
}

/// 分类映射的一条：(收支类型, 主分类名, 子分类名)。
class CategoryMapKey {
  const CategoryMapKey({
    required this.kind,
    required this.primary,
    required this.secondary,
  });

  final String kind;
  final String primary;
  final String secondary;

  @override
  bool operator ==(Object other) =>
      other is CategoryMapKey &&
      other.kind == kind &&
      other.primary == primary &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(kind, primary, secondary);

  String get display {
    final typeLabel = kind == 'income' ? '收入' : '支出';
    if (primary.isEmpty && secondary.isEmpty) return typeLabel;
    if (secondary.isEmpty) return '$typeLabel · $primary';
    if (primary.isEmpty) return '$typeLabel · $secondary';
    return '$typeLabel · $primary / $secondary';
  }
}

class ImportPreviewRow {
  const ImportPreviewRow({
    required this.happenedAt,
    required this.amount,
    required this.type,
    required this.category,
    required this.tags,
  });

  final String happenedAt;
  final String amount;
  final String type;
  final String category;
  final String tags;
}

abstract final class CsvImportMapping {
  static const uniqueNameCap = 200;
  static const previewLimit = 5;

  static int? indexOf(CsvTable table, ColumnMapping mapping, CsvImportField f) {
    return table.indexOfHeader(mapping[f]);
  }

  static String cell(
    CsvTable table,
    List<String> row,
    ColumnMapping mapping,
    CsvImportField f,
  ) {
    return table.cell(row, indexOf(table, mapping, f));
  }

  static List<CategoryMapKey> uniqueCategoryKeys(
    CsvTable table,
    ColumnMapping mapping, {
    int cap = uniqueNameCap,
  }) {
    final seen = <CategoryMapKey>{};
    final out = <CategoryMapKey>[];
    final hasPrimary = mapping[CsvImportField.primaryCategory] != null;
    final hasSecondary = mapping[CsvImportField.secondaryCategory] != null;
    if (!hasPrimary && !hasSecondary) return const [];

    for (final row in table.rows) {
      final typeRaw = cell(table, row, mapping, CsvImportField.type);
      final kind =
          typeRaw.isEmpty ? 'expense' : CsvCodec.parseType(typeRaw);
      final primary = cell(table, row, mapping, CsvImportField.primaryCategory);
      final secondary =
          cell(table, row, mapping, CsvImportField.secondaryCategory);
      if (primary.isEmpty && secondary.isEmpty) continue;
      final key = CategoryMapKey(
        kind: kind,
        primary: primary,
        secondary: secondary,
      );
      if (seen.add(key)) {
        out.add(key);
        if (out.length >= cap) break;
      }
    }
    return out;
  }

  static List<String> uniqueTagNames(
    CsvTable table,
    ColumnMapping mapping, {
    int cap = uniqueNameCap,
  }) {
    if (mapping[CsvImportField.tags] == null) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final row in table.rows) {
      final raw = cell(table, row, mapping, CsvImportField.tags);
      for (final name in CsvCodec.splitTags(raw)) {
        if (seen.add(name)) {
          out.add(name);
          if (out.length >= cap) return out;
        }
      }
    }
    return out;
  }

  static String labelFor(Category c, List<Category> catalog) =>
      _labelOf(c, catalog);

  /// [categoryMap] 三态见 ADR-043：无键=自动；键且 null=忽略；键且 id=对到该分类。
  static String categoryPreviewLabel({
    required CategoryMapKey key,
    required Map<CategoryMapKey, int?> categoryMap,
    required List<Category> catalog,
  }) {
    if (categoryMap.containsKey(key)) {
      final mappedId = categoryMap[key];
      if (mappedId == null) return '忽略';
      final hit = catalog.where((c) => c.id == mappedId);
      if (hit.isNotEmpty) return _labelOf(hit.first, catalog);
      return '忽略';
    }
    if (key.secondary.isNotEmpty) {
      final child = catalog.where(
        (c) =>
            c.kind == key.kind &&
            c.name == key.secondary &&
            c.parentId != null,
      );
      if (child.isNotEmpty) {
        if (key.primary.isEmpty) return _labelOf(child.first, catalog);
        final parentOk = catalog.any(
          (c) =>
              c.id == child.first.parentId &&
              c.name == key.primary &&
              c.kind == key.kind,
        );
        if (parentOk) return _labelOf(child.first, catalog);
      }
      final will = key.primary.isEmpty
          ? key.secondary
          : '${key.primary} / ${key.secondary}';
      return '将新建 $will';
    }
    if (key.primary.isNotEmpty) {
      final hit = catalog.where(
        (c) => c.kind == key.kind && c.name == key.primary,
      );
      if (hit.isNotEmpty) return _labelOf(hit.first, catalog);
      return '将新建 ${key.primary}';
    }
    return '—';
  }

  static String _labelOf(Category c, List<Category> catalog) {
    if (c.parentId == null) return c.name;
    Category? parent;
    for (final x in catalog) {
      if (x.id == c.parentId) {
        parent = x;
        break;
      }
    }
    return parent == null ? c.name : '${parent.name} / ${c.name}';
  }

  static List<ImportPreviewRow> preview({
    required CsvTable table,
    required ColumnMapping columns,
    required Map<CategoryMapKey, int?> categoryMap,
    required Map<String, int?> tagMap,
    required List<Category> catalog,
    required Map<int, String> tagNamesById,
    Map<String, int> existingTagByName = const {},
  }) {
    final out = <ImportPreviewRow>[];
    for (final row in table.rows) {
      if (out.length >= previewLimit) break;
      final dateRaw = cell(table, row, columns, CsvImportField.happenedAt);
      final amountRaw = cell(table, row, columns, CsvImportField.amount);
      final typeRaw = cell(table, row, columns, CsvImportField.type);
      final date = CsvCodec.parseDate(dateRaw);
      final amount = CsvCodec.parseAmount(amountRaw);
      final kind = typeRaw.isEmpty ? 'expense' : CsvCodec.parseType(typeRaw);
      final primary =
          cell(table, row, columns, CsvImportField.primaryCategory);
      final secondary =
          cell(table, row, columns, CsvImportField.secondaryCategory);
      String categoryText = '—';
      if (primary.isNotEmpty || secondary.isNotEmpty) {
        final key = CategoryMapKey(
          kind: kind,
          primary: primary,
          secondary: secondary,
        );
        categoryText = categoryPreviewLabel(
          key: key,
          categoryMap: categoryMap,
          catalog: catalog,
        );
      }
      final tagRaw = cell(table, row, columns, CsvImportField.tags);
      final tagBits = <String>[];
      for (final name in CsvCodec.splitTags(tagRaw)) {
        // 三态：无键=自动；键且 null=忽略；键且 id=对到该标签（ADR-043）。
        if (tagMap.containsKey(name)) {
          final id = tagMap[name];
          if (id == null) continue;
          tagBits.add(tagNamesById[id] ?? name);
        } else if (existingTagByName.containsKey(name)) {
          tagBits.add(name);
        } else {
          tagBits.add('$name（外部导入）');
        }
      }
      out.add(
        ImportPreviewRow(
          happenedAt: date == null ? '—' : dateRaw,
          amount: (amount == null || amount <= 0) ? '—' : amountRaw,
          type: typeRaw.isEmpty ? '支出' : (kind == 'income' ? '收入' : '支出'),
          category: categoryText,
          tags: tagBits.isEmpty ? '—' : tagBits.join('、'),
        ),
      );
    }
    return out;
  }
}
