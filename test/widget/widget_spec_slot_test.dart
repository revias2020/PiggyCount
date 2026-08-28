import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/widget/widget_spec.dart';

void main() {
  group('WidgetSpec medium slot layout ratios (ADR-062)', () {
    test('design fallback size', () {
      expect(
        WidgetSpec.glanceMedium.logicalSize,
        const Size(364, 182),
      );
    });

    test('transparent and content split of canvas height', () {
      const h = 200.0;
      final contentH =
          h * (WidgetSpec.glanceMediumContentHeight / WidgetSpec.mediumDesignHeight);
      final padEach = (h - contentH) / 2;
      expect(contentH, closeTo(h * 162 / 182, 0.01));
      expect(padEach, closeTo(h * 10 / 182, 0.01));
      expect(padEach * 2 + contentH, closeTo(h, 0.01));
    });

    test('card inner rows sum to content height', () {
      const contentH = 162.0;
      final pad = contentH * (WidgetSpec.glanceMediumPad / 162);
      final today =
          contentH * (WidgetSpec.glanceMediumTodayRowHeight / 162);
      final gap =
          contentH * (WidgetSpec.glanceMediumTodayChartGap / 162);
      final chart =
          contentH * (WidgetSpec.glanceMediumChartHeight / 162);
      expect(pad * 2 + today + gap + chart, closeTo(contentH, 0.01));
    });
  });
}
