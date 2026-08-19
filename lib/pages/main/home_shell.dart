import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/report_providers.dart';
import '../../providers/tab_index_provider.dart';
import '../../styles/tokens.dart';
import '../../widgets/app_top_bar.dart';
import 'details_page.dart';
import 'mine_page.dart';
import 'report_page.dart';

/// 应用主壳：顶栏 + 三 Tab 内容 + 底部导航。
///
/// 明细 Tab 自绘一体顶栏（ADR-003）；报表 / 我的仍用壳层 AppTopBar。
///
/// ```
/// [明细] 品牌图标+账本+日历+同步+搜索 / 月度汇总 …
/// [报表|我的]
/// 小猪记账          当前账本名 ▾
/// -------------------------------
///            主内容
/// -------------------------------
///    明细  |  报表  |  我的
/// ```
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const _pages = [
    DetailsPage(),
    ReportPage(),
    MinePage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    // ADR-005：账单变更 → 报表过期；再显报表时重拉。
    ref.watch(reportRefreshBinderProvider);

    // 明细 Tab 自绘一体顶栏，隐藏壳层 AppTopBar（ADR-003）。
    final showShellAppBar = index != 0;

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: showShellAppBar ? const AppTopBar() : null,
      body: IndexedStack(
        index: index,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        height: PigTokens.bottomNavHeight + 8,
        selectedIndex: index,
        onDestinationSelected: (i) {
          ref.read(tabIndexProvider.notifier).state = i;
        },
        indicatorColor: PigTokens.primarySoft,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt, color: PigTokens.primary),
            label: '明细',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart, color: PigTokens.primary),
            label: '报表',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: PigTokens.primary),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
