import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../providers/database_provider.dart';
import '../../providers/ledger_session_provider.dart';
import '../../services/csv/csv_service.dart';
import '../../services/csv/csv_table.dart';
import '../../services/system/local_export_service.dart';
import '../../services/system/logger_service.dart';
import '../../styles/tokens.dart';
import 'import_mapping_page.dart';
import '../../widgets/pig_toast.dart';

final csvServiceProvider = Provider(
  (ref) => CsvService(
    ledgers: ref.watch(ledgerRepositoryProvider),
    categories: ref.watch(categoryRepositoryProvider),
    tags: ref.watch(tagRepositoryProvider),
    transactions: ref.watch(transactionRepositoryProvider),
  ),
);

/// 数据管理：CSV 导入 / 导出（当前账本或全部）。
class DataManagePage extends ConsumerStatefulWidget {
  const DataManagePage({super.key});

  @override
  ConsumerState<DataManagePage> createState() => _DataManagePageState();
}

class _DataManagePageState extends ConsumerState<DataManagePage> {
  bool _allLedgers = false;
  bool _busy = false;
  bool _aiMapping = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final ledgerId =
          _allLedgers ? null : ref.read(currentLedgerIdProvider);
      final csv = await ref.read(csvServiceProvider).exportCsv(ledgerId: ledgerId);
      final stamp = LocalExportService.fileStamp();
      final name = _allLedgers
          ? 'piggy_all_$stamp.csv'
          : 'piggy_ledger_$stamp.csv';
      final result = await LocalExportService.exportText(
        fileName: name,
        content: csv,
        mimeType: 'text/csv',
        shareSubject: '小猪记账导出',
      );
      logger.info('CSV', _allLedgers ? '导出全部账本完成' : '导出当前账本完成');
      if (!mounted) return;
      PigToast.show(context, result.successMessage);
    } catch (e, st) {
      logger.error('CSV', '导出失败', e, st);
      if (!mounted) return;
      PigToast.show(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
    );
    if (file == null || !mounted) return;
    final raw = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    late final CsvTable table;
    try {
      table = CsvTable.parse(raw);
    } on FormatException catch (e) {
      if (!mounted) return;
      PigToast.show(context, e.message);
      return;
    } catch (e) {
      if (!mounted) return;
      PigToast.show(context, '无法读取文件：$e');
      return;
    }

    if (!mounted) return;
    final n = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ImportMappingPage(
          table: table,
          aiEnabled: _aiMapping,
        ),
      ),
    );
    if (!mounted || n == null) return;
    logger.info('CSV', '导入完成 $n 笔');
    PigToast.show(context, '成功导入 $n 笔');
  }

  @override
  Widget build(BuildContext context) {
    final textReady = ref.watch(textCapabilityReadyProvider).valueOrNull ?? false;
    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: const Text('数据管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Material(
            color: PigTokens.surface,
            borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CSV 导入 / 导出',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '导入会先进入列名映射。打开 AI 智能映射后，用文本对话模型预填列名、分类与标签映射（可再改）。分类/标签不存在会按规则创建。',
                    style:
                        TextStyle(fontSize: 13, color: PigTokens.textSecondary),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('导出全部账本'),
                    subtitle: const Text('关闭则仅导出当前账本'),
                    value: _allLedgers,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _allLedgers = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('AI 智能映射'),
                    subtitle: Text(
                      textReady
                          ? '用文本对话模型辅助列名、分类、标签映射'
                          : '请先在 AI 设置中绑定并测通文本对话',
                    ),
                    value: _aiMapping && textReady,
                    onChanged: _busy || !textReady
                        ? null
                        : (v) => setState(() => _aiMapping = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _import,
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('导入 CSV'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _export,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.file_download_outlined),
                          label: const Text('导出 CSV'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
