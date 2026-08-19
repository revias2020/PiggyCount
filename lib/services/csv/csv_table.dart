import 'dart:convert';

import 'csv_codec.dart';

/// 带表头的 CSV 表。无表头时不要构造，调用方应先 [looksLikeDataRow]。
class CsvTable {
  CsvTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  static const noHeaderMessage = '文件没有表头，请使用带列名的 CSV';

  int get columnCount => headers.length;

  /// 去掉 BOM 后按行切开。
  static List<String> splitLines(String raw) {
    final text = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
    return const LineSplitter()
        .convert(text)
        .map((l) => l.trimRight())
        .where((l) => l.trim().isNotEmpty)
        .toList();
  }

  /// 首行能同时解析出日期和金额，视为数据行（无表头）。
  static bool looksLikeDataRow(List<String> cells) {
    var hasDate = false;
    var hasAmount = false;
    for (final cell in cells) {
      if (!hasDate && CsvCodec.parseDate(cell) != null) hasDate = true;
      final amt = CsvCodec.parseAmount(cell);
      if (!hasAmount && amt != null && amt > 0) hasAmount = true;
      if (hasDate && hasAmount) return true;
    }
    return false;
  }

  /// 解析带表头的 CSV。无表头抛 [FormatException]。
  static CsvTable parse(String raw) {
    final lines = splitLines(raw);
    if (lines.isEmpty) {
      throw const FormatException('文件为空');
    }
    final headerCells = CsvCodec.parseRow(lines.first);
    if (looksLikeDataRow(headerCells)) {
      throw const FormatException(noHeaderMessage);
    }
    final rows = <List<String>>[];
    for (var i = 1; i < lines.length; i++) {
      rows.add(CsvCodec.parseRow(lines[i]));
    }
    return CsvTable(headers: headerCells, rows: rows);
  }

  String cell(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  int? indexOfHeader(String? name) {
    if (name == null || name.isEmpty) return null;
    for (var i = 0; i < headers.length; i++) {
      if (headers[i].trim() == name.trim()) return i;
    }
    return null;
  }
}
