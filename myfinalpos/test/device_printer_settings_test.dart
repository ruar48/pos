import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/models/device_printer_settings.dart';
import 'package:myfinalpos/models/printer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DevicePrinterSettings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save and load printer config for one tablet', () async {
      const config = PrinterConfig(
        type: PrinterConnectionType.bluetooth,
        device: 'AA:BB:CC:DD:EE:FF',
      );

      await DevicePrinterSettings.save(config);
      final loaded = await DevicePrinterSettings.load();

      expect(loaded.hasLocalConfig, isTrue);
      expect(loaded.config.type, PrinterConnectionType.bluetooth);
      expect(loaded.config.device, 'AA:BB:CC:DD:EE:FF');
    });

    test('load returns empty config when tablet has not saved a printer', () async {
      final loaded = await DevicePrinterSettings.load();

      expect(loaded.hasLocalConfig, isFalse);
      expect(loaded.config.isConfigured, isFalse);
    });
  });
}
