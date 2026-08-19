import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/repositories/tag_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/ledger_session_provider.dart';
import '../../services/csv/csv_ai_mapping_service.dart';
import '../../services/csv/csv_import_mapping.dart';
import '../../services/csv/csv_table.dart';
import '../../styles/tokens.dart';
import '../../widgets/import_progress_layer.dart';
import 'data_manage_page.dart';
import 'import_mapping_pickers.dart';

enum _MapStep { columns, categories, tags }

/// 数据导入映射向导。页内无 AI 开关。
///
/// 分类 / 标签 map 三态（ADR-043）：无键=自动；键且 null=不映射；键且 id=对到目标。
class ImportMappingPage extends ConsumerStatefulWidget {
  const ImportMappingPage({
    super.key,
    required this.table,
    required this.aiEnabled,
  });

  final CsvTable table;
  final bool aiEnabled;

  @override
  ConsumerState<ImportMappingPage> createState() => _ImportMappingPageState();
}

class _ImportMappingPageState extends ConsumerState<ImportMappingPage> {
  late ColumnMapping _columns;
  final Map<CategoryMapKey, int?> _categoryMap = {};
  final Map<String, int?> _tagMap = {};
  List<Category> _catalog = const [];
  List<TagGroupBundle> _bundles = const [];

  _MapStep _step = _MapStep.columns;
  bool _llmBusy = false;
  String? _llmError;
  String? _columnFp;
  String? _categoryFp;

  final _ai = CsvAiMappingService();

  List<_MapStep> get _steps {
    if (!widget.aiEnabled) return const [_MapStep.columns];
    final steps = <_MapStep>[_MapStep.columns];
    if (CsvImportMapping.uniqueCategoryKeys(widget.table, _columns)
        .isNotEmpty) {
      steps.add(_MapStep.categories);
    }
    if (CsvImportMapping.uniqueTagNames(widget.table, _columns).isNotEmpty) {
      steps.add(_MapStep.tags);
    }
    return steps;
  }

  @override
  void initState() {
    super.initState();
    _columns = ColumnMapping.guess(widget.table.headers);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final cats = ref.read(categoryRepositoryProvider);
    final tagRepo = ref.read(tagRepositoryProvider);
    final catalog = await cats.listAll();
    final bundles = await tagRepo.getBundles();
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _bundles = bundles;
    });
    if (widget.aiEnabled) {
      await _runColumnLlm();
    }
  }

  Future<void> _runColumnLlm() async {
    setState(() {
      _llmBusy = true;
      _llmError = null;
    });
    try {
      final next = await _ai.suggestColumns(
        table: widget.table,
        current: _columns,
      );
      if (!mounted) return;
      setState(() {
        _columns = next;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _llmError = '列名映射预填失败：$e');
    } finally {
      if (mounted) setState(() => _llmBusy = false);
    }
  }

  Future<void> _runCategoryLlm() async {
    final keys =
        CsvImportMapping.uniqueCategoryKeys(widget.table, _columns);
    if (keys.isEmpty) return;
    setState(() {
      _llmBusy = true;
      _llmError = null;
    });
    try {
      final suggested = await _ai.suggestCategories(
        keys: keys,
        catalog: _catalog,
      );
      if (!mounted) return;
      setState(() {
        _categoryMap
          ..clear()
          ..addAll(suggested);
        _columnFp = _columns.fingerprint();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _llmError = '分类映射预填失败：$e');
      // 失败仍记下指纹，避免卡住重复调用；用户可点重试或手改后继续。
      _columnFp = _columns.fingerprint();
    } finally {
      if (mounted) setState(() => _llmBusy = false);
    }
  }

  Future<void> _runTagLlm() async {
    final names = CsvImportMapping.uniqueTagNames(widget.table, _columns);
    if (names.isEmpty) return;
    setState(() {
      _llmBusy = true;
      _llmError = null;
    });
    try {
      final suggested = await _ai.suggestTags(
        names: names,
        bundles: _bundles,
      );
      if (!mounted) return;
      setState(() {
        _tagMap
          ..clear()
          ..addAll(suggested);
        _categoryFp = _categoryFingerprint();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _llmError = '标签映射预填失败：$e');
      _categoryFp = _categoryFingerprint();
    } finally {
      if (mounted) setState(() => _llmBusy = false);
    }
  }

  String _categoryFingerprint() {
    final keys = CsvImportMapping.uniqueCategoryKeys(widget.table, _columns);
    return keys.map((k) {
      if (!_categoryMap.containsKey(k)) return '${k.kind}:${k.primary}:${k.secondary}:auto';
      final id = _categoryMap[k];
      return '${k.kind}:${k.primary}:${k.secondary}:${id ?? 'ignore'}';
    }).join('|');
  }

  Future<void> _goNext() async {
    if (_llmBusy) return;
    final steps = _steps;
    final idx = steps.indexOf(_step);
    if (idx < 0) return;
    if (idx == steps.length - 1) {
      await _startImport();
      return;
    }
    final next = steps[idx + 1];
    if (next == _MapStep.categories) {
      if (_columnFp != _columns.fingerprint()) {
        await _runCategoryLlm();
        if (!mounted) return;
      }
    } else if (next == _MapStep.tags) {
      if (_categoryFp != _categoryFingerprint()) {
        await _runTagLlm();
        if (!mounted) return;
      }
    }
    if (!mounted) return;
    setState(() {
      _step = next;
      _llmError = null;
    });
  }

  void _goBack() {
    if (_llmBusy) return;
    final steps = _steps;
    final idx = steps.indexOf(_step);
    if (idx <= 0) return;
    setState(() => _step = steps[idx - 1]);
  }

  Future<void> _startImport() async {
    if (!_columns.isReady) return;
    final ledgerId = ref.read(currentLedgerIdProvider);
    if (ledgerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前账本未就绪，请稍后重试')),
      );
      return;
    }
    try {
      final n = await showImportProgressLayer<int>(
        context: context,
        title: '正在导入账单',
        task: (report) {
          return ref.read(csvServiceProvider).importMapped(
                table: widget.table,
                columns: _columns,
                defaultLedgerId: ledgerId,
                categoryMap: Map.of(_categoryMap),
                tagMap: Map.of(_tagMap),
                onProgress: report,
              );
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(n);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  void _retryLlm() {
    if (_step == _MapStep.columns) {
      _runColumnLlm();
    } else if (_step == _MapStep.categories) {
      _columnFp = null;
      _runCategoryLlm();
    } else {
      _categoryFp = null;
      _runTagLlm();
    }
  }

  Future<void> _openColumnPicker(CsvImportField field) async {
    final headers = widget.table.headers;
    final current = _columns[field];
    final picked = await showImportColumnPickerSheet(
      context: context,
      title: '选择列：${field.label}',
      headers: headers,
      current: current != null && headers.contains(current) ? current : null,
      allowUnmapped: !field.required,
    );
    if (!mounted || picked == null) return;
    setState(() {
      switch (picked) {
        case ImportColumnPickUnmapped():
          _columns[field] = null;
        case ImportColumnPickHeader(:final header):
          _columns[field] = header;
      }
    });
  }

  Future<void> _openCategoryPicker(CategoryMapKey key) async {
    final options = _catalog.where((c) => c.kind == key.kind).toList();
    final isIgnore =
        _categoryMap.containsKey(key) && _categoryMap[key] == null;
    final selectedId = isIgnore ? null : _categoryMap[key];
    final picked = await showImportCategoryPickerSheet(
      context: context,
      title: key.display,
      catalog: options,
      selectedId: selectedId,
      isIgnore: isIgnore,
    );
    if (!mounted || picked == null) return;
    setState(() {
      switch (picked) {
        case ImportIdPickAuto():
          _categoryMap.remove(key);
        case ImportIdPickIgnore():
          _categoryMap[key] = null;
        case ImportIdPickMapped(:final id):
          _categoryMap[key] = id;
      }
    });
  }

  Future<void> _openTagPicker(String name) async {
    final isIgnore = _tagMap.containsKey(name) && _tagMap[name] == null;
    final selectedId = isIgnore ? null : _tagMap[name];
    final picked = await showImportTagPickerSheet(
      context: context,
      title: name,
      bundles: _bundles,
      selectedId: selectedId,
      isIgnore: isIgnore,
    );
    if (!mounted || picked == null) return;
    setState(() {
      switch (picked) {
        case ImportIdPickAuto():
          _tagMap.remove(name);
        case ImportIdPickIgnore():
          _tagMap[name] = null;
        case ImportIdPickMapped(:final id):
          _tagMap[name] = id;
      }
    });
  }

  String _columnSummary(CsvImportField field) {
    final current = _columns[field];
    final headers = widget.table.headers;
    if (current != null && headers.contains(current)) return current;
    if (field.required) return '请选择';
    return '不映射';
  }

  String _categorySummary(CategoryMapKey key) {
    if (!_categoryMap.containsKey(key)) return '自动';
    final id = _categoryMap[key];
    if (id == null) return '忽略';
    final hit = _catalog.where((c) => c.id == id);
    if (hit.isEmpty) return '忽略';
    return CsvImportMapping.labelFor(hit.first, _catalog);
  }

  String _tagSummary(String name) {
    if (!_tagMap.containsKey(name)) return '自动';
    final id = _tagMap[name];
    if (id == null) return '忽略';
    for (final b in _bundles) {
      for (final t in b.tags) {
        if (t.id == id) return '${b.group.name} / ${t.name}';
      }
    }
    return '忽略';
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _MapStep.columns => '列名映射',
      _MapStep.categories => '分类映射',
      _MapStep.tags => '标签映射',
    };
    final steps = _steps;
    final idx = steps.indexOf(_step);
    final isLast = idx == steps.length - 1;
    final canNext = _columns.isReady && !_llmBusy;

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          if (_llmBusy)
            const LinearProgressIndicator(minHeight: 2, color: PigTokens.primary),
          if (_llmError != null)
            Material(
              color: const Color(0xFFFFF1F0),
              child: ListTile(
                dense: true,
                title: Text(
                  _llmError!,
                  style: const TextStyle(fontSize: 13, color: PigTokens.danger),
                ),
                trailing: TextButton(
                  onPressed: _llmBusy ? null : _retryLlm,
                  child: const Text('重试'),
                ),
              ),
            ),
          Expanded(
            child: AbsorbPointer(
              absorbing: _llmBusy,
              child: ListView(
                padding: const EdgeInsets.all(PigTokens.spaceLg),
                children: [
                  if (widget.aiEnabled && _llmBusy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: PigTokens.spaceMd),
                      child: Text(
                        '正在用 AI 预填…',
                        style: TextStyle(
                          fontSize: 13,
                          color: PigTokens.textSecondary,
                        ),
                      ),
                    ),
                  if (_step == _MapStep.columns) ..._buildColumns(),
                  if (_step == _MapStep.categories) ..._buildCategories(),
                  if (_step == _MapStep.tags) ..._buildTags(),
                  const SizedBox(height: PigTokens.spaceLg),
                  const Text(
                    '样例',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: PigTokens.spaceSm),
                  _buildPreview(),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  if (idx > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _llmBusy ? null : _goBack,
                        child: const Text('上一步'),
                      ),
                    ),
                  if (idx > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: canNext ? _goNext : null,
                      child: Text(isLast ? '开始导入' : '下一步'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildColumns() {
    return [
      const Text(
        '把 CSV 列对到账单字段。日期时间、金额必须映射。类型未映射则整批当支出；账本名未映射则写入当前账本，没有的账本会新建。',
        style: TextStyle(fontSize: 13, color: PigTokens.textSecondary),
      ),
      const SizedBox(height: PigTokens.spaceMd),
      for (final field in CsvImportField.values) _mapTile(
        label: field.required ? '${field.label}（必填）' : field.label,
        value: _columnSummary(field),
        onTap: () => _openColumnPicker(field),
      ),
    ];
  }

  List<Widget> _buildCategories() {
    final keys =
        CsvImportMapping.uniqueCategoryKeys(widget.table, _columns);
    return [
      const Text(
        '点开后用分类网格选择本机分类。自动：精准匹配，没有则新建；不映射：不指定账单分类类别（摘要显示「忽略」）。',
        style: TextStyle(fontSize: 13, color: PigTokens.textSecondary),
      ),
      const SizedBox(height: PigTokens.spaceMd),
      for (final key in keys) _mapTile(
        label: key.display,
        value: _categorySummary(key),
        onTap: () => _openCategoryPicker(key),
      ),
    ];
  }

  List<Widget> _buildTags() {
    final names = CsvImportMapping.uniqueTagNames(widget.table, _columns);
    return [
      const Text(
        '点开后按组选择本机标签（单选）。自动：精准匹配，没有则新建；不映射：不挂该标签（摘要显示「忽略」）。',
        style: TextStyle(fontSize: 13, color: PigTokens.textSecondary),
      ),
      const SizedBox(height: PigTokens.spaceMd),
      for (final name in names) _mapTile(
        label: name,
        value: _tagSummary(name),
        onTap: () => _openTagPicker(name),
      ),
    ];
  }

  Widget _mapTile({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PigTokens.spaceSm),
      child: Material(
        color: PigTokens.surface,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PigTokens.radiusCard),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: const Icon(Icons.chevron_right, size: 20),
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                color: PigTokens.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final tagNames = <int, String>{
      for (final b in _bundles)
        for (final t in b.tags) t.id: t.name,
    };
    final existingTagByName = <String, int>{
      for (final b in _bundles)
        for (final t in b.tags) t.name: t.id,
    };
    final rows = CsvImportMapping.preview(
      table: widget.table,
      columns: _columns,
      categoryMap: _categoryMap,
      tagMap: _tagMap,
      catalog: _catalog,
      tagNamesById: tagNames,
      existingTagByName: existingTagByName,
    );
    if (rows.isEmpty) {
      return const Text(
        '没有可预览的行',
        style: TextStyle(fontSize: 13, color: PigTokens.textTertiary),
      );
    }
    return Material(
      color: PigTokens.surface,
      borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columns: const [
            DataColumn(label: Text('日期')),
            DataColumn(label: Text('金额')),
            DataColumn(label: Text('类型')),
            DataColumn(label: Text('分类')),
            DataColumn(label: Text('标签')),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                cells: [
                  DataCell(Text(r.happenedAt)),
                  DataCell(Text(r.amount)),
                  DataCell(Text(r.type)),
                  DataCell(Text(r.category)),
                  DataCell(Text(r.tags)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
