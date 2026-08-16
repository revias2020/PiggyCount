import '../../ai/bill_info.dart';
import '../../ai/extraction_context.dart';
import '../../data/app_database.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/tag_repository.dart';
import '../../data/repositories/transaction_repository.dart';

/// 把已确认的 [BillInfo] 匹配分类/标签后写入当前账本。
class BillCreationService {
  BillCreationService({
    required this.categories,
    required this.tags,
    required this.transactions,
    required this.settings,
  });

  final CategoryRepository categories;
  final TagRepository tags;
  final TransactionRepository transactions;
  final SettingsRepository settings;

  Future<AiExtractionContext> buildContext() async {
    final expense = await categories.listByKind('expense');
    final income = await categories.listByKind('income');
    final bundles = await tags.getBundles();

    final expenseNames = expense
        .where((c) => c.parentId != null || !_hasChildren(c.id, expense))
        .map((c) => c.name)
        .toList();
    final incomeNames = income
        .where((c) => c.parentId != null || !_hasChildren(c.id, income))
        .map((c) => c.name)
        .toList();

    return AiExtractionContext(
      expenseCategories: expenseNames,
      incomeCategories: incomeNames,
      tagGroups: [
        for (final b in bundles)
          AiTagGroupHint(
            name: b.group.name,
            kind: b.group.kind,
            tags: [
              for (final t in b.tags)
                AiTagHint(
                  name: t.name,
                  rangeLabel: b.isNumber ? _rangeLabel(t) : null,
                ),
            ],
          ),
      ],
    );
  }

  String? _rangeLabel(Tag t) {
    final min = t.rangeMin;
    final max = t.rangeMax;
    if (min == null) return null;
    if (max == null) return '≥${_fmt(min)}';
    return '${_fmt(min)}≤金额<${_fmt(max)}';
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  bool _hasChildren(int id, List<Category> all) =>
      all.any((c) => c.parentId == id);

  /// 保存一笔；失败返回 null。
  Future<int?> createFromBill({
    required BillInfo bill,
    required int ledgerId,
    String source = 'ai_chat',
  }) async {
    final amount = bill.amount;
    if (amount == null || amount <= 0) return null;

    final type = bill.type == BillType.income ? 'income' : 'expense';
    final cats = await categories.listByKind(type);
    final categoryId = _matchCategory(bill.category, bill.note, cats);
    final tagIds = await _resolveTagIds(
      suggestions: bill.tags,
      amount: amount,
    );

    return transactions.insert(
      ledgerId: ledgerId,
      type: type,
      amount: amount,
      categoryId: categoryId,
      happenedAt: bill.time ?? DateTime.now(),
      note: bill.note,
      tagIds: tagIds,
      source: source,
    );
  }

  int? _matchCategory(
    String? name,
    String? note,
    List<Category> cats,
  ) {
    if (cats.isEmpty) return null;
    final needle = (name ?? '').trim();
    if (needle.isNotEmpty) {
      final exact = cats.where((c) => c.name == needle);
      if (exact.isNotEmpty) return exact.first.id;
      final contains = cats.where(
        (c) => c.name.contains(needle) || needle.contains(c.name),
      );
      if (contains.isNotEmpty) return contains.first.id;
    }
    final hint = '${name ?? ''}${note ?? ''}';
    for (final c in cats) {
      if (hint.contains(c.name)) return c.id;
    }
    final other = cats.where((c) => c.name.contains('其他'));
    if (other.isNotEmpty) return other.first.id;
    return cats.last.id;
  }

  /// 智能选标：数值组按金额落区间；字符串组按建议至多 2 个，可自动建标。
  Future<List<int>> _resolveTagIds({
    required List<SuggestedTag>? suggestions,
    required double amount,
  }) async {
    final allowCreate = await settings.autoGenerateTags();
    final bundles = await tags.getBundles();
    final selected = <int>[];

    for (final bundle in bundles) {
      if (bundle.isNumber) {
        for (final t in bundle.tags) {
          if (TagRepository.amountInRange(amount, t)) {
            selected.add(t.id);
            break;
          }
        }
        continue;
      }

      // 字符串组
      final picked = <int>[];
      for (final s in suggestions ?? const <SuggestedTag>[]) {
        if (picked.length >= 2) break;
        final name = s.name.trim();
        if (name.isEmpty) continue;

        final existing = bundle.tags.where((t) => t.name == name);
        if (existing.isNotEmpty) {
          final id = existing.first.id;
          if (!picked.contains(id)) picked.add(id);
          continue;
        }

        if (!allowCreate) continue;
        final gName = s.groupName?.trim();
        if (gName == null || gName != bundle.group.name) continue;

        try {
          final id = await tags.create(name, groupId: bundle.group.id);
          picked.add(id);
          // 刷新本 bundle 视图用不到：后续同组建议走 create 的 byName 即可
        } catch (_) {
          // 重名或校验失败则跳过
        }
      }
      selected.addAll(picked);
    }

    return selected;
  }
}
