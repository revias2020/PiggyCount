import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_provider.dart';
import '../providers/ledger_session_provider.dart';
import '../styles/tokens.dart';
import '../widget/widget_manager.dart';

const _widgetChannel = MethodChannel('com.xiaozhu.piggy_count/widget');

/// 触发桌面小组件重渲（记账保存 / 回前台 / 启动等）。
Future<void> updateAppWidget(WidgetRef ref, {bool warmUp = false}) async {
  if (!Platform.isAndroid) return;
  final ledgerId = ref.read(currentLedgerIdProvider);
  final stats = ref.read(statisticsRepositoryProvider);
  await WidgetManager.instance.updateAllWidgets(
    stats: stats,
    ledgerId: ledgerId,
    themeColor: PigTokens.primary,
    warmUpAllSpecs: warmUp,
  );
}

/// 监听生命周期：回前台刷新；进程内存活时排到本地 0:00 尽力刷新；
/// 原生添加/改尺寸时进程内重渲（ADR-023）。
class WidgetRefreshHost extends ConsumerStatefulWidget {
  const WidgetRefreshHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WidgetRefreshHost> createState() => _WidgetRefreshHostState();
}

class _WidgetRefreshHostState extends ConsumerState<WidgetRefreshHost>
    with WidgetsBindingObserver {
  Timer? _midnightTimer;
  Timer? _nativeRefreshDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindNativeRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await updateAppWidget(ref, warmUp: true);
      _scheduleMidnight();
    });
  }

  void _bindNativeRefresh() {
    if (!Platform.isAndroid) return;
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method != 'onWidgetRefresh') return;
      _nativeRefreshDebounce?.cancel();
      _nativeRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        updateAppWidget(ref);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _nativeRefreshDebounce?.cancel();
    if (Platform.isAndroid) {
      _widgetChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      updateAppWidget(ref);
      _scheduleMidnight();
    }
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    if (!Platform.isAndroid) return;
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    final delay = next.difference(now) + const Duration(seconds: 2);
    _midnightTimer = Timer(delay, () async {
      await updateAppWidget(ref);
      if (mounted) _scheduleMidnight();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int?>(currentLedgerIdProvider, (prev, next) {
      if (prev != next) {
        updateAppWidget(ref);
      }
    });
    return widget.child;
  }
}
