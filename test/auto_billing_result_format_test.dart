import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/services/automation/auto_billing_service.dart';

void main() {
  group('formatAutoBillingResultBody', () {
    test('纯成功', () {
      expect(
        formatAutoBillingResultBody(
          success: 3,
          skip: 0,
          failImages: 0,
          blocked: 0,
          successAmount: 12.5,
        ),
        '入账 3 笔（¥12.50）',
      );
    });

    test('混桶省略 0，阻塞用另有', () {
      expect(
        formatAutoBillingResultBody(
          success: 2,
          skip: 1,
          failImages: 1,
          blocked: 1,
          successAmount: 35,
        ),
        '入账 2 笔（¥35.00），跳过 1 笔，失败 1 张；另有 1 张阻塞，打开 App 后继续',
      );
    });

    test('纯失败张', () {
      expect(
        formatAutoBillingResultBody(
          success: 0,
          skip: 0,
          failImages: 3,
          blocked: 0,
        ),
        '失败 3 张',
      );
    });

    test('纯阻塞不加另有', () {
      expect(
        formatAutoBillingResultBody(
          success: 0,
          skip: 0,
          failImages: 0,
          blocked: 1,
        ),
        '1 张阻塞，打开 App 后继续',
      );
    });

    test('batchNote 附加', () {
      expect(
        formatAutoBillingResultBody(
          success: 1,
          skip: 0,
          failImages: 0,
          blocked: 0,
          successAmount: 1,
          batchNote: '已截取前 9 张',
        ),
        '入账 1 笔（¥1.00）（已截取前 9 张）',
      );
    });
  });

  group('formatAutoBillingResultTitle', () {
    test('固定识别结果', () {
      expect(formatAutoBillingResultTitle(), '识别结果');
    });
  });

  group('autoBillingResultClickSuccess', () {
    test('无失败张走明细，有失败张走 Dialog', () {
      expect(autoBillingResultClickSuccess(0), isTrue);
      expect(autoBillingResultClickSuccess(1), isFalse);
    });
  });
}
