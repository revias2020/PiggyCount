import 'dart:convert';

import 'package:intl/intl.dart';

import '../../data/app_database.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../data/repositories/tag_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import 'csv_codec.dart';
import 'csv_import_mapping.dart';
import 'csv_table.dart';

/// CSV 列：日期时间,类型,金额,主分类,子分类,标签,备注,账本名
class CsvService {
  CsvService({
    required this.ledgers,
    required this.categories,
    required this.tags,
    required this.transactions,
  });

  final LedgerRepository ledgers;
  final CategoryRepository categories;
  final TagRepository tags;
  final TransactionRepository transactions;

  static const header = '日期时间,类型,金额,主分类,子分类,标签,备注,账本名';

  /// 导出 UTF-8（带 BOM，方便 Excel）。
  Future<String> exportCsv({int? ledgerId}) async {
    final allLedgers = await ledgers.getAll();
    final ledgerName = {for (final l in allLedgers) l.id: l.name};
    final cats = await _allCategories();
    final byId = {for (final c in cats) c.id: c};

    final items = await transactions.listForExport(ledgerId: ledgerId);
    final buf = StringBuffer()
      ..write('\uFEFF')
      ..writeln(header);

    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    for (final item in items) {
      final tx = item.tx;
      final cat = tx.categoryId == null ? null : byId[tx.categoryId];
      String primary = '';
      String secondary = '';
      if (cat != null) {
        if (cat.parentId == null) {
          primary = cat.name;
        } else {
          secondary = cat.name;
          primary = byId[cat.parentId]?.name ?? '';
        }
      }
      final typeLabel = tx.type == 'income' ? '收入' : '支出';
      buf.writeln(
        [
          CsvCodec.cell(fmt.format(tx.happenedAt)),
          CsvCodec.cell(typeLabel),
          CsvCodec.cell(tx.amount.toStringAsFixed(2)),
          CsvCodec.cell(primary),
          CsvCodec.cell(secondary),
          CsvCodec.cell(item.tagNames.join('|')),
          CsvCodec.cell(tx.note ?? ''),
          CsvCodec.cell(ledgerName[tx.ledgerId] ?? ''),
        ].join(','),
      );
    }
    return buf.toString();
  }

  /// 云下载等：按列位置导入（兼容旧扁平「分类」列）。不走导入映射向导。
  Future<int> importCsv(String raw, {int? defaultLedgerId}) async {
    final text = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) return 0;

    var start = 0;
    var singleCategoryCol = false;
    if (lines.first.contains('日期') ||
        lines.first.toLowerCase().contains('time')) {
      final h = lines.first;
      singleCategoryCol = h.contains(',分类,') &&
          !h.contains('主分类') &&
          !h.contains('一级分类') &&
          !h.contains('子分类') &&
          !h.contains('二级分类');
      start = 1;
    }

    final allLedgers = await ledgers.getAll();
    final ledgerByName = {for (final l in allLedgers) l.name: l.id};
    final allTags = await tags.getAll();
    final tagByName = {for (final t in allTags) t.name: t.id};

    var imported = 0;
    for (var i = start; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final cols = CsvCodec.parseRow(line);
      if (cols.length < 3) continue;

      final happenedAt = CsvCodec.parseDate(cols[0]) ?? DateTime.now();
      final type = CsvCodec.parseType(cols.length > 1 ? cols[1] : '支出');
      final amount = CsvCodec.parseAmount(cols.length > 2 ? cols[2] : '') ?? 0;
      if (amount <= 0) continue;

      late final String primary;
      late final String secondary;
      late final String tagPart;
      late final String note;
      late final String ledgerNameStr;

      if (singleCategoryCol) {
        primary = cols.length > 3 ? cols[3].trim() : '';
        secondary = '';
        tagPart = cols.length > 4 ? cols[4].trim() : '';
        note = cols.length > 5 ? cols[5].trim() : '';
        ledgerNameStr = cols.length > 6 ? cols[6].trim() : '';
      } else {
        primary = cols.length > 3 ? cols[3].trim() : '';
        secondary = cols.length > 4 ? cols[4].trim() : '';
        tagPart = cols.length > 5 ? cols[5].trim() : '';
        note = cols.length > 6 ? cols[6].trim() : '';
        ledgerNameStr = cols.length > 7 ? cols[7].trim() : '';
      }

      var ledgerId = defaultLedgerId;
      if (ledgerNameStr.isNotEmpty) {
        ledgerId = ledgerByName[ledgerNameStr];
        if (ledgerId == null) {
          ledgerId = await ledgers.create(ledgerNameStr, select: false);
          ledgerByName[ledgerNameStr] = ledgerId;
        }
      }
      ledgerId ??= (await ledgers.getAll()).first.id;

      final categoryId = await _resolveCategory(
        kind: type,
        primary: primary,
        secondary: secondary,
      );

      final tagIds = <int>[];
      if (tagPart.isNotEmpty) {
        for (final n in CsvCodec.splitTags(tagPart)) {
          var id = tagByName[n];
          if (id == null) {
            id = await tags.create(n);
            tagByName[n] = id;
          }
          tagIds.add(id);
        }
      }

        try {
          await transactions.insert(
            ledgerId: ledgerId,
            type: type,
            amount: amount.abs(),
            categoryId: categoryId,
            happenedAt: happenedAt,
            note: note.isEmpty ? null : note,
            tagIds: tagIds,
            source: 'manual',
          );
          imported++;
        } on StateError catch (e) {
          if (!e.message.contains('已存在相同')) rethrow;
        }
    }
    return imported;
  }

  /// 导入映射向导确认后的写入。日期/金额解析失败的行跳过，不用「此刻」。
  Future<int> importMapped({
    required CsvTable table,
    required ColumnMapping columns,
    required int defaultLedgerId,
    Map<CategoryMapKey, int?> categoryMap = const {},
    Map<String, int?> tagMap = const {},
    void Function(int current, int total)? onProgress,
  }) async {
    final total = table.rows.length;
    onProgress?.call(0, total == 0 ? 1 : total);
    if (total == 0) return 0;

    final allLedgers = await ledgers.getAll();
    final ledgerByName = {for (final l in allLedgers) l.name: l.id};
    final allTags = await tags.getAll();
    final tagByName = {for (final t in allTags) t.name: t.id};
    final bundles = await tags.getBundles();
    final tagScope = <int, String>{
      for (final b in bundles)
        for (final t in b.tags) t.id: b.group.scope,
    };

    var imported = 0;
    for (var i = 0; i < table.rows.length; i++) {
      final row = table.rows[i];
      try {
        final dateRaw =
            CsvImportMapping.cell(table, row, columns, CsvImportField.happenedAt);
        final amountRaw =
            CsvImportMapping.cell(table, row, columns, CsvImportField.amount);
        final happenedAt = CsvCodec.parseDate(dateRaw);
        final amount = CsvCodec.parseAmount(amountRaw);
        if (happenedAt == null || amount == null || amount <= 0) {
          continue;
        }

        final typeRaw =
            CsvImportMapping.cell(table, row, columns, CsvImportField.type);
        final type =
            typeRaw.isEmpty ? 'expense' : CsvCodec.parseType(typeRaw);
        final primary = CsvImportMapping.cell(
          table,
          row,
          columns,
          CsvImportField.primaryCategory,
        );
        final secondary = CsvImportMapping.cell(
          table,
          row,
          columns,
          CsvImportField.secondaryCategory,
        );
        final tagPart =
            CsvImportMapping.cell(table, row, columns, CsvImportField.tags);
        final note =
            CsvImportMapping.cell(table, row, columns, CsvImportField.note);
        final ledgerNameStr =
            CsvImportMapping.cell(table, row, columns, CsvImportField.ledgerName);

        var ledgerId = defaultLedgerId;
        if (ledgerNameStr.isNotEmpty) {
          ledgerId = ledgerByName[ledgerNameStr] ??
              await ledgers.create(ledgerNameStr, select: false);
          ledgerByName[ledgerNameStr] = ledgerId;
        }

        final catKey = CategoryMapKey(
          kind: type,
          primary: primary,
          secondary: secondary,
        );
        // 三态：无键=自动；键且 null=不映射（未分类）；键且 id=对到该分类（ADR-043）。
        int? categoryId;
        if (categoryMap.containsKey(catKey)) {
          categoryId = categoryMap[catKey];
        } else {
          categoryId = await _resolveCategory(
            kind: type,
            primary: primary,
            secondary: secondary,
          );
        }

        final tagIds = <int>[];
        for (final n in CsvCodec.splitTags(tagPart)) {
          // 三态：无键=自动；键且 null=不映射（忽略该名）；键且 id=对到该标签（ADR-043）。
          late final int id;
          if (tagMap.containsKey(n)) {
            final mapped = tagMap[n];
            if (mapped == null) continue;
            id = mapped;
          } else {
            id = tagByName[n] ?? await tags.create(n);
            tagByName[n] = id;
            tagScope.putIfAbsent(id, () => TagGroupScope.both);
          }
          final scope = tagScope[id] ?? TagGroupScope.both;
          if (!TagGroupScope.matchesType(scope, type)) continue;
          tagIds.add(id);
        }

        try {
          await transactions.insert(
            ledgerId: ledgerId,
            type: type,
            amount: amount.abs(),
            categoryId: categoryId,
            happenedAt: happenedAt,
            note: note.isEmpty ? null : note,
            tagIds: tagIds,
            source: 'manual',
          );
          imported++;
        } on StateError catch (e) {
          if (!e.message.contains('已存在相同')) rethrow;
        }
      } finally {
        onProgress?.call(i + 1, total);
      }
    }
    return imported;
  }

  Future<List<Category>> _allCategories() async {
    final expense = await categories.listByKind('expense');
    final income = await categories.listByKind('income');
    return [...expense, ...income];
  }

  Future<int?> _resolveCategory({
    required String kind,
    required String primary,
    required String secondary,
  }) async {
    final list = await categories.listByKind(kind);
    if (primary.isEmpty && secondary.isEmpty) return null;

    if (secondary.isNotEmpty) {
      Category? byName(String n) {
        final hits = list.where((c) => c.name == n);
        return hits.isEmpty ? null : hits.first;
      }

      final existingLeaf = byName(secondary);
      if (existingLeaf != null) return existingLeaf.id;
      int? parentId;
      if (primary.isNotEmpty) {
        final parent = byName(primary);
        if (parent == null) {
          parentId = await categories.create(name: primary, kind: kind);
        } else if (parent.parentId == null) {
          parentId = parent.id;
        }
      }
      return categories.create(
        name: secondary,
        kind: kind,
        parentId: parentId,
      );
    }

    if (primary.isNotEmpty) {
      final hit = list.where((c) => c.name == primary);
      if (hit.isNotEmpty) return hit.first.id;
      return categories.create(name: primary, kind: kind);
    }
    return null;
  }
}
