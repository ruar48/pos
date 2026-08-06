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
    final metaLine = lines.firstWhere((line) => line.contains('#320x3'));

    expect(lines.any((line) => line.contains('ACC Feeds 40kg')), isTrue);
    expect(metaLine, contains('930.00'));
    expect(lines, contains('30.00 discount'));
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
    final earnedIndex =
        lines.indexWhere((line) => line.contains('POINTS EARNED'));
    final totalIndex =
        lines.indexWhere((line) => line.contains('TOTAL POINTS'));
    final dividerIndex = lines.indexWhere((line) => line == '-' * kThermalWidth);

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
    final metaLine = lines.firstWhere((line) => line.contains('#29.50x3'));

    expect(metaLine.trimRight(), endsWith('88.50'));
    expect(metaLine.length, lessThanOrEqualTo(32));
    expect(lines.any((line) => line.contains('Broiler Starter Feed')), isTrue);
  });

  test('item name and price/amount combine on one line when the printer is wide enough', () {
    // A 72 mm printer (48 columns) has room to fit this name, its meta,
    // and the amount on a single line - the layout should use the full
    // printable width the selected printer reports rather than wrapping
    // early as if every printer were narrow.
    kThermalWidth = 48;
    addTearDown(() => kThermalWidth = 32);

    final receipt = ReceiptData(
      orderId: 5,
      invoiceNumber: 'INV-000050',
      customerName: 'Walk In Farmer',
      paymentMethod: 'Cash',
      items: const [
        ReceiptLineItem(
          name: 'TOP BREED ADULT DOG FOOD',
          quantity: 1,
          unitPrice: 1340,
          total: 1340,
        ),
      ],
      subtotal: 1340,
      vat: 0,
      discount: 0,
      manualDiscount: 0,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      total: 1340,
      amountTendered: 1500,
      change: 160,
      currencySymbol: 'PHP',
      cashierName: 'Cashier',
      itemCount: 1,
    );

    final lines = ThermalReceiptLayout(receipt).buildLines();
    final combinedLine = lines.firstWhere((line) => line.contains('#1340x1'));

    expect(combinedLine.contains('TOP BREED ADULT DOG FOOD'), isTrue);
    expect(combinedLine.trimRight(), endsWith('1,340.00'));
    expect(combinedLine.length, lessThanOrEqualTo(48));
  });

  test('long word in item name never gets sliced mid-word', () {
    kThermalWidth = 20;
    addTearDown(() => kThermalWidth = 32);

    final receipt = ReceiptData(
      orderId: 6,
      invoiceNumber: 'INV-000060',
      customerName: 'Walk In Farmer',
      paymentMethod: 'Cash',
      items: const [
        ReceiptLineItem(
          name: 'TROPLE FOURTEEN AMIGOSUPREME',
          quantity: 1,
          unitPrice: 1850,
          total: 1850,
        ),
      ],
      subtotal: 1850,
      vat: 0,
      discount: 0,
      manualDiscount: 0,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      total: 1850,
      amountTendered: 1850,
      change: 0,
      currencySymbol: 'PHP',
      cashierName: 'Cashier',
      itemCount: 1,
    );

    final lines = ThermalReceiptLayout(receipt).buildLines();

    expect(lines.any((line) => line == 'TROPLE FOURTEEN'), isTrue);
    expect(lines.any((line) => line == 'AMIGOSUPREME'), isTrue);
    // Neither word was sliced mid-word (e.g. no stray "TROPLE FOUR"/"TEEN").
    expect(
        lines
            .any((line) => line.contains('FOUR') && !line.contains('FOURTEEN')),
        isFalse);
  });

  test('variety/unit prints on its own line after the name and price', () {
    kThermalWidth = 32;

    final receipt = ReceiptData(
      orderId: 7,
      invoiceNumber: 'INV-000070',
      customerName: 'Walk In Farmer',
      paymentMethod: 'Cash',
      items: const [
        ReceiptLineItem(
          name: 'UREA VIKING BLUE GRANULAR - 50 KILO',
          quantity: 1,
          unitPrice: 2250,
          total: 2250,
        ),
      ],
      subtotal: 2250,
      vat: 0,
      discount: 0,
      manualDiscount: 0,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      total: 2250,
      amountTendered: 2250,
      change: 0,
      currencySymbol: 'PHP',
      cashierName: 'Cashier',
      itemCount: 1,
    );

    final lines = ThermalReceiptLayout(receipt).buildLines();
    final nameIndex =
        lines.indexWhere((line) => line.contains('UREA VIKING BLUE'));
    final metaIndex = lines.indexWhere((line) => line.contains('#2250x1'));
    final varietyIndex = lines.indexWhere((line) => line.trim() == '- 50 KILO');

    expect(nameIndex, greaterThan(-1));
    expect(metaIndex, greaterThan(nameIndex));
    expect(varietyIndex, greaterThan(metaIndex));
    expect(lines[nameIndex].contains('50 KILO'), isFalse);
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
    final earnedIndex =
        lines.indexWhere((line) => line.contains('POINTS EARNED'));
    final totalIndex =
        lines.indexWhere((line) => line.contains('TOTAL POINTS'));

    expect(customerIndex, greaterThan(-1));
    expect(earnedIndex, greaterThan(customerIndex));
    expect(totalIndex, greaterThan(earnedIndex));
    expect(lines.any((line) => line.contains('35')), isTrue);
  });

  test('refund receipt wraps long item names instead of truncating them', () {
    kThermalWidth = 32;

    final receipt = ReceiptData(
      orderId: 9,
      invoiceNumber: 'RCP-000030',
      customerName: 'Walk In Farmer',
      paymentMethod: 'Cash',
      items: const [],
      subtotal: 7739,
      vat: 0,
      discount: 0,
      manualDiscount: 0,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      total: 7739,
      amountTendered: 7739,
      change: 0,
      currencySymbol: 'PHP',
      cashierName: 'Cashier',
      itemCount: 10,
      refundedAmount: 7739,
      refundItems: const [
        ReceiptRefundLineItem(
          name: 'DRAGON CARTAP TAGCHEM - 5 X 100 GRAMS',
          quantity: 1,
          amount: 1740,
        ),
      ],
    );

    final lines = ThermalReceiptLayout(receipt).buildLines();

    // The old behavior hard-truncated this to "DRAGON CARTAP TAG" to fit
    // it and the amount on one line - the full name must survive now,
    // split across word-wrapped lines instead.
    expect(lines.any((line) => line == 'DRAGON CARTAP TAG'), isFalse);
    expect(lines.any((line) => line.contains('DRAGON CARTAP')), isTrue);
    expect(lines.any((line) => line.contains('TAGCHEM')), isTrue);
    expect(lines.any((line) => line.trim() == '- 5 X 100 GRAMS'), isTrue);
  });
}
