import '../../ai/ai_category_match.dart';
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

    return AiExtractionContext(
      expenseGroups: _toGroups(expense),
      incomeGroups: _toGroups(income),
      tagGroups: [
        for (final b in bundles)
          AiTagGroupHint(
            name: b.group.name,
            kind: b.group.kind,
            scope: b.group.scope,
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

  List<AiCategoryGroupHint> _toGroups(List<Category> all) {
    final mains = all.where((c) => c.parentId == null).toList();
    return [
      for (final m in mains)
        AiCategoryGroupHint(
          mainName: m.name,
          childNames: [
            for (final c in all.where((c) => c.parentId == m.id)) c.name,
          ],
        ),
    ];
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

  /// 保存一笔；失败返回 null。
  ///
  /// [source] 须由调用方显式传入（历史取值可含已下线的 `ai_chat`）。
  Future<int?> createFromBill({
    required BillInfo bill,
    required int ledgerId,
    required String source,
  }) async {
    final amount = bill.amount;
    if (amount == null || amount <= 0) return null;

    final type = bill.type == BillType.income ? 'income' : 'expense';
    final cats = await categories.listByKind(type);
    final categoryId = _matchCategory(bill.category, bill.note, cats);
    final tagIds = await _resolveTagIds(
      suggestions: bill.tags,
      amount: amount,
      type: type,
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
    final resolved = AiCategoryMatch.resolve(name, cats);
    if (resolved != null) return resolved.id;
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
    required String type,
  }) async {
    final allowCreate = await settings.autoGenerateTags();
    final bundles = await tags.getBundles();
    final selected = <int>[];

    for (final bundle in bundles) {
      if (!TagGroupScope.matchesType(bundle.group.scope, type)) continue;

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
        } catch (_) {
          // 重名或校验失败则跳过
        }
      }
      selected.addAll(picked);
    }

    return selected;
  }
}
