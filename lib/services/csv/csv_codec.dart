import 'package:intl/intl.dart';

/// CSV 单元格 / 行 / 日期 / 金额 / 类型的共用解析。
abstract final class CsvCodec {
  static const tagSplit = r'[|｜、,，;；]';

  static String cell(String value) {
    final needsQuote =
        value.contains(',') || value.contains('"') || value.contains('\n');
    final escaped = value.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }

  static List<String> parseRow(String line) {
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

  static DateTime? parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final tryFormats = [
      DateFormat('yyyy-MM-dd HH:mm:ss'),
      DateFormat('yyyy/MM/dd HH:mm:ss'),
      DateFormat('yyyy-MM-dd HH:mm'),
      DateFormat('yyyy/MM/dd HH:mm'),
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

  static double? parseAmount(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[¥￥$€,\s]'), '');
    return double.tryParse(s);
  }

  static String parseType(String raw) {
    final s = raw.trim();
    if (s.contains('收') || s.toLowerCase().contains('income')) {
      return 'income';
    }
    return 'expense';
  }

  static List<String> splitTags(String raw) {
    final names = <String>[];
    for (final name in raw.split(RegExp(tagSplit))) {
      final n = name.trim();
      if (n.isNotEmpty) names.add(n);
    }
    return names;
  }
}
