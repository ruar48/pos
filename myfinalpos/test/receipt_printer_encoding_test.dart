import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/features/receipt/printer_transport.dart';
import 'package:myfinalpos/features/receipt/receipt_printer.dart';

ReceiptData _receipt({
  String customerName = 'Walk In Farmer',
  String itemName = 'ACC Feeds 40kg',
  ReceiptStoreConfig store = const ReceiptStoreConfig(),
}) {
  return ReceiptData(
    orderId: 1,
    invoiceNumber: 'INV-000001',
    customerName: customerName,
    paymentMethod: 'Cash',
    items: [
      ReceiptLineItem(name: itemName, quantity: 1, unitPrice: 100, total: 100),
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
    currencySymbol: '₱',
    cashierName: 'Cashier',
    itemCount: 1,
    store: store,
  );
}

/// The paced Bluetooth write that carries [row] - must be the whole row
/// plus its CRLF, nothing split off.
List<int> _segmentFor(List<int> bytes, List<int> row) {
  final expected = [...row, 0x0D, 0x0A];
  return PrinterTransport.splitIntoLineSegments(bytes).firstWhere(
        (segment) =>
            segment.length >= expected.length &&
            _sameBytes(
              segment.sublist(segment.length - expected.length),
              expected,
            ),
      );
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  group('PrinterTransport.encodeText', () {
    test('ñ and Ñ are a single PC437/PC850 byte each', () {
      expect(PrinterTransport.encodeText('ñ'), [0xA4]);
      expect(PrinterTransport.encodeText('Ñ'), [0xA5]);
      expect(
        PrinterTransport.encodeText('Muñoz'),
        [0x4D, 0x75, 0xA4, 0x6F, 0x7A],
      );
    });

    test('accented letters use the PC437 byte, or fold to ASCII without one',
        () {
      expect(PrinterTransport.encodeText('é'), [0x82]);
      expect(PrinterTransport.encodeText('ü'), [0x81]);
      // Not in PC437 - folded rather than sent as a byte that prints as
      // something else.
      expect(PrinterTransport.encodeText('Á'), 'A'.codeUnits);
      expect(PrinterTransport.encodeText('ã'), 'a'.codeUnits);
    });

    test('everything else is one byte per character, never UTF-8', () {
      expect(PrinterTransport.encodeText('₱100'), 'P100'.codeUnits);
      expect(PrinterTransport.encodeText('a\tb'), 'a?b'.codeUnits);
      expect(PrinterTransport.encodeText('x\u{1F600}'), 'x?'.codeUnits);
      // Decomposed "ñ" ("n" + combining tilde) keeps just the base letter.
      expect(PrinterTransport.encodeText('Muñoz'), 'Munoz'.codeUnits);
      const ascii = 'TOTAL   1,340.00 @29.50x3 - #/:';
      expect(PrinterTransport.encodeText(ascii), ascii.codeUnits);
    });
  });

  group('ESC/POS receipt bytes on 48-column paper', () {
    setUp(() => kThermalWidth = 48);
    tearDown(() => kThermalWidth = 32);

    test('a padded row with ñ is exactly 48 bytes + CRLF in one write', () {
      final receipt = _receipt(customerName: 'Juan Muñoz');
      final row = ThermalReceiptLayout(receipt)
          .buildLines()
          .firstWhere((line) => line.startsWith('CUSTOMER'));
      final encodedRow = PrinterTransport.encodeText(row);

      expect(row.length, 48);
      expect(encodedRow.length, 48);
      expect(encodedRow, contains(0xA4));

      final bytes = PosReceiptService.buildEscPosBytes(receipt);
      expect(_segmentFor(bytes, encodedRow), [...encodedRow, 0x0D, 0x0A]);
      // No UTF-8 lead byte for ñ anywhere in the job.
      expect(bytes, isNot(contains(0xC3)));
    });

    test('an item row with ñ in the product name stays 48 bytes', () {
      final receipt = _receipt(itemName: 'Muñoz Special Feed');
      final row = ThermalReceiptLayout(receipt)
          .buildLines()
          .firstWhere((line) => line.contains('@100x1'));
      final encodedRow = PrinterTransport.encodeText(row);

      expect(row.length, 48);
      expect(encodedRow.length, 48);
      expect(row, endsWith('100.00'));

      final bytes = PosReceiptService.buildEscPosBytes(receipt);
      expect(_segmentFor(bytes, encodedRow), [...encodedRow, 0x0D, 0x0A]);
    });

    test('no ₱ reaches the printer bytes', () {
      final receipt = _receipt(
        itemName: 'Promo ₱50 Feed',
        store: const ReceiptStoreConfig(storeName: 'Muñoz ₱ Store'),
      );
      final bytes = PosReceiptService.buildEscPosBytes(receipt);

      // ₱ is U+20B1 - as UTF-8 it starts with 0xE2.
      expect(bytes, isNot(contains(0xE2)));
      expect(String.fromCharCodes(bytes), contains('Promo P50 Feed'));
    });
  });
}
