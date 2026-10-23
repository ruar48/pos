import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/features/receipt/printer_transport.dart';

void main() {
  group('PrinterTransport MAC helpers', () {
    test('normalizeMacAddress formats dashed and compact values', () {
      expect(
        PrinterTransport.normalizeMacAddress('aa:bb:cc:dd:ee:ff'),
        'AA:BB:CC:DD:EE:FF',
      );
      expect(
        PrinterTransport.normalizeMacAddress('aabbccddeeff'),
        'AA:BB:CC:DD:EE:FF',
      );
      expect(
        PrinterTransport.normalizeMacAddress('AA-BB-CC-DD-EE-FF'),
        'AA:BB:CC:DD:EE:FF',
      );
    });

    test('isValidMacAddress accepts normalized MAC values', () {
      expect(PrinterTransport.isValidMacAddress('AA:BB:CC:DD:EE:FF'), isTrue);
      expect(PrinterTransport.isValidMacAddress('aabbccddeeff'), isTrue);
      expect(PrinterTransport.isValidMacAddress('not-a-mac'), isFalse);
      expect(PrinterTransport.isValidMacAddress('AA:BB:CC'), isFalse);
    });
  });

  group('PrinterTransport Bluetooth test receipt bytes', () {
    test('buildBluetoothTestReceiptBytes has no ESC/POS control bytes and sends ñ as one code-page byte', () {
      final bytes = PrinterTransport.buildBluetoothTestReceiptBytes();

      expect(bytes.isNotEmpty, isTrue);
      // Deliberately bare (see buildBluetoothTestReceiptBytes doc comment):
      // no init/align/bold ESC bytes (0x00-0x1F control range besides \n).
      for (final byte in bytes) {
        expect(
          byte == 0x0A || byte >= 0x20,
          isTrue,
          reason: 'Unexpected control byte: $byte',
        );
      }
      // The brand name's 'ñ' must be its single PC437 byte 0xA4, not the
      // two UTF-8 bytes the printer would show as two wrong glyphs. Each
      // byte read back as one char, so 0xA4 shows up as U+00A4.
      final text = String.fromCharCodes(bytes);
      expect(text, contains('Mu¤oz Macam Agri BT Test\n'));
      expect(text, contains('Bluetooth printer OK\n'));
      expect(bytes, isNot(contains(0xC3)));
    });
  });
}
