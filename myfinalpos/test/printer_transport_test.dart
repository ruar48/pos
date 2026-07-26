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
    test('buildBluetoothTestReceiptBytes starts with ESC/POS init', () {
      final bytes = PrinterTransport.buildBluetoothTestReceiptBytes();

      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.take(2).toList(), [0x1B, 0x40]);
      expect(bytes, containsAll('GreenTok BT Test'.codeUnits));
      expect(bytes, containsAll('Bluetooth printer OK'.codeUnits));
    });
  });
}
