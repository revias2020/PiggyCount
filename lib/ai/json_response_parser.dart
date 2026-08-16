import 'dart:convert';

import 'bill_info.dart';

/// 将模型文本解析为 [BillInfo] 列表；容错 markdown / trailing comma / 单对象。
class JsonResponseParser {
  const JsonResponseParser();

  List<BillInfo> parse(String response) {
    final arrayBlock = _extractBalancedBlock(response, '[', ']');
    if (arrayBlock != null) {
      try {
        final decoded = jsonDecode(_cleanupJson(arrayBlock));
        if (decoded is List) {
          final bills = <BillInfo>[];
          for (final item in decoded) {
            if (item is! Map) continue;
            final sanitized =
                _sanitize(BillInfo.fromJson(Map<String, dynamic>.from(item)));
            if (sanitized != null) bills.add(sanitized);
          }
          if (bills.isNotEmpty) return bills;
        }
      } catch (_) {
        // fallback 单对象
      }
    }

    final objectBlock = _extractBalancedBlock(response, '{', '}');
    if (objectBlock == null) return const [];
    try {
      final json =
          jsonDecode(_cleanupJson(objectBlock)) as Map<String, dynamic>;
      final sanitized = _sanitize(BillInfo.fromJson(json));
      return sanitized == null ? const [] : [sanitized];
    } catch (_) {
      return const [];
    }
  }

  BillInfo? _sanitize(BillInfo bill) {
    final amt = bill.amount;
    if (amt == null || amt <= 0) return null;
    if (bill.time == null) {
      return bill.copyWith(
        time: DateTime.now(),
        type: bill.type ?? BillType.expense,
      );
    }
    return bill.copyWith(type: bill.type ?? BillType.expense);
  }

  String _cleanupJson(String input) {
    final out = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (inString) {
        out.write(c);
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        out.write(c);
        continue;
      }
      if (c == ',') {
        var j = i + 1;
        while (j < input.length &&
            (input[j] == ' ' ||
                input[j] == '\t' ||
                input[j] == '\n' ||
                input[j] == '\r')) {
          j++;
        }
        if (j < input.length && (input[j] == '}' || input[j] == ']')) {
          continue;
        }
      }
      out.write(c);
    }
    return out.toString();
  }

  String? _extractBalancedBlock(String text, String open, String close) {
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
