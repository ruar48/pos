import 'dart:convert';

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
    test('buildBluetoothTestReceiptBytes has no ESC/POS control bytes and is valid UTF-8', () {
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
      // Must be proper UTF-8, not raw UTF-16 code units - the brand name
      // contains 'ñ', which .codeUnits would mangle into a single invalid
      // byte instead of encoding it as two valid UTF-8 bytes.
      final decoded = utf8.decode(bytes);
      expect(decoded, contains('Muñoz Macam Agri BT Test'));
      expect(decoded, contains('Bluetooth printer OK'));
    });
  });
}
