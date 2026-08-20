import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../styles/tokens.dart';
import '../utils/money_format.dart';
import 'views/glance_view.dart';
import 'widget_data_service.dart';
import 'widget_spec.dart';

/// 金额隐藏 prefs 与后台就地重渲（ADR-024）。
abstract final class WidgetPrivacy {
  static const hideSmallKey = 'glance_hide_small';
  static const hideMediumKey = 'glance_hide_medium';

  static const cacheTodayExpense = 'glance_cache_today_expense';
  static const cacheTodayIncome = 'glance_cache_today_income';
  static const cacheMonthExpense = 'glance_cache_month_expense';
  static const cacheMonthIncome = 'glance_cache_month_income';
  static const cacheDaysJson = 'glance_cache_days_json';
  static const cacheThemeArgb = 'glance_cache_theme_argb';

  /// 隐私切换时刻（epoch ms）。Kotlin 侧据此跳过紧随其后的主进程全量重渲。
  static const privacyToggledAtKey = 'glance_privacy_toggled_at';

  static Future<bool> isHidden(HWSize size) async {
    final key = size == HWSize.small ? hideSmallKey : hideMediumKey;
    return await HomeWidget.getWidgetData<bool>(key) ?? false;
  }

  static Future<void> saveCache({
    required String todayExpense,
    required String todayIncome,
    required String monthExpense,
    required String monthIncome,
    required String daysJson,
    required Color themeColor,
  }) async {
    await HomeWidget.saveWidgetData(cacheTodayExpense, todayExpense);
    await HomeWidget.saveWidgetData(cacheTodayIncome, todayIncome);
    await HomeWidget.saveWidgetData(cacheMonthExpense, monthExpense);
    await HomeWidget.saveWidgetData(cacheMonthIncome, monthIncome);
    await HomeWidget.saveWidgetData(cacheDaysJson, daysJson);
    await HomeWidget.saveWidgetData(cacheThemeArgb, themeColor.toARGB32());
  }

  /// 切换指定尺寸隐藏态并仅重渲该规格（后台 isolate 可用）。
  ///
  /// 先写 [privacyToggledAtKey]，再渲图 / updateWidget：避免 Provider 收到
  /// UPDATE / OPTIONS_CHANGED 后误发主进程全量刷新（约 1s 后再闪一次）。
  static Future<void> toggleAndRerender(String? sizeParam) async {
    final size = sizeParam == 'small' ? HWSize.small : HWSize.medium;
    final key = size == HWSize.small ? hideSmallKey : hideMediumKey;
    final cur = await HomeWidget.getWidgetData<bool>(key) ?? false;
    await HomeWidget.saveWidgetData(key, !cur);
    await HomeWidget.saveWidgetData(
      privacyToggledAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    await rerenderFromCache(size);
  }

  static Future<void> rerenderFromCache(HWSize size) async {
    final hidden = await isHidden(size);
    final todayExpense =
        await HomeWidget.getWidgetData<String>(cacheTodayExpense) ??
            formatWidgetMoney(0);
    final todayIncome =
        await HomeWidget.getWidgetData<String>(cacheTodayIncome) ??
            formatWidgetMoney(0);
    final monthExpense =
        await HomeWidget.getWidgetData<String>(cacheMonthExpense) ??
            formatWidgetMoneyCompact(0);
    final monthIncome =
        await HomeWidget.getWidgetData<String>(cacheMonthIncome) ??
            formatWidgetMoneyCompact(0);
    final daysJson = await HomeWidget.getWidgetData<String>(cacheDaysJson);
    final days = GlanceWidgetData.parseLast7DaysJson(daysJson);
    final argb = await HomeWidget.getWidgetData<int>(cacheThemeArgb);
    final theme = argb != null ? Color(argb) : PigTokens.primary;

    final spec =
        size == HWSize.small ? WidgetSpec.glanceSmall : WidgetSpec.glanceMedium;
    var logical = spec.logicalSize;
    if (size == HWSize.medium) {
      final w = await HomeWidget.getWidgetData<int>(WidgetSpec.mediumWidthKey);
      final h = await HomeWidget.getWidgetData<int>(WidgetSpec.mediumHeightKey);
      if (w != null && h != null && w > 0 && h > 0) {
        logical = Size(w.toDouble(), h.toDouble());
      }
    }

    final Widget view;
    if (size == HWSize.small) {
      view = GlanceView.small(
        todayExpense: todayExpense,
        monthExpense: monthExpense,
        monthIncome: monthIncome,
        themeColor: theme,
        width: logical.width,
        height: logical.height,
        amountsHidden: hidden,
      );
    } else {
      view = GlanceView.medium(
        todayExpense: todayExpense,
        todayIncome: todayIncome,
        themeColor: theme,
        width: logical.width,
        height: logical.height,
        last7Days: days,
        amountsHidden: hidden,
      );
    }

    await HomeWidget.renderFlutterWidget(
      view,
      key: spec.imageKey,
      logicalSize: logical,
      pixelRatio: 3.0,
    );
    await HomeWidget.updateWidget(qualifiedAndroidName: spec.androidClassName);
  }
}

/// home_widget 后台交互入口。
@pragma('vm:entry-point')
Future<void> widgetInteractivityCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (uri == null) return;
  // piggycount://privacy?size=small|medium
  if (uri.scheme == 'piggycount' && uri.host == 'privacy') {
    await WidgetPrivacy.toggleAndRerender(uri.queryParameters['size']);
  }
}
