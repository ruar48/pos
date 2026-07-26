import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/features/receipt/receipt_printer.dart';

void main() {
  test('thermal receipt shows unit price, quantity, and line total', () {
    final receipt = ReceiptData(
      orderId: 1,
      invoiceNumber: 'INV-000030',
      customerName: 'Walk In Farmer',
      paymentMethod: 'Cash',
      items: const [
        ReceiptLineItem(
          name: 'ACC Feeds 40kg',
          quantity: 3,
          unitPrice: 320,
          total: 930,
        ),
      ],
      subtotal: 960,
      vat: 0,
      discount: 30,
      manualDiscount: 30,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      total: 930,
      amountTendered: 1000,
      change: 70,
      currencySymbol: 'PHP',
      cashierName: 'Cashier',
      itemCount: 3,
    );

    final lines = ThermalReceiptLayout(receipt).buildLines();
    final itemLine = lines.firstWhere((line) => line.contains('@320x3'));

    expect(itemLine, contains('ACC Feeds 40kg'));
    expect(itemLine, contains('930.00'));
    expect(lines, contains('30.00 discount @3.13%'));
    expect(lines.any((line) => line.startsWith('Total Qty')), isTrue);
    expect(lines.any((line) => line.contains('MARAMING SALAMAT PO!')), isTrue);
    expect(lines.any((line) => line.contains('NO REFUND POLICY')), isTrue);
    expect(lines.any((line) => line.contains('PTU')), isFalse);
    expect(lines.any((line) => line.contains('TIN:')), isFalse);
    expect(lines.any((line) => line.contains('NON-VAT')), isFalse);
    expect(lines.any((line) => line.contains('VAT REGISTERED')), isFalse);
    expect(lines.any((line) => line.contains('INPUT TAX')), isFalse);
  });

  test('loyalty customer shows points earned and total near top', () {
    final receipt = ReceiptData(
      orderId: 2,
      invoiceNumber: 'INV-000002',
      customerName: 'Juan Farmer',
      paymentMethod: 'Cash',
      items: const [
        ReceiptLineItem(
          name: 'ACC Rice 25kg',
          quantity: 1,
          unitPrice: 100,
          total: 100,
        ),
      ],
      subtotal: 100,
      vat: 0,
      discount: 0,
      manualDiscount: 0,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      total: 100,
      amountTendered: 100,
      change: 0,
      currencySymbol: 'PHP',
      cashierName: 'Cashier',
      itemCount: 1,
      loyaltyPointsEarned: 50,
      loyaltyBalance: 250,
      isLoyaltyCustomer: true,
    );

    final lines = ThermalReceiptLayout(receipt).buildLines();
    final customerIndex = lines.indexWhere((line) => line.contains('CUSTOMER'));
    final earnedIndex = lines.indexWhere((line) => line.contains('POINTS EARNED'));
    final totalIndex = lines.indexWhere((line) => line.contains('TOTAL POINTS'));
    final dividerIndex = lines.indexWhere((line) => line == '-' * 32);

    expect(customerIndex, greaterThan(-1));
    expect(earnedIndex, greaterThan(customerIndex));
    expect(totalIndex, greaterThan(earnedIndex));
    expect(dividerIndex, greaterThan(totalIndex));
    expect(lines.any((line) => line.contains('LOYALTY POINTS')), isFalse);
  });

  test('long item names still show right-aligned line total', () {
    final receipt = ReceiptData(
      orderId: 3,
      invoiceNumber: 'INV-000031',
      customerName: 'Walk In Farmer',
      paymentMethod: 'Cash',
      items: const [
        ReceiptLineItem(
          name: 'Broiler Starter Feed',
          quantity: 3,
          unitPrice: 29.50,
          total: 88.50,
        ),
      ],
      subtotal: 88.50,
      vat: 0,
      discount: 0,
      manualDiscount: 0,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      total: 88.50,
      amountTendered: 100,
      change: 11.50,
      currencySymbol: 'PHP',
      cashierName: 'Cashier',
      itemCount: 3,
    );

    final lines = ThermalReceiptLayout(receipt).buildLines();
    final metaLine = lines.firstWhere((line) => line.contains('@29.50x3'));

    expect(metaLine.trimRight(), endsWith('88.50'));
    expect(metaLine.length, lessThanOrEqualTo(32));
    expect(lines.any((line) => line.contains('Broiler Starter Feed')), isTrue);
  });

  test('first-time loyalty customer shows points earned on receipt', () {
    final receipt = ReceiptData(
      orderId: 4,
      invoiceNumber: 'INV-000042',
      customerName: 'sa',
      paymentMethod: 'Cash',
      items: const [
        ReceiptLineItem(
          name: 'ACC Pesticide 1L',
          quantity: 1,
          unitPrice: 80,
          total: 80,
        ),
      ],
      subtotal: 709.44,
      vat: 0,
      discount: 0,
      manualDiscount: 0,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      total: 709.44,
      amountTendered: 709.44,
      change: 0,
      currencySymbol: 'PHP',
      cashierName: 'JOMAR',
      itemCount: 18,
      loyaltyPointsEarned: 35,
      loyaltyBalance: 35,
      isLoyaltyCustomer: true,
    );

    final lines = ThermalReceiptLayout(receipt).buildPreviewLines();
    final customerIndex = lines.indexWhere((line) => line.contains('CUSTOMER'));
    final earnedIndex = lines.indexWhere((line) => line.contains('POINTS EARNED'));
    final totalIndex = lines.indexWhere((line) => line.contains('TOTAL POINTS'));

    expect(customerIndex, greaterThan(-1));
    expect(earnedIndex, greaterThan(customerIndex));
    expect(totalIndex, greaterThan(earnedIndex));
    expect(lines.any((line) => line.contains('35')), isTrue);
  });
}
