import '../data/app_database.dart';

/// Prompt 分类消歧标签与回写匹配（ADR-047）。
///
/// 子类在 prompt 中为「主类-子类」；明细/确认展示仍用分类裸名。
class AiCategoryMatch {
  AiCategoryMatch._();

  static String childLabel(String parentName, String childName) =>
      '$parentName-$childName';

  /// 优先精确匹配「主类-子类」，再裸名，再包含；未命中返回 null。
  static Category? resolve(String? raw, List<Category> cats) {
    final needle = (raw ?? '').trim();
    if (needle.isEmpty || cats.isEmpty) return null;

    final byId = {for (final c in cats) c.id: c};
    for (final c in cats) {
      final parentId = c.parentId;
      if (parentId == null) continue;
      final parent = byId[parentId];
      if (parent == null) continue;
      if (needle == childLabel(parent.name, c.name)) return c;
    }

    final exact = cats.where((c) => c.name == needle);
    if (exact.isNotEmpty) return exact.first;

    final contains = cats.where(
      (c) => c.name.contains(needle) || needle.contains(c.name),
    );
    if (contains.isNotEmpty) return contains.first;
    return null;
  }

  /// 确认弹层等：解析为目录中的裸名；未命中则回落原始字符串或「未分类」。
  static String displayName(String? raw, List<Category> cats) {
    final matched = resolve(raw, cats);
    if (matched != null) return matched.name;
    final needle = (raw ?? '').trim();
    return needle.isNotEmpty ? needle : '未分类';
  }
}
