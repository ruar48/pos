import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/features/receipt/receipt_printer.dart';
import 'package:myfinalpos/features/transactions/transaction_model.dart';
import 'package:myfinalpos/features/transactions/transaction_service.dart';

/// INV-013507 as the POS checkout built it: three item discounts totalling
/// 6,480 plus a separate 3,720 order-level manual discount.
ReceiptData _inv013507Checkout() => ReceiptData(
      orderId: 13507,
      invoiceNumber: 'INV-013507',
      customerName: 'Walk In Farmer',
      paymentMethod: 'Cash',
      items: const [
        ReceiptLineItem(
          name: 'AGWAY CARTAP - 100 GRAMS',
          quantity: 120,
          unitPrice: 120,
          total: 10680, // 14,400 less a 3,720 item discount
        ),
        ReceiptLineItem(
          name: 'LAUDA - 1000 ML',
          quantity: 12,
          unitPrice: 650,
          total: 6120, // 7,800 less 1,680
        ),
        ReceiptLineItem(
          name: 'ULTRACRON - 1000 ML',
          quantity: 12,
          unitPrice: 600,
          total: 6120, // 7,200 less 1,080
        ),
      ],
      subtotal: 19200, // net of item AND manual discounts, as checkout sends
      vat: 0,
      discount: 3720,
      manualDiscount: 3720, // order-level only
      couponDiscount: 0,
      loyaltyDiscount: 0,
      total: 19200,
      amountTendered: 19500,
      change: 300,
      currencySymbol: 'PHP',
      cashierName: 'HASMIN',
      itemCount: 144,
    );

void main() {
  test(
    'DISCOUNT includes a manual discount alongside item discounts '
    '(reported bug: INV-013507 printed SUBTOTAL 25,680 / DISCOUNT -6,480 - '
    'the 3,720 manual discount was dropped)',
    () {
      final lines = ThermalReceiptLayout(_inv013507Checkout()).buildLines();

      final subtotalLine = lines.firstWhere((l) => l.startsWith('SUBTOTAL'));
      final discountLine = lines.firstWhere((l) => l.startsWith('DISCOUNT'));
      final totalLine = lines.firstWhere((l) => l.startsWith('TOTAL'));

      // Gross 29,400 - (item 6,480 + manual 3,720) = 19,200.
      expect(subtotalLine, contains('29,400.00'));
      expect(discountLine, contains('10,200.00'));
      expect(totalLine, contains('19,200.00'));
    },
  );

  test('on-screen preview matches the printed SUBTOTAL / DISCOUNT', () {
    final lines =
        ThermalReceiptLayout(_inv013507Checkout()).buildPreviewLines();

    expect(lines.firstWhere((l) => l.startsWith('SUBTOTAL')),
        contains('29400.00'));
    expect(lines.firstWhere((l) => l.startsWith('DISCOUNT')),
        contains('10200.00'));
  });

  test(
    'item-only discount is not double-counted (MEDIUM EGG 30pc @7.50 with a '
    '15 item discount: SUBTOTAL 225 / DISCOUNT -15 / TOTAL 210)',
    () {
      final receipt = ReceiptData(
        orderId: 2040,
        invoiceNumber: 'INV-002040',
        customerName: 'Walk In Farmer',
        paymentMethod: 'Cash',
        items: const [
          ReceiptLineItem(
            name: 'MEDIUM EGG - PIECE',
            quantity: 30,
            unitPrice: 7.50,
            total: 210,
          ),
        ],
        subtotal: 210,
        vat: 0,
        discount: 15,
        manualDiscount: 0,
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

      expect(lines, contains('15.00 discount'));
      expect(lines.firstWhere((l) => l.startsWith('SUBTOTAL')),
          contains('225.00'));
      final discountLine = lines.firstWhere((l) => l.startsWith('DISCOUNT'));
      expect(discountLine, contains('15.00'));
      expect(discountLine.contains('30.00'), isFalse);
      expect(lines.firstWhere((l) => l.startsWith('TOTAL')),
          contains('210.00'));
    },
  );

  test('coupon and loyalty add on top of item + manual discounts', () {
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
      subtotal: 67, // 90 - 15 manual - 5 coupon - 3 loyalty
      vat: 0,
      discount: 23,
      manualDiscount: 15,
      couponDiscount: 5,
      loyaltyDiscount: 3,
      total: 67,
      amountTendered: 67,
      change: 0,
      currencySymbol: 'PHP',
      cashierName: 'Cashier',
      itemCount: 1,
    );

    final lines = ThermalReceiptLayout(receipt).buildLines();

    expect(lines.firstWhere((l) => l.startsWith('SUBTOTAL')),
        contains('100.00'));
    expect(lines.firstWhere((l) => l.startsWith('DISCOUNT')),
        contains('33.00'));
    expect(lines.firstWhere((l) => l.startsWith('TOTAL')), contains('67.00'));
  });

  group('every discount type stacked (item + manual + coupon + loyalty)', () {
    // FEEDS 10 x 100 = 1,000 gross, 10/unit item discount -> 900 net.
    // Then manual 200, coupon 150, loyalty 50 -> 500 merchandise, +12% VAT.
    const items = [
      ReceiptLineItem(
        name: 'FEEDS - 50 KILO',
        quantity: 10,
        unitPrice: 100,
        total: 900,
      ),
    ];

    ReceiptData checkout() => ReceiptData(
          orderId: 77,
          invoiceNumber: 'INV-000077',
          customerName: 'Juan Farmer',
          paymentMethod: 'Cash',
          items: items,
          subtotal: 500,
          vat: 60,
          discount: 400,
          manualDiscount: 200,
          couponDiscount: 150,
          loyaltyDiscount: 50,
          total: 560,
          amountTendered: 600,
          change: 40,
          currencySymbol: 'PHP',
          cashierName: 'Cashier',
          itemCount: 10,
        );

    Map<String, dynamic> apiJson({double refundedQty = 0, double refunded = 0}) => {
          'id': 77,
          'customer_name': 'Juan Farmer',
          'payment_method': 'Cash',
          'created_at': '2026-10-23 10:00:00',
          'subtotal': 500,
          // OrderQueryController adds the 100 item discount to the 200
          // manual discount.
          'discount_amount': 300,
          'coupon_discount': 150,
          'loyalty_discount': 50,
          'vat': 60,
          'total_amount': 560,
          'client_change': 40,
          'refunded_amount': refunded,
          'items': [
            {
              'product_name': 'FEEDS',
              'variety_name': '50 KILO',
              'quantity': 10,
              'refunded_quantity': refundedQty,
              'price': 100,
              'discount_amount': 100,
              'total': 900,
            },
          ],
        };

    void expectTotals(List<String> lines) {
      expect(lines.firstWhere((l) => l.startsWith('SUBTOTAL')),
          contains('1,000.00'));
      // 100 item + 200 manual + 150 coupon + 50 loyalty - each counted once.
      expect(lines.firstWhere((l) => l.startsWith('DISCOUNT')),
          contains('500.00'));
      expect(lines.firstWhere((l) => l.startsWith('VAT')), contains('60.00'));
      expect(lines.firstWhere((l) => l.startsWith('TOTAL ')),
          contains('560.00'));
    }

    test('checkout receipt counts each discount exactly once', () {
      expectTotals(ThermalReceiptLayout(checkout()).buildLines());
    });

    test('reprint prints the same totals as the checkout receipt', () {
      final receipt = TransactionService('http://localhost')
          .buildReceiptData(TransactionRecord.fromJson(apiJson()));

      expect(receipt.manualDiscount, 200);
      expect(receipt.couponDiscount, 150);
      expect(receipt.loyaltyDiscount, 50);
      expectTotals(ThermalReceiptLayout(receipt).buildLines());
    });

    test('refunded reprint item lines add up to the amount refunded', () {
      final receipt = TransactionService('http://localhost').buildReceiptData(
        TransactionRecord.fromJson(apiJson(refundedQty: 4, refunded: 224)),
      );

      // 4 of 10 refunded = 40% of the 560 paid, not 40% of the 900 line.
      expect(receipt.refundItems.single.amount, closeTo(224, 0.001));
      final lines = ThermalReceiptLayout(receipt).buildLines();
      expect(lines.firstWhere((l) => l.startsWith('REFUNDED')),
          contains('224.00'));
      expect(lines.any((l) => l.contains('360.00')), isFalse);
    });
  });

  test(
    'reprint from the orders API (discount_amount already includes item '
    'discounts) prints the same totals as the original receipt',
    () {
      final transaction = TransactionRecord.fromJson({
        'id': 13507,
        'customer_name': 'Walk In Farmer',
        'payment_method': 'Cash',
        'cashier_name': 'HASMIN',
        'created_at': '2026-10-23 09:21:00',
        'subtotal': 19200,
        // OrderQueryController: o.discount_amount (3,720) + item discounts
        // (6,480).
        'discount_amount': 10200,
        'coupon_discount': 0,
        'loyalty_discount': 0,
        'vat': 0,
        'total_amount': 19200,
        'client_change': 300,
        'items': [
          {
            'product_name': 'AGWAY CARTAP',
            'variety_name': '100 GRAMS',
            'quantity': 120,
            'price': 120,
            'discount_amount': 3720,
            'total': 10680,
          },
          {
            'product_name': 'LAUDA',
            'variety_name': '1000 ML',
            'quantity': 12,
            'price': 650,
            'discount_amount': 1680,
            'total': 6120,
          },
          {
            'product_name': 'ULTRACRON',
            'variety_name': '1000 ML',
            'quantity': 12,
            'price': 600,
            'discount_amount': 1080,
            'total': 6120,
          },
        ],
      });

      final receipt =
          TransactionService('http://localhost').buildReceiptData(transaction);

      expect(receipt.invoiceNumber, 'INV-013507');
      expect(receipt.manualDiscount, 3720);

      final lines = ThermalReceiptLayout(receipt).buildLines();
      expect(lines.firstWhere((l) => l.startsWith('SUBTOTAL')),
          contains('29,400.00'));
      expect(lines.firstWhere((l) => l.startsWith('DISCOUNT')),
          contains('10,200.00'));
      expect(lines.firstWhere((l) => l.startsWith('TOTAL')),
          contains('19,200.00'));
    },
  );
}
