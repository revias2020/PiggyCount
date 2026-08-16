import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/database_provider.dart';
import '../../providers/ledger_session_provider.dart';
import '../../services/csv/csv_service.dart';
import '../../styles/tokens.dart';

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

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final ledgerId =
          _allLedgers ? null : ref.read(currentLedgerIdProvider);
      final csv = await ref.read(csvServiceProvider).exportCsv(ledgerId: ledgerId);
      final dir = await getTemporaryDirectory();
      final name = _allLedgers
          ? 'piggy_all_${DateTime.now().millisecondsSinceEpoch}.csv'
          : 'piggy_ledger_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File(p.join(dir.path, name));
      await file.writeAsString(csv, encoding: utf8);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: '小猪记账导出',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已生成 CSV，请选择分享或保存位置')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      withData: true,
    );
    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.first;
    String raw;
    if (file.bytes != null) {
      raw = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      raw = await File(file.path!).readAsString();
    } else {
      return;
    }

    setState(() => _busy = true);
    try {
      final n = await ref.read(csvServiceProvider).importCsv(
            raw,
            defaultLedgerId: ref.read(currentLedgerIdProvider),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $n 笔')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: const Text('数据管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PigTokens.surface,
              borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CSV 导入 / 导出',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 6),
                const Text(
                  '列：日期时间,类型,金额,主分类,子分类,标签(|分隔),备注,账本名\n'
                  '编码 UTF-8（带 BOM）。导入时分类/标签不存在会自动创建。',
                  style: TextStyle(fontSize: 13, color: PigTokens.textSecondary),
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
        ],
      ),
    );
  }
}
