import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/features/receipt/receipt_printer.dart';

void main() {
  test(
    'DISCOUNT line does not double-count when manualDiscount already '
    'covers the item-level portion (reported bug: MEDIUM EGG 30pc @7.50, '
    'printed SUBTOTAL 225 / DISCOUNT -30 / TOTAL 210 - should be -15)',
    () {
      final receipt = ReceiptData(
        orderId: 2040,
        invoiceNumber: 'RCP-002040',
        customerName: 'Walk In Farmer',
        paymentMethod: 'Cash',
        items: const [
          ReceiptLineItem(
            name: 'MEDIUM EGG - PIECE',
            quantity: 30,
            unitPrice: 7.50,
            total: 210, // gross 225 net of a real 15-peso item-level discount
          ),
        ],
        subtotal: 210, // net subtotal as reported by the backend
        vat: 0,
        discount: 15,
        manualDiscount: 15, // same 15 the item line already accounts for
        couponDiscount: 0,
        loyaltyDiscount: 0,
        total: 210,
        amountTendered: 210,
        change: 0,
        currencySymbol: 'PHP',
        cashierName: 'APRIL JOY TUMANGUIL',
        itemCount: 30,
      );

      final lines = ThermalReceiptLayout(receipt).buildLines();

      final subtotalLine = lines.firstWhere((l) => l.startsWith('SUBTOTAL'));
      final discountLine = lines.firstWhere((l) => l.startsWith('DISCOUNT'));
      final totalLine = lines.firstWhere((l) => l.startsWith('TOTAL'));

      // The item's own discount sub-line still shows the real 15.
      expect(lines, contains('15.00 discount'));

      // SUBTOTAL is the gross amount before any discount.
      expect(subtotalLine, contains('225.00'));

      // Fixed behavior: DISCOUNT should read 15.00, not the old
      // double-counted 30.00.
      expect(discountLine, contains('15.00'));
      expect(discountLine.contains('30.00'), isFalse);

      // TOTAL must reconcile: SUBTOTAL - DISCOUNT == TOTAL.
      expect(totalLine, contains('210.00'));
    },
  );

  test(
    'DISCOUNT line still adds coupon/loyalty on top of the larger of '
    'manual vs item-level discount (those never overlap with either)',
    () {
      final receipt = ReceiptData(
        orderId: 1,
        invoiceNumber: 'INV-000001',
        customerName: 'Walk In Farmer',
        paymentMethod: 'Cash',
        items: const [
          ReceiptLineItem(
            name: 'Sample Item',
            quantity: 1,
            unitPrice: 100,
            total: 90, // 10 item-level discount
          ),
        ],
        subtotal: 75, // 90 - 15 manual discount
        vat: 0,
        discount: 25,
        manualDiscount: 15,
        couponDiscount: 5,
        loyaltyDiscount: 0,
        total: 70,
        amountTendered: 70,
        change: 0,
        currencySymbol: 'PHP',
        cashierName: 'Cashier',
        itemCount: 1,
      );

      final lines = ThermalReceiptLayout(receipt).buildLines();
      final discountLine = lines.firstWhere((l) => l.startsWith('DISCOUNT'));

      // max(manual 15, item 10) + coupon 5 = 20, not 15+10+5=30.
      expect(discountLine, contains('20.00'));
    },
  );
}
