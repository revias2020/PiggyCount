import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/ai/ai_category_match.dart';
import 'package:piggy_count/ai/extraction_context.dart';
import 'package:piggy_count/ai/prompt_builder.dart';
import 'package:piggy_count/data/app_database.dart';

Category _cat({
  required int id,
  required String name,
  int? parentId,
  int sortOrder = 0,
}) {
  return Category(
    id: id,
    name: name,
    kind: 'expense',
    icon: 'restaurant',
    iconType: 'material',
    parentId: parentId,
    sortOrder: sortOrder,
    syncId: 's$id',
    updatedAt: DateTime(2026),
  );
}

void main() {
  group('AiCategoryMatch', () {
    final cats = <Category>[
      _cat(id: 1, name: '餐饮'),
      _cat(id: 2, name: '午餐', parentId: 1, sortOrder: 1),
      _cat(id: 3, name: '约会', sortOrder: 2),
      _cat(id: 4, name: '吃点好的', parentId: 3, sortOrder: 3),
    ];

    test('复合名命中子类', () {
      expect(AiCategoryMatch.resolve('餐饮-午餐', cats)?.id, 2);
      expect(AiCategoryMatch.resolve('约会-吃点好的', cats)?.id, 4);
    });

    test('裸名仍可命中', () {
      expect(AiCategoryMatch.resolve('午餐', cats)?.id, 2);
      expect(AiCategoryMatch.resolve('餐饮', cats)?.id, 1);
    });

    test('展示用裸名', () {
      expect(AiCategoryMatch.displayName('餐饮-午餐', cats), '午餐');
    });
  });

  test('Prompt 按主类分组并含复合可回写值', () {
    const ctx = AiExtractionContext(
      expenseGroups: [
        AiCategoryGroupHint(
          mainName: '餐饮',
          childNames: ['午餐'],
        ),
        AiCategoryGroupHint(mainName: '交通'),
      ],
    );
    final prompt = const PromptBuilder().build(
      context: ctx,
      inputSource: '用户说：',
      userText: '午饭30',
      now: DateTime(2026, 8, 20, 12),
    );
    expect(prompt, contains('先定主类'));
    expect(prompt, contains('- 餐饮：餐饮、餐饮-午餐'));
    expect(prompt, contains('- 交通：交通'));
  });
}
