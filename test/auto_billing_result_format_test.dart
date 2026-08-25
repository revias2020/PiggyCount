import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/services/automation/auto_billing_service.dart';

void main() {
  group('formatAutoBillingResultBody', () {
    test('纯成功用已入账合计', () {
      expect(
        formatAutoBillingResultBody(
          success: 3,
          skip: 0,
          fail: 0,
          imagesUnsaved: 0,
          successAmount: 12.5,
        ),
        '已入账 3 笔，合计 ¥12.50',
      );
    });

    test('混桶用三数字且可附整图未入账', () {
      expect(
        formatAutoBillingResultBody(
          success: 2,
          skip: 1,
          fail: 0,
          imagesUnsaved: 1,
        ),
        '成功 2 笔，跳过 1 笔，失败 0 笔，另有 1 张未入账',
      );
    });

    test('仅整图未入账不写三个 0 笔', () {
      expect(
        formatAutoBillingResultBody(
          success: 0,
          skip: 0,
          fail: 0,
          imagesUnsaved: 3,
        ),
        '另有 3 张未入账',
      );
    });

    test('单张整图未入账保留原正文', () {
      expect(
        formatAutoBillingResultBody(
          success: 0,
          skip: 0,
          fail: 0,
          imagesUnsaved: 1,
          singleUnsavedBody: '该图可能不是支付截图',
        ),
        '该图可能不是支付截图',
      );
    });
  });

  group('formatAutoBillingResultTitle', () {
    test('有成功无失败笔 → 自动记账成功', () {
      expect(
        formatAutoBillingResultTitle(
          success: 1,
          skip: 1,
          fail: 0,
          imagesUnsaved: 0,
        ),
        '自动记账成功',
      );
    });

    test('仅跳过 → 记账取消', () {
      expect(
        formatAutoBillingResultTitle(
          success: 0,
          skip: 2,
          fail: 0,
          imagesUnsaved: 0,
        ),
        '记账取消',
      );
    });

    test('点击成功仅看成功笔数', () {
      expect(autoBillingResultClickSuccess(1), isTrue);
      expect(autoBillingResultClickSuccess(0), isFalse);
    });
  });
}
