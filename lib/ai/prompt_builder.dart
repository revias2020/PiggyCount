import 'extraction_context.dart';

/// Prompt 拼装：要求返回 JSON 数组；无账户/转账字段。
class PromptBuilder {
  const PromptBuilder();

  static const String defaultTemplate = '''{{BILL_GUARD}}{{INPUT_SOURCE}}提取记账信息，返回JSON数组。

当前时间：{{CURRENT_TIME}}
当前日期：{{CURRENT_DATE}}

{{USER_TEXT}}

{{CATEGORIES}}
{{TAGS}}

输出格式：
- 始终返回 JSON 数组，即使只有一笔，也包成 [{...}]
- 识别到多笔独立消费/收入时，按时间先后拆成多个对象
- 「AA拆账」「拆开报销」「拼单」等：每个独立支付/收款点算 1 笔
- 同一商家多件商品若为一次性支付，合并为 1 笔
- 同时出现应付与实付时，金额取实付（优惠后）

字段说明：
1. amount: 金额（正数）
2. type: expense 或 income
3. time: ISO8601（YYYY-MM-DDTHH:mm:ss），严禁 null：
   - 明确时刻/日期 → 直接使用（仅时刻则用 {{CURRENT_DATE}} 拼完整时间）
   - 相对日期 → 基于 {{CURRENT_DATE}} 推算（昨天 -1d，前天 -2d 等）
   - 概括时段 → 早上 09:00:00、中午 12:00:00、晚上 19:00:00
   - 未提及时间 → 使用 {{CURRENT_TIME}}
4. note: 备注，必须 ≤15 字；提取商家/店铺名、商品名、用户描述，多段用 "-" 连接并极简（如「雅哈饮品旗舰店」→「雅哈」）；无则 ""
5. category: 从分类列表选择最贴近的名称
6. tags: 可选。字符串组：只选语义相关的已有标签，每组最多 2 个；不相关的组不要选。新标签仅当需要创建时用 {"group":"已有字符串组名","name":"新标签"}；数值组不要填（系统按金额自动落档）。

注意：**如果输入中存在多个时间，请优先采用账单的支付时间作为time**

示例：
"昨天中午跟同事吃饭280，晚上买黑色冲锋衣450" → [{"amount":280,"type":"expense","time":"{{CURRENT_DATE}}T12:00:00","note":"跟同事聚餐","category":"餐饮"},{"amount":450,"type":"expense","time":"{{CURRENT_DATE}}T19:00:00","note":"黑色冲锋衣","category":"购物"}]
"发工资8000" → [{"amount":8000,"type":"income","time":"{{CURRENT_TIME}}","note":"工资","category":"工资"}]
"商户：雅哈饮品旗舰店 商品：生椰拿铁、冰美式 应付36 实付28" → [{"amount":28,"type":"expense","time":"{{CURRENT_TIME}}","note":"雅哈-生椰拿铁-冰美式","category":"餐饮"}]

注意：只返回 JSON 数组，不要解释文字，不要 Markdown 代码块。''';

  /// 截图/图片路径使用的账单过滤段；文本/语音路径传空。
  static const String billGuardForImage =
      '请先判断输入图片是否为支付/收款账单截图。'
      '以下情况通常不属于账单（不仅限于此）：\n'
      '- 电脑/手机桌面截图\n'
      '- 聊天记录、朋友圈等社交页面\n'
      '- 新闻、文章、网页浏览页\n'
      '- 照片、自拍、风景图\n'
      '- 应用主界面、设置页面\n'
      '\n'
      '不是账单则返回 JSON 空数组 []，是账单则继续提取。\n';

  String build({
    required AiExtractionContext context,
    required String inputSource,
    String billGuard = '',
    String userText = '',
    DateTime? now,
  }) {
    final ts = now ?? DateTime.now();
    final currentDate = '${ts.year}-${_pad(ts.month)}-${_pad(ts.day)}';
    final currentTime =
        '${currentDate}T${_pad(ts.hour)}:${_pad(ts.minute)}:${_pad(ts.second)}';

    return defaultTemplate
        .replaceAll('{{BILL_GUARD}}', billGuard)
        .replaceAll('{{INPUT_SOURCE}}', inputSource)
        .replaceAll('{{CURRENT_TIME}}', currentTime)
        .replaceAll('{{CURRENT_DATE}}', currentDate)
        .replaceAll('{{USER_TEXT}}', userText)
        .replaceAll('{{CATEGORIES}}', _categoryHint(context))
        .replaceAll('{{TAGS}}', _tagHint(context));
  }

  String _categoryHint(AiExtractionContext ctx) {
    if (ctx.expenseCategories.isEmpty && ctx.incomeCategories.isEmpty) {
      return '分类列表：\n支出：餐饮、交通、购物、娱乐、居家\n收入：工资、理财、红包';
    }
    final parts = <String>[];
    if (ctx.expenseCategories.isNotEmpty) {
      parts.add('支出：${ctx.expenseCategories.join('、')}');
    }
    if (ctx.incomeCategories.isNotEmpty) {
      parts.add('收入：${ctx.incomeCategories.join('、')}');
    }
    return '分类列表：\n${parts.join('\n')}';
  }

  String _tagHint(AiExtractionContext ctx) {
    if (ctx.tagGroups.isEmpty) return '';
    final lines = <String>['标签组（按组选择；数值组勿手填）：'];
    for (final g in ctx.tagGroups) {
      final kindLabel = g.kind == 'number' ? '数值组' : '字符串组';
      final scopeLabel = switch (g.scope) {
        'expense' => '仅支出',
        'income' => '仅收入',
        _ => '全部',
      };
      if (g.tags.isEmpty) {
        lines.add('- $kindLabel「${g.name}」[$scopeLabel]：（空）');
      } else {
        lines.add(
          '- $kindLabel「${g.name}」[$scopeLabel]：${g.tagLabels.join('、')}',
        );
      }
    }
    return lines.join('\n');
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
