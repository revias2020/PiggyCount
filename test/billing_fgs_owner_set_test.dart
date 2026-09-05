import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/services/platform/foreground_billing_bridge.dart';

void main() {
  group('BillingFgsOwnerSet', () {
    test('acquire/release 空才该 stop', () {
      final o = BillingFgsOwnerSet();
      expect(o.acquire(BillingFgsOwner.assoc), isTrue);
      expect(o.acquire(BillingFgsOwner.share), isFalse);
      expect(o.contains(BillingFgsOwner.assoc), isTrue);
      expect(o.contains(BillingFgsOwner.share), isTrue);
      expect(o.release(BillingFgsOwner.assoc), isFalse);
      expect(o.isEmpty, isFalse);
      expect(o.release(BillingFgsOwner.share), isTrue);
      expect(o.isEmpty, isTrue);
    });

    test('重复 acquire 同 owner 仍单槽', () {
      final o = BillingFgsOwnerSet();
      o.acquire(BillingFgsOwner.batch);
      o.acquire(BillingFgsOwner.batch);
      expect(o.snapshot, {BillingFgsOwner.batch});
      expect(o.release(BillingFgsOwner.batch), isTrue);
    });

    test('clear 后为空', () {
      final o = BillingFgsOwnerSet();
      o.acquire(BillingFgsOwner.retry);
      o.acquire(BillingFgsOwner.share);
      o.clear();
      expect(o.isEmpty, isTrue);
    });
  });
}
