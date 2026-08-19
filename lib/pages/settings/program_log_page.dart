import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/system/local_export_service.dart';
import '../../services/system/logger_service.dart';
import '../../styles/tokens.dart';

/// 程序日志页：搜索、级别筛选、清空、导出（ADR-014）。
class ProgramLogPage extends StatefulWidget {
  const ProgramLogPage({super.key});

  @override
  State<ProgramLogPage> createState() => _ProgramLogPageState();
}

class _ProgramLogPageState extends State<ProgramLogPage> {
  final Set<LogLevel> _selectedLevels = LogLevel.values.toSet();
  final _searchController = TextEditingController();
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    logger.addListener(_onChanged);
  }

  @override
  void dispose() {
    logger.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<LogEntry> get _filtered {
    final kw = _keyword.trim().toLowerCase();
    return logger.logs.reversed.where((log) {
      if (!_selectedLevels.contains(log.level)) return false;
      if (kw.isEmpty) return true;
      return log.message.toLowerCase().contains(kw) ||
          log.tag.toLowerCase().contains(kw) ||
          (log.error?.toLowerCase().contains(kw) ?? false);
    }).toList();
  }

  Future<void> _export() async {
    try {
      final stamp = LocalExportService.fileStamp();
      final result = await LocalExportService.exportText(
        fileName: 'piggy_logs_$stamp.log',
        content: logger.exportAsText(),
        mimeType: 'text/plain',
        shareSubject: '小猪记账 · 程序日志',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.successMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定清空全部程序日志？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await logger.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日志已清空')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: const Text('程序日志'),
        actions: [
          IconButton(
            tooltip: '导出',
            onPressed: _export,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索内容或标签…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _keyword = '');
                        },
                      ),
                filled: true,
                fillColor: PigTokens.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PigTokens.radiusCard),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _keyword = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: LogLevel.values.map((level) {
                  final selected = _selectedLevels.contains(level);
                  return FilterChip(
                    label: Text(level.displayName),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (on) {
                      setState(() {
                        if (on) {
                          _selectedLevels.add(level);
                        } else {
                          _selectedLevels.remove(level);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '共 ${logger.logs.length} 条 · 显示 ${filtered.length} 条',
                style: const TextStyle(
                  fontSize: 12,
                  color: PigTokens.textTertiary,
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      '暂无日志',
                      style: TextStyle(color: PigTokens.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _LogTile(entry: filtered[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final LogEntry entry;

  Color get _levelColor => switch (entry.level) {
        LogLevel.info => PigTokens.primary,
        LogLevel.warning => const Color(0xFFD97706),
        LogLevel.error => PigTokens.danger,
      };

  String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  void _showDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('[${entry.tag}]'),
        content: SingleChildScrollView(
          child: SelectableText(entry.toFormattedString()),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: entry.toFormattedString()),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制')),
              );
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: PigTokens.surface,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(PigTokens.radiusCard),
          onTap: () => _showDetail(context),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: entry.toFormattedString()));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制')),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _levelColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _levelColor),
                      ),
                      child: Text(
                        entry.level.displayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _levelColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: PigTokens.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      _time(entry.timestamp),
                      style: const TextStyle(
                        fontSize: 11,
                        color: PigTokens.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  entry.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: PigTokens.textPrimary,
                  ),
                ),
                if (entry.error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PigTokens.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
