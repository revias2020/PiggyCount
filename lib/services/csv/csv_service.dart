import 'dart:convert';

import 'package:intl/intl.dart';

import '../../data/app_database.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../data/repositories/tag_repository.dart';
import '../../data/repositories/transaction_repository.dart';

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
          _cell(fmt.format(tx.happenedAt)),
          _cell(typeLabel),
          _cell(tx.amount.toStringAsFixed(2)),
          _cell(primary),
          _cell(secondary),
          _cell(item.tagNames.join('|')),
          _cell(tx.note ?? ''),
          _cell(ledgerName[tx.ledgerId] ?? ''),
        ].join(','),
      );
    }
    return buf.toString();
  }

  /// 导入；分类/标签不存在时创建；账本按名匹配或创建。
  Future<int> importCsv(String raw, {int? defaultLedgerId}) async {
    final text = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) return 0;

    var start = 0;
    var singleCategoryCol = false;
    if (lines.first.contains('日期') ||
        lines.first.toLowerCase().contains('time')) {
      final h = lines.first;
      // 旧扁平导出只有一列「分类」
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
      final cols = _parseRow(line);
      if (cols.length < 3) continue;

      final happenedAt = _parseDate(cols[0]) ?? DateTime.now();
      final type = _parseType(cols.length > 1 ? cols[1] : '支出');
      final amount = double.tryParse(
            (cols.length > 2 ? cols[2] : '').replaceAll(',', ''),
          ) ??
          0;
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
        for (final name in tagPart.split(RegExp(r'[|｜、,，;；]'))) {
          final n = name.trim();
          if (n.isEmpty) continue;
          var id = tagByName[n];
          if (id == null) {
            id = await tags.create(n); // 落入「默认」字符串组
            tagByName[n] = id;
          }
          tagIds.add(id);
        }
      }

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
      final child = list.where(
        (c) => c.name == secondary && c.parentId != null,
      );
      if (child.isNotEmpty) {
        if (primary.isEmpty) return child.first.id;
        final parentOk = list.any(
          (c) => c.id == child.first.parentId && c.name == primary,
        );
        if (parentOk || primary.isEmpty) return child.first.id;
      }
      int? parentId;
      if (primary.isNotEmpty) {
        final parents =
            list.where((c) => c.name == primary && c.parentId == null);
        parentId = parents.isEmpty
            ? await categories.create(name: primary, kind: kind)
            : parents.first.id;
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

  String _cell(String value) {
    final needsQuote =
        value.contains(',') || value.contains('"') || value.contains('\n');
    final escaped = value.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }

  List<String> _parseRow(String line) {
    final result = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        result.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    result.add(buf.toString());
    return result;
  }

  DateTime? _parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final tryFormats = [
      DateFormat('yyyy-MM-dd HH:mm:ss'),
      DateFormat('yyyy/MM/dd HH:mm:ss'),
      DateFormat('yyyy-MM-dd'),
      DateFormat('yyyy/MM/dd'),
    ];
    for (final f in tryFormats) {
      try {
        return f.parse(s);
      } catch (_) {}
    }
    return DateTime.tryParse(s);
  }

  String _parseType(String raw) {
    final s = raw.trim();
    if (s.contains('收') || s.toLowerCase().contains('income')) {
      return 'income';
    }
    return 'expense';
  }
}
