import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart' show HomeWidgetInfo;

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

  /// 中号：固定渲图画布 364×182（对齐 BeeCount Android 2:1；不可拉伸）。
  static const glanceMedium = WidgetSpec._(
    type: HWType.glance,
    size: HWSize.medium,
    logicalSize: Size(364, 182),
    androidClassName: 'com.xiaozhu.piggy_count.GlanceMediumWidgetProvider',
    imageKey: 'widget_glance_medium',
  );

  /// 中号浮卡内容高度；画布内上下透明边各 (182−162)/2 = 10。
  static const glanceMediumContentHeight = 162.0;

  /// 浮卡内边距（含柱图区到底边 = 14）。
  static const glanceMediumPad = 14.0;

  /// 今日区行高（标签 ~16 + 间距 6 + 金额 22×1.05 ≈ 46）。
  static const glanceMediumTodayRowHeight = 46.0;

  /// 今日区与柱图区间距。
  static const glanceMediumTodayChartGap = 12.0;

  /// 柱图区定高：162 − 14 − 46 − 12 − 14 = 76。
  static const glanceMediumChartHeight = 76.0;

  static const catalog = <WidgetSpec>[glanceSmall, glanceMedium];

  static const defaultSet = <WidgetSpec>[glanceMedium];

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
