import 'dart:async' show Completer;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../data/repositories/statistics_repository.dart';
import '../styles/tokens.dart';
import 'views/glance_view.dart';
import '../utils/money_format.dart';
import 'widget_data_service.dart';
import 'widget_privacy.dart';
import 'widget_spec.dart';

/// 渲染并刷新已安装的桌面小组件（本轮仅 Android 收支速览）。
class WidgetManager {
  WidgetManager._();
  static final WidgetManager instance = WidgetManager._();

  Future<void> _renderGate = Future.value();

  static const _lastDayKey = 'glance_last_render_day';

  /// [warmUpAllSpecs]：启动时预渲染小+中，避免用户刚添加时空白。
  Future<void> updateAllWidgets({
    required StatisticsRepository stats,
    required int? ledgerId,
    Color themeColor = PigTokens.primary,
    bool warmUpAllSpecs = false,
  }) async {
    if (!Platform.isAndroid) return;

    final prev = _renderGate;
    final gate = Completer<void>();
    _renderGate = gate.future;
    await prev;
    try {
      final specs = warmUpAllSpecs
          ? WidgetSpec.catalog
          : await _resolveSpecsToRender();
      if (specs.isEmpty) return;

      final glance = ledgerId == null
          ? GlanceWidgetData.empty
          : await WidgetDataService.gatherGlance(
              stats: stats,
              ledgerId: ledgerId,
            );

      final todayExpense = formatWidgetMoney(glance.todayExpenseTotal);
      final todayIncome = formatWidgetMoney(glance.todayIncomeTotal);
      final monthExpense =
          formatWidgetMoneyCompact(glance.monthExpenseTotal);
      final monthIncome =
          formatWidgetMoneyCompact(glance.monthIncomeTotal);
      final daysJson = glance.last7DaysJson();

      await WidgetPrivacy.saveCache(
        todayExpense: todayExpense,
        todayIncome: todayIncome,
        monthExpense: monthExpense,
        monthIncome: monthIncome,
        daysJson: daysJson,
        themeColor: themeColor,
      );

      final hideSmall = await WidgetPrivacy.isHidden(HWSize.small);
      final hideMedium = await WidgetPrivacy.isHidden(HWSize.medium);

      for (final spec in specs) {
        try {
          await _renderGlance(
            spec,
            themeColor: themeColor,
            todayExpense: todayExpense,
            todayIncome: todayIncome,
            monthExpense: monthExpense,
            monthIncome: monthIncome,
            last7Days: glance.last7Days,
            amountsHidden: spec.size == HWSize.small ? hideSmall : hideMedium,
          );
        } catch (e, st) {
          debugPrint('WidgetManager render ${spec.imageKey} failed: $e\n$st');
        }
      }

      final touched = <String>{};
      for (final spec in specs) {
        if (!touched.add(spec.androidClassName)) continue;
        try {
          await HomeWidget.updateWidget(
            qualifiedAndroidName: spec.androidClassName,
          );
        } catch (e) {
          debugPrint('HomeWidget.updateWidget failed: $e');
        }
      }

      final now = DateTime.now();
      final dayKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await HomeWidget.saveWidgetData<String>(_lastDayKey, dayKey);
    } finally {
      gate.complete();
    }
  }

  Future<List<WidgetSpec>> _resolveSpecsToRender() async {
    try {
      final infos = await HomeWidget.getInstalledWidgets();
      final matched = <WidgetSpec>[];
      for (final info in infos) {
        final spec = WidgetSpec.matchInstalled(info);
        if (spec != null && !matched.contains(spec)) {
          matched.add(spec);
        }
      }
      return matched;
    } catch (e) {
      debugPrint('getInstalledWidgets failed: $e');
      return WidgetSpec.defaultSet;
    }
  }

  Future<void> _renderGlance(
    WidgetSpec spec, {
    required Color themeColor,
    required String todayExpense,
    required String todayIncome,
    required String monthExpense,
    required String monthIncome,
    required List<GlanceDayPoint> last7Days,
    required bool amountsHidden,
  }) async {
    final size = spec.logicalSize;
    final Widget view;
    if (spec.size == HWSize.small) {
      view = GlanceView.small(
        todayExpense: todayExpense,
        monthExpense: monthExpense,
        monthIncome: monthIncome,
        themeColor: themeColor,
        width: size.width,
        height: size.height,
        amountsHidden: amountsHidden,
      );
    } else {
      view = GlanceView.medium(
        todayExpense: todayExpense,
        todayIncome: todayIncome,
        themeColor: themeColor,
        width: size.width,
        height: size.height,
        last7Days: last7Days,
        amountsHidden: amountsHidden,
      );
    }

    await HomeWidget.renderFlutterWidget(
      view,
      key: spec.imageKey,
      logicalSize: size,
      pixelRatio: 3.0,
    );
  }
}
