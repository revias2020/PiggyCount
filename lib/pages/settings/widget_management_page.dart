import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../styles/tokens.dart';
import '../../widget/views/glance_view.dart';
import '../../widget/widget_data_service.dart';

/// 「我的 → 桌面小组件」：示意预览 + 添加说明。
class WidgetManagementPage extends StatelessWidget {
  const WidgetManagementPage({super.key});

  static List<GlanceDayPoint> get _demoDays {
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 6));
    const labels = ['周二', '周三', '周四', '周五', '周六', '周日', '今日'];
    const expenses = [20.0, 0.0, 45.0, 200.0, 80.0, 0.0, 200.0];
    const incomes = [0.0, 0.0, 0.0, 0.0, 120.0, 0.0, 0.0];
    return List.generate(7, (i) {
      final day = start.add(Duration(days: i));
      return GlanceDayPoint(
        day: day,
        label: i == 6 ? '今日' : labels[i],
        expense: expenses[i],
        income: incomes[i],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(title: const Text('桌面小组件')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const Text(
            '组件库',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '以下为示意效果，桌面上的数字来自当前账本真实数据。',
            style: TextStyle(fontSize: 13, color: PigTokens.textSecondary),
          ),
          const SizedBox(height: 16),
          _PreviewCard(
            title: '收支速览 · 中',
            child: ColoredBox(
              color: const Color(0xFF8B3A3A),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FittedBox(
                  child: GlanceView.medium(
                    todayExpense: '¥200.00',
                    todayIncome: '¥0.00',
                    themeColor: PigTokens.primary,
                    width: 360,
                    height: 152,
                    last7Days: _demoDays,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _PreviewCard(
            title: '收支速览 · 小',
            child: ColoredBox(
              color: const Color(0xFF8B3A3A),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GlanceView.small(
                    todayExpense: '¥88.50',
                    monthExpense: '¥3,200.50',
                    monthIncome: '¥8,000.00',
                    themeColor: PigTokens.primary,
                    width: 110,
                    height: 110,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '如何添加到桌面',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const _Bullet(
            '长按桌面空白处 → 小组件 / 微件 → 找到「小猪记账」。',
          ),
          const _Bullet(
            '选择「收支速览 · 小」或「收支速览 · 中」放到桌面。',
          ),
          const _Bullet(
            '中号：点今日支出/收入进明细；点「+」记支出；点柱图打开报表自定义近 7 天；点眼睛隐藏金额。',
          ),
          const _Bullet(
            '小号：点卡片记支出；点右侧眼睛隐藏金额（与中号开关相互独立）。',
          ),
          const _Bullet(
            '数字约每 30 分钟由系统刷新；记账保存、回到 App，或添加小组件时'
            '（App 仍在运行）会尽快更新。跨日后也会尽量在本地 0 点附近更新。',
          ),
          if (!Platform.isAndroid) ...[
            const SizedBox(height: 12),
            const Text(
              '本版本桌面小组件仅支持 Android，iOS 稍后提供。',
              style: TextStyle(fontSize: 13, color: PigTokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PigTokens.surface,
        borderRadius: BorderRadius.circular(PigTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('· ', style: TextStyle(fontSize: 13, height: 1.5)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: PigTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
