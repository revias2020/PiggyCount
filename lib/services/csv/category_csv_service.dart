import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../data/repositories/category_repository.dart';
import '../custom_icon_service.dart';

/// 分类导入导出（CSV / zip；兼容 BeeCount 分类包）。
///
/// 导出为 zip：`categories.csv` + `custom_icons/*`
/// CSV 列：`name,kind,icon,sort_order,level,parent_name,icon_type,custom_icon_path`
class CategoryCsvService {
  CategoryCsvService(this._categories, {CustomIconService? icons})
      : _icons = icons ?? CustomIconService();

  final CategoryRepository _categories;
  final CustomIconService _icons;

  static const header =
      'name,kind,icon,sort_order,level,parent_name,icon_type,custom_icon_path';

  /// 导出分类包 zip，返回输出文件路径。
  Future<String> exportZip({
    required String outputPath,
    String? filterKind,
  }) async {
    final csv = await exportCsv(filterKind: filterKind);
    final archive = Archive();
    final csvBytes = utf8.encode(csv);
    archive.addFile(
      ArchiveFile('categories.csv', csvBytes.length, csvBytes),
    );

    final all = await _categories.listAll();
    final list = filterKind == null
        ? all
        : all.where((c) => c.kind == filterKind).toList(growable: false);

    final added = <String>{};
    for (final c in list) {
      if (c.iconType != 'custom' || c.customIconPath == null) continue;
      final rel = c.customIconPath!;
      final name = p.basename(rel);
      if (added.contains(name)) continue;
      final abs = await _icons.resolveIconPath(rel);
      final file = File(abs);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(
        ArchiveFile('custom_icons/$name', bytes.length, bytes),
      );
      added.add(name);
    }

    final encoded = ZipEncoder().encode(archive);
    final out = File(outputPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(encoded, flush: true);
    return outputPath;
  }

  /// 导出 UTF-8（带 BOM）CSV 文本。
  Future<String> exportCsv({String? filterKind}) async {
    final all = await _categories.listAll();
    final byId = {for (final c in all) c.id: c};
    final list = filterKind == null
        ? all
        : all.where((c) => c.kind == filterKind).toList(growable: false);

    final mains = list.where((c) => c.parentId == null).toList()
      ..sort((a, b) {
        final k = a.kind.compareTo(b.kind);
        if (k != 0) return k;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    final children = list.where((c) => c.parentId != null).toList()
      ..sort((a, b) {
        final k = a.kind.compareTo(b.kind);
        if (k != 0) return k;
        final pa = byId[a.parentId]?.sortOrder ?? 0;
        final pb = byId[b.parentId]?.sortOrder ?? 0;
        if (pa != pb) return pa.compareTo(pb);
        return a.sortOrder.compareTo(b.sortOrder);
      });

    final buf = StringBuffer()
      ..write('\uFEFF')
      ..writeln(header);

    for (final c in [...mains, ...children]) {
      final parentName =
          c.parentId == null ? '' : (byId[c.parentId]?.name ?? '');
      final level = c.parentId == null ? 1 : 2;
      final iconType = c.iconType;
      final customPath =
          iconType == 'custom' ? (c.customIconPath ?? '') : '';
      buf.writeln(
        [
          _cell(c.name),
          _cell(c.kind),
          _cell(c.icon ?? 'category'),
          _cell('${c.sortOrder}'),
          _cell('$level'),
          _cell(parentName),
          _cell(iconType),
          _cell(customPath),
        ].join(','),
      );
    }
    return buf.toString();
  }

  Future<CategoryImportResult> importBytes(
    List<int> bytes, {
    required String fileName,
    required String mode,
  }) async {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.zip')) {
      return importZip(bytes, mode: mode);
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    return importText(text, fileName: fileName, mode: mode);
  }

  Future<CategoryImportResult> importText(
    String raw, {
    String fileName = '',
    required String mode,
    Map<String, String> iconPathMap = const {},
  }) async {
    final text = raw.startsWith('\uFEFF') ? raw.substring(1) : raw.trimLeft();
    final lower = fileName.toLowerCase();
    final looksYaml = lower.endsWith('.yaml') ||
        lower.endsWith('.yml') ||
        text.startsWith('#') ||
        (text.contains('categories:') && text.contains('version:'));

    final items = looksYaml ? _parseYamlItems(text) : _parseCsvItems(text);
    return _importItems(items, mode: mode, iconPathMap: iconPathMap);
  }

  /// 导入本应用或 BeeCount 分类 zip。
  Future<CategoryImportResult> importZip(
    List<int> bytes, {
    required String mode,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    final iconMap = <String, String>{}; // archive path / basename -> new rel
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll('\\', '/');
      if (!name.toLowerCase().contains('custom_icons/')) continue;
      final fileName = p.basename(name);
      if (fileName.isEmpty) continue;
      final rel = await _icons.importIconBytes(
        entry.content,
        preferredName: fileName,
      );
      iconMap[name] = rel;
      iconMap['custom_icons/$fileName'] = rel;
      iconMap[fileName] = rel;
    }

    ArchiveFile? csvFile = archive.findFile('categories.csv');
    if (csvFile != null) {
      final csv = utf8.decode(csvFile.content);
      return importText(
        csv,
        fileName: 'categories.csv',
        mode: mode,
        iconPathMap: iconMap,
      );
    }

    ArchiveFile? yamlFile = archive.findFile('categories.yaml');
    if (yamlFile == null) {
      for (final f in archive) {
        if (f.name.toLowerCase().endsWith('categories.yaml')) {
          yamlFile = f;
          break;
        }
      }
    }
    if (yamlFile == null) {
      throw FormatException('无效的分类包：缺少 categories.csv / categories.yaml');
    }
    final yamlContent = utf8.decode(yamlFile.content);
    return importText(
      yamlContent,
      fileName: 'categories.yaml',
      mode: mode,
      iconPathMap: iconMap,
    );
  }

  /// 兼容旧测试名。
  Future<CategoryImportResult> importBeeCountZip(
    List<int> bytes, {
    required String mode,
  }) =>
      importZip(bytes, mode: mode);

  Future<CategoryImportResult> _importItems(
    List<_CategoryImportItem> items, {
    required String mode,
    Map<String, String> iconPathMap = const {},
  }) async {
    if (mode == 'overwrite') {
      await _categories.clearUnused();
    }

    final existing = await _categories.listAll();
    final existingKeys = {
      for (final c in existing) _key(c.name, c.kind),
    };

    final level1 = <_CategoryImportItem>[];
    final level2 = <_CategoryImportItem>[];
    for (final item in items) {
      if (item.level <= 1 ||
          item.parentName == null ||
          item.parentName!.isEmpty) {
        level1.add(item);
      } else {
        level2.add(item);
      }
    }

    var imported = 0;
    var skipped = 0;
    var iconsImported = 0;

    Future<({String iconType, String? customPath, int icons})> resolveIcon(
      _CategoryImportItem item,
    ) async {
      if (item.iconType != 'custom' ||
          item.customIconPath == null ||
          item.customIconPath!.isEmpty) {
        return (iconType: 'material', customPath: null, icons: 0);
      }
      final raw = item.customIconPath!;
      final mapped = iconPathMap[raw] ??
          iconPathMap[p.basename(raw)] ??
          iconPathMap['custom_icons/${p.basename(raw)}'];
      if (mapped != null) {
        return (iconType: 'custom', customPath: mapped, icons: 1);
      }
      // 无图标文件时退回 material
      return (iconType: 'material', customPath: null, icons: 0);
    }

    for (final item in level1) {
      final k = _key(item.name, item.kind);
      if (existingKeys.contains(k)) {
        skipped++;
        continue;
      }
      final icon = await resolveIcon(item);
      await _categories.create(
        name: item.name,
        kind: item.kind,
        icon: item.icon,
        sortOrder: item.sortOrder,
        iconType: icon.iconType,
        customIconPath: icon.customPath,
      );
      existingKeys.add(k);
      imported++;
      iconsImported += icon.icons;
    }

    final updated = await _categories.listAll();
    final keyToId = {
      for (final c in updated) _key(c.name, c.kind): c.id,
    };

    for (final item in level2) {
      final k = _key(item.name, item.kind);
      if (existingKeys.contains(k)) {
        skipped++;
        continue;
      }
      final parentName = item.parentName?.trim() ?? '';
      final parentId =
          parentName.isEmpty ? null : keyToId[_key(parentName, item.kind)];
      if (parentId == null) {
        skipped++;
        continue;
      }
      final icon = await resolveIcon(item);
      await _categories.create(
        name: item.name,
        kind: item.kind,
        parentId: parentId,
        icon: item.icon,
        sortOrder: item.sortOrder,
        iconType: icon.iconType,
        customIconPath: icon.customPath,
      );
      existingKeys.add(k);
      imported++;
      iconsImported += icon.icons;
    }

    return CategoryImportResult(
      imported: imported,
      skipped: skipped,
      iconsImported: iconsImported,
    );
  }

  List<_CategoryImportItem> _parseCsvItems(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) return const [];

    var start = 0;
    final headerCells = _parseRow(lines.first);
    final col = _ColumnIndex.fromHeader(headerCells);
    if (col.hasHeader) start = 1;

    final items = <_CategoryImportItem>[];
    for (var i = start; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final cells = _parseRow(line);
      final name = col.nameOf(cells).trim();
      if (name.isEmpty) continue;
      final kind = _normalizeKind(col.kindOf(cells));
      final icon = col.iconOf(cells).trim();
      final sortOrder = int.tryParse(col.sortOf(cells).trim()) ?? 0;
      final levelRaw = col.levelOf(cells).trim();
      final parentName = col.parentOf(cells).trim();
      final level =
          int.tryParse(levelRaw) ?? (parentName.isEmpty ? 1 : 2);
      final iconType = _normalizeIconType(col.iconTypeOf(cells));
      final customPath = col.customPathOf(cells).trim();
      items.add(
        _CategoryImportItem(
          name: name,
          kind: kind,
          icon: icon.isEmpty ? 'category' : icon,
          sortOrder: sortOrder,
          level: level,
          parentName: parentName.isEmpty ? null : parentName,
          iconType: iconType,
          customIconPath: customPath.isEmpty ? null : customPath,
        ),
      );
    }
    return items;
  }

  List<_CategoryImportItem> _parseYamlItems(String text) {
    final doc = loadYaml(text);
    if (doc is! Map) {
      throw FormatException('无效的分类 YAML');
    }
    final categoriesData = doc['categories'];
    if (categoriesData is! List || categoriesData.isEmpty) {
      return const [];
    }

    final items = <_CategoryImportItem>[];
    for (final raw in categoriesData) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
      final name = (map['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final kind = _normalizeKind((map['kind'] ?? 'expense').toString());
      final icon = (map['icon'] ?? 'category').toString().trim();
      final sortOrder = _asInt(map['sort_order']) ?? 0;
      final parentName = map['parent_name']?.toString().trim();
      final level = _asInt(map['level']) ??
          (parentName == null || parentName.isEmpty ? 1 : 2);
      final iconType = _normalizeIconType(
        (map['icon_type'] ?? 'material').toString(),
      );
      final customPath = map['custom_icon_path']?.toString().trim();
      items.add(
        _CategoryImportItem(
          name: name,
          kind: kind,
          icon: icon.isEmpty ? 'category' : icon,
          sortOrder: sortOrder,
          level: level,
          parentName:
              parentName == null || parentName.isEmpty ? null : parentName,
          iconType: iconType,
          customIconPath:
              customPath == null || customPath.isEmpty ? null : customPath,
        ),
      );
    }
    return items;
  }

  static String _key(String name, String kind) =>
      '${name.trim().toLowerCase()}|$kind';

  static String _normalizeKind(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.contains('income') || s.contains('收')) return 'income';
    return 'expense';
  }

  static String _normalizeIconType(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'custom') return 'custom';
    return 'material';
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
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
}

class CategoryImportResult {
  const CategoryImportResult({
    required this.imported,
    required this.skipped,
    this.iconsImported = 0,
  });

  final int imported;
  final int skipped;
  final int iconsImported;
}

class _CategoryImportItem {
  const _CategoryImportItem({
    required this.name,
    required this.kind,
    required this.icon,
    required this.sortOrder,
    required this.level,
    this.parentName,
    this.iconType = 'material',
    this.customIconPath,
  });

  final String name;
  final String kind;
  final String icon;
  final int sortOrder;
  final int level;
  final String? parentName;
  final String iconType;
  final String? customIconPath;
}

class _ColumnIndex {
  _ColumnIndex({
    required this.name,
    required this.kind,
    required this.icon,
    required this.sort,
    required this.level,
    required this.parent,
    required this.iconType,
    required this.customPath,
    required this.hasHeader,
  });

  final int name;
  final int kind;
  final int icon;
  final int sort;
  final int level;
  final int parent;
  final int iconType;
  final int customPath;
  final bool hasHeader;

  factory _ColumnIndex.fromHeader(List<String> cells) {
    int find(List<String> aliases) {
      for (var i = 0; i < cells.length; i++) {
        final h = cells[i].trim().toLowerCase();
        for (final a in aliases) {
          if (h == a.toLowerCase()) return i;
        }
      }
      return -1;
    }

    final name = find(const ['name', '名称', '分类名', '分类名称']);
    if (name < 0) {
      return _ColumnIndex(
        name: 0,
        kind: 1,
        icon: 2,
        sort: 3,
        level: 4,
        parent: 5,
        iconType: 6,
        customPath: 7,
        hasHeader: false,
      );
    }
    return _ColumnIndex(
      name: name,
      kind: find(const ['kind', '类型', '收支']),
      icon: find(const ['icon', '图标']),
      sort: find(const ['sort_order', 'sort', '排序']),
      level: find(const ['level', '层级', '级别']),
      parent: find(const [
        'parent_name',
        'parent',
        '父分类',
        '主分类',
        '一级分类',
      ]),
      iconType: find(const ['icon_type', '图标类型']),
      customPath: find(const [
        'custom_icon_path',
        'custom_icon',
        '自定义图标',
      ]),
      hasHeader: true,
    );
  }

  String nameOf(List<String> cells) => _at(cells, name);
  String kindOf(List<String> cells) => _at(cells, kind);
  String iconOf(List<String> cells) => _at(cells, icon);
  String sortOf(List<String> cells) => _at(cells, sort);
  String levelOf(List<String> cells) => _at(cells, level);
  String parentOf(List<String> cells) => _at(cells, parent);
  String iconTypeOf(List<String> cells) => _at(cells, iconType);
  String customPathOf(List<String> cells) => _at(cells, customPath);

  static String _at(List<String> cells, int i) {
    if (i < 0 || i >= cells.length) return '';
    return cells[i];
  }
}
