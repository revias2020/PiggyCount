import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

/// 桌面小组件内容类型（本轮仅收支速览）。
enum HWType { glance }

/// 尺寸档：对齐 BeeCount glance 的小 / 中。
enum HWSize { small, medium }

/// 单个「内容类型 + 尺寸」渲染规格。
@immutable
class WidgetSpec {
  const WidgetSpec._({
    required this.type,
    required this.size,
    required this.logicalSize,
    required this.androidClassName,
    required this.imageKey,
  });

  final HWType type;
  final HWSize size;
  final Size logicalSize;
  final String androidClassName;
  final String imageKey;

  /// 小号：约 2×2 格（ADR-023）。
  static const glanceSmall = WidgetSpec._(
    type: HWType.glance,
    size: HWSize.small,
    logicalSize: Size(110, 110),
    androidClassName: 'com.xiaozhu.piggy_count.GlanceSmallWidgetProvider',
    imageKey: 'widget_glance_small',
  );

  /// 中号设计基准（仅兜底 / 内部分配比例）；实渲见 [resolveMediumLogicalSize]（ADR-062）。
  static const glanceMedium = WidgetSpec._(
    type: HWType.glance,
    size: HWSize.medium,
    logicalSize: Size(mediumDesignWidth, mediumDesignHeight),
    androidClassName: 'com.xiaozhu.piggy_count.GlanceMediumWidgetProvider',
    imageKey: 'widget_glance_medium',
  );

  /// 与 Kotlin [WidgetSlotSize.KEY_SLOT_W] / [KEY_SLOT_H] 同键。
  static const mediumSlotWidthKey = 'glance_medium_slot_w';
  static const mediumSlotHeightKey = 'glance_medium_slot_h';

  static const mediumDesignWidth = 364.0;
  static const mediumDesignHeight = 182.0;

  /// 设计稿：浮卡占整高比例（162/182）；上下透明各 10/182。
  static const glanceMediumContentHeight = 162.0;

  /// 浮卡内边距（设计稿 14；相对浮卡 14/162）。
  static const glanceMediumPad = 14.0;

  /// 今日区行高（设计稿 46；相对浮卡 46/162）。
  static const glanceMediumTodayRowHeight = 46.0;

  /// 今日区与柱图区间距（设计稿 12）。
  static const glanceMediumTodayChartGap = 12.0;

  /// 柱图区定高（设计稿 76）。
  static const glanceMediumChartHeight = 76.0;

  static const catalog = <WidgetSpec>[glanceSmall, glanceMedium];

  static const defaultSet = <WidgetSpec>[glanceMedium];

  static double? _asPositiveDouble(dynamic raw) {
    final v = switch (raw) {
      int n => n.toDouble(),
      double n => n,
      _ => null,
    };
    if (v == null || v <= 0) return null;
    return v;
  }

  /// 读取 Kotlin [WidgetSlotSize] 写入的渲图宽高（已 normalize）；无效则回退设计基准。
  static Future<Size> resolveMediumLogicalSize() async {
    try {
      final rawW =
          await HomeWidget.getWidgetData<dynamic>(mediumSlotWidthKey);
      final rawH =
          await HomeWidget.getWidgetData<dynamic>(mediumSlotHeightKey);
      final w = _asPositiveDouble(rawW);
      final h = _asPositiveDouble(rawH);
      if (w != null && h != null) {
        return Size(w, h);
      }
    } catch (e) {
      debugPrint('resolveMediumLogicalSize failed: $e');
    }
    return glanceMedium.logicalSize;
  }

  /// 匹配已安装小组件；短类名与全限定名都认。
  static WidgetSpec? matchInstalled(HomeWidgetInfo info) {
    final cls = info.androidClassName;
    if (cls == null || cls.isEmpty) return null;
    final short = cls.contains('.') ? cls.split('.').last : cls;
    for (final spec in catalog) {
      final targetShort = spec.androidClassName.split('.').last;
      if (cls == spec.androidClassName || short == targetShort) {
        return spec;
      }
    }
    return null;
  }
}
