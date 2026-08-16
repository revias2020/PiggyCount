import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/ai/bill_info.dart';
import 'package:piggy_count/ai/json_response_parser.dart';

void main() {
  const parser = JsonResponseParser();

  test('解析 markdown 包裹的 JSON 数组', () {
    const raw = '''
好的，结果如下：
```json
[{"amount":-28,"type":"expense","category":"餐饮","note":"奶茶","time":"2026-08-13T12:00:00"}]
```
''';
    final bills = parser.parse(raw);
    expect(bills.length, 1);
    expect(bills.first.amount, 28);
    expect(bills.first.type, BillType.expense);
    expect(bills.first.category, '餐饮');
  });

  test('金额为 0 的项被丢弃', () {
    final bills = parser.parse('[{"amount":0,"type":"expense"}]');
    expect(bills, isEmpty);
  });
}
