import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/utils/details_month_bounds.dart';

void main() {
  group('DetailsMonthBounds', () {
    test('shiftMonth respects latest month', () {
      final now = DateTime.now();
      final current = DateTime(now.year, now.month);
      expect(DetailsMonthBounds.shiftMonth(current, 1), isNull);
    });

    test('shiftMonth steps to previous month', () {
      final now = DateTime.now();
      final current = DateTime(now.year, now.month);
      final prev = DetailsMonthBounds.shiftMonth(current, -1);
      expect(prev, DateTime(now.year, now.month - 1));
    });

    test('isFutureMonth flags months after current', () {
      final now = DateTime.now();
      if (now.month < 12) {
        expect(
          DetailsMonthBounds.isFutureMonth(now.year, now.month + 1),
          isTrue,
        );
      }
      expect(
        DetailsMonthBounds.isFutureMonth(now.year, now.month),
        isFalse,
      );
    });
  });
}
