import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 使用教程：各功能说明（可展开章节）。
class UsageTutorialPage extends StatelessWidget {
  const UsageTutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: const Text('使用教程')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          for (final s in _tutorialSections)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TutorialExpansion(title: s.$1, body: s.$2),
            ),
        ],
      ),
    );
  }
}

class _TutorialExpansion extends StatelessWidget {
  const _TutorialExpansion({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PigTokens.surface,
      borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                body,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: PigTokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _tutorialSections = <(String, String)>[
  (
    '账本',
    '顶栏点当前账本名可切换账本，并在列表内新建、重命名或删除账本。'
        '记一笔与智能记账都会写入当前账本。「我的」页不提供账本管理入口。',
  ),
  (
    '手动记账',
    '明细页右下角点「记一笔」打开底部弹层：选择支出/收入、金额、分类、标签、备注与时间，保存即可。'
        '新建时备注旁相机可拍照或从相册走识别入账；手动账单本身仍不支持附图。',
  ),
  (
    '智能记账',
    '长按「记一笔」展开扇形：拍照、语音、图片。\n'
        '· 拍照 / 图片：用视觉模型识别支付截图后确认入账。\n'
        '· 语音：系统语音识别转文字，再由文本模型结构化后确认。\n'
        '· 截图自动：在「我的」打开开关；Android 监听相册截图，iOS 需按快捷指令引导配置；进度与结果走通知并自动入账。\n'
        '· 分享入账：系统分享图片到本 App，同样走通知后台识别并自动入账（不进确认页）；点失败通知可看错误说明。',
  ),
  (
    'AI 助手',
    '报表页右侧紫色浮动球进入 AI 账单助手，可分析账单或对话记账。'
        '「我的 → AI 智能助手」关闭后仅隐藏该浮动球，不影响扇形三项智能入口。',
  ),
  (
    'AI 设置',
    '「我的 → AI 设置」：\n'
        '· 服务商管理：配置内置智谱或最多 5 个自定义 OpenAI 兼容服务商（Key、Base URL、文本/视觉模型），可逐项测试连接。\n'
        '· 能力绑定：分别为「文本对话」「图片理解」指定服务商。\n'
        '密钥只保存在本机。',
  ),
  (
    '分类与标签',
    '「我的 → 分类管理」维护支出/收入两套主分类与子分类，可自定义图标。\n'
        '「标签管理」维护标签与标签组；「自动生成标签」打开时，智能记账允许创建新标签。',
  ),
  (
    '报表',
    '报表 Tab 可切换周/月/年/自定义周期，查看汇总、趋势、分类或标签构成、月度对比与单笔排行。'
        '周/月/年点中间文案可打开选择弹层；切换回报表页时会刷新以反映最新账单。',
  ),
  (
    '云服务、同步与数据',
    '「云服务」配置 WebDAV 或 S3；测通后可在「同步」把全部账本以及分类、标签、账单与网盘工作区对齐（先预览再写入；同额同时的疑似重复可保留或合并；不是实时自动同步）。\n'
        '「数据管理」用于本机 CSV 导入导出（导入会生成新的账单身份，不会沿用 CSV 当同步）。导入须带表头，先做列名映射；可打开「AI 智能映射」用文本模型预填列名、分类和标签。写入时屏幕中央显示进度，完成前不能操作。分类管理的导入同样有进度层。'
  ),
  (
    '桌面小组件',
    '「我的 → 桌面小组件」可预览效果并查看添加步骤（目前仅 Android）。\n'
        '系统桌面长按空白处 → 小组件 → 选择「收支速览 · 小」或「收支速览 · 中」。\n'
        '小号整卡点按记支出；中号左侧记收入、右侧记支出。'
        '数字来自当前账本的今日与本月合计，记账保存或回到 App 后会尽快刷新。',
  ),
];
