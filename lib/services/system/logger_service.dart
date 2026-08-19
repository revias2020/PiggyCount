import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 程序日志级别（ADR-014：不做 debug 进中心）。
enum LogLevel {
  info,
  warning,
  error;

  String get displayName => switch (this) {
        LogLevel.info => 'INFO',
        LogLevel.warning => 'WARN',
        LogLevel.error => 'ERROR',
      };
}

/// 一条程序日志。
class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.millisecondsSinceEpoch,
        'level': level.index,
        'tag': tag,
        'message': message,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      level: LogLevel.values[(json['level'] as int).clamp(0, LogLevel.values.length - 1)],
      tag: json['tag'] as String? ?? '',
      message: json['message'] as String? ?? '',
      error: json['error'] as String?,
      stackTrace: json['stackTrace'] as String?,
    );
  }

  String toFormattedString() {
    final buffer = StringBuffer();
    final t = timestamp;
    final time =
        '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${_three(t.millisecond)}';
    buffer.writeln('[$time] [${level.displayName}] [$tag] $message');
    if (error != null && error!.isNotEmpty) {
      buffer.writeln('  Error: $error');
    }
    if (stackTrace != null && stackTrace!.isNotEmpty) {
      buffer.writeln('  Stack:\n  ${stackTrace!.replaceAll('\n', '\n  ')}');
    }
    return buffer.toString();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _three(int n) => n.toString().padLeft(3, '0');
}

/// 打码密钥类片段后再入库 / 展示。
String sanitizeLogText(String input) {
  var s = input;
  s = s.replaceAllMapped(
    RegExp(r'(Bearer\s+)\S+', caseSensitive: false),
    (m) => '${m[1]}***',
  );
  s = s.replaceAllMapped(
    RegExp(r'(api[_-]?key\s*[:=]\s*)\S+', caseSensitive: false),
    (m) => '${m[1]}***',
  );
  s = s.replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{10,}'), 'sk-***');
  s = s.replaceAllMapped(
    RegExp(r'(password|secret|access[_-]?key)\s*[:=]\s*\S+', caseSensitive: false),
    (m) => '${m[1]}=***',
  );
  return s;
}

/// 程序日志服务：内存队列 + SharedPreferences；约 48h、最多 1000 条（ADR-014）。
class LoggerService {
  LoggerService._();

  static const _storageKey = 'piggy_app_logs';
  static const _maxStorageHours = 48;
  static const _maxLogs = 1000;

  final Queue<LogEntry> _logs = Queue<LogEntry>();
  final List<VoidCallback> _listeners = [];
  bool _loaded = false;
  Timer? _saveTimer;
  bool _saving = false;

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final l in List<VoidCallback>.from(_listeners)) {
      l();
    }
  }

  /// 启动时调用：加载并裁剪过期条目。
  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        final now = DateTime.now();
        for (final item in list) {
          try {
            final entry = LogEntry.fromJson(item as Map<String, dynamic>);
            if (now.difference(entry.timestamp).inHours < _maxStorageHours) {
              _logs.add(entry);
            }
          } catch (_) {}
        }
        while (_logs.length > _maxLogs) {
          _logs.removeFirst();
        }
      }
    } catch (e) {
      debugPrint('程序日志加载失败: $e');
    } finally {
      _loaded = true;
    }
  }

  void info(String tag, String message) {
    _add(LogLevel.info, tag, message);
  }

  void warning(String tag, String message, [Object? error]) {
    _add(LogLevel.warning, tag, message, error: error);
  }

  void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _add(
      LogLevel.error,
      tag,
      message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _add(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_loaded) {
      // 启动极早期：仍写入内存，init 后再持久化
      scheduleMicrotask(() async {
        if (!_loaded) await init();
      });
    }

    var stack = stackTrace?.toString();
    if (stack != null && stack.length > 4000) {
      stack = '${stack.substring(0, 4000)}…';
    }

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: sanitizeLogText(message),
      error: error == null ? null : sanitizeLogText('$error'),
      stackTrace: stack == null ? null : sanitizeLogText(stack),
    );

    while (_logs.length >= _maxLogs) {
      _logs.removeFirst();
    }
    _logs.add(entry);

    if (kDebugMode) {
      debugPrint(entry.toFormattedString());
    }

    _notify();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _persist);
  }

  Future<void> _persist() async {
    if (_saving) return;
    _saving = true;
    try {
      final now = DateTime.now();
      _logs.removeWhere(
        (e) => now.difference(e.timestamp).inHours >= _maxStorageHours,
      );
      while (_logs.length > _maxLogs) {
        _logs.removeFirst();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(_logs.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('程序日志保存失败: $e');
    } finally {
      _saving = false;
    }
  }

  Future<void> clear() async {
    _logs.clear();
    _notify();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  String exportAsText() {
    final buffer = StringBuffer();
    buffer.writeln('=== 小猪记账 · 程序日志 ===');
    buffer.writeln('导出时间: ${DateTime.now()}');
    buffer.writeln('条数: ${_logs.length}');
    buffer.writeln('=' * 40);
    buffer.writeln();
    for (final log in _logs) {
      buffer.write(log.toFormattedString());
      buffer.writeln();
    }
    return buffer.toString();
  }
}

/// 全局程序日志实例。
final logger = LoggerService._();
