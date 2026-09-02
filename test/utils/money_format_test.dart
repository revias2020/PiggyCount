import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/utils/money_format.dart';

void main() {
  group('formatMoneyScaleCompact', () {
    test('below 1k uses integer', () {
      expect(formatMoneyScaleCompact(0), '0');
      expect(formatMoneyScaleCompact(999.99), '999');
      expect(formatMoneyScaleCompact(88.5), '88');
    });

    test('1k to 1w uses truncated x.xxk', () {
      expect(formatMoneyScaleCompact(1000), '1.00k');
      expect(formatMoneyScaleCompact(3200.5), '3.20k');
      expect(formatMoneyScaleCompact(9999.99), '9.99k');
    });

    test('1w and above uses truncated x.xxw', () {
      expect(formatMoneyScaleCompact(10000), '1.00w');
      expect(formatMoneyScaleCompact(123456), '12.34w');
    });
  });

  group('formatWidgetMoneyCompact', () {
    test('prefixes scale compact with yen', () {
      expect(formatWidgetMoneyCompact(0), '¥0');
      expect(formatWidgetMoneyCompact(999.99), '¥999');
      expect(formatWidgetMoneyCompact(88.5), '¥88');
      expect(formatWidgetMoneyCompact(1000), '¥1.00k');
      expect(formatWidgetMoneyCompact(3200.5), '¥3.20k');
      expect(formatWidgetMoneyCompact(9999.99), '¥9.99k');
      expect(formatWidgetMoneyCompact(10000), '¥1.00w');
      expect(formatWidgetMoneyCompact(123456), '¥12.34w');
    });
  });
}
