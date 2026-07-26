import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:usb_serial/usb_serial.dart';

import '../../core/constants/brand.dart';
import '../../models/printer_settings.dart';
import 'bluetooth_printer_test_result.dart';
import 'receipt_print_exception.dart';

class PrinterTransport {
  static final RegExp _macPattern = RegExp(
    r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$',
  );

  static String normalizeMacAddress(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (cleaned.length != 12) {
      return raw.trim().toUpperCase();
    }

    return List.generate(
      6,
      (index) => cleaned.substring(index * 2, index * 2 + 2),
    ).join(':');
  }

  static bool isValidMacAddress(String raw) {
    return _macPattern.hasMatch(normalizeMacAddress(raw));
  }

  static List<int> buildBluetoothTestReceiptBytes() {
    const title = '${AppBrand.shortName} BT Test';
    const subtitle = 'Bluetooth printer OK';
    final bytes = <int>[0x1B, 0x40];

    void line(String text, {bool center = false, bool bold = false}) {
      if (center) bytes.addAll(const [0x1B, 0x61, 0x01]);
      if (bold) bytes.addAll(const [0x1B, 0x45, 0x01]);
      bytes.addAll('$text\n'.codeUnits);
      if (bold) bytes.addAll(const [0x1B, 0x45, 0x00]);
      if (center) bytes.addAll(const [0x1B, 0x61, 0x00]);
    }

    line(title, center: true, bold: true);
    line(subtitle, center: true);
    line('');
    line('If you can read this, Bluetooth printing works.');
    bytes.addAll(const [0x1B, 0x64, 0x03]);
    return bytes;
  }

  static Future<BluetoothPrinterTestResult> testBluetoothConnection({
    required String macAddress,
    bool sendTestReceipt = true,
  }) async {
    final steps = <BluetoothPrinterTestStep>[];

    void addStep(String label, bool passed, String message) {
      steps.add(
        BluetoothPrinterTestStep(
          label: label,
          passed: passed,
          message: message,
        ),
      );
    }

    BluetoothPrinterTestResult finish({
      required bool passed,
      required String summary,
    }) {
      return BluetoothPrinterTestResult(
        passed: passed,
        steps: List<BluetoothPrinterTestStep>.from(steps),
        summary: summary,
      );
    }

    if (kIsWeb) {
      addStep('Platform', false, 'Bluetooth is not available in the browser.');
      return finish(
        passed: false,
        summary: 'Use an Android tablet to test Bluetooth printing.',
      );
    }

    if (!Platform.isAndroid) {
      addStep(
        'Platform',
        false,
        'Bluetooth printing is supported on Android tablets only.',
      );
      return finish(
        passed: false,
        summary: 'Run this test on the POS tablet, not a PC or emulator.',
      );
    }

    final mac = normalizeMacAddress(macAddress);
    if (!isValidMacAddress(macAddress)) {
      addStep('MAC address', false, 'Invalid format: $macAddress');
      return finish(
        passed: false,
        summary: 'Enter a valid MAC address like AA:BB:CC:DD:EE:FF.',
      );
    }
    addStep('MAC address', true, 'Using $mac');

    try {
      await _ensureBluetoothPermissions();
      addStep('Permissions', true, 'Nearby devices permission granted.');
    } on ReceiptPrintException catch (error) {
      addStep('Permissions', false, error.message);
      return finish(passed: false, summary: error.message);
    } catch (error) {
      addStep('Permissions', false, error.toString());
      return finish(
        passed: false,
        summary: 'Could not verify Bluetooth permissions.',
      );
    }

    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) {
      addStep('Bluetooth radio', false, 'Bluetooth is turned off.');
      return finish(
        passed: false,
        summary: 'Turn on Bluetooth on this tablet, then run the test again.',
      );
    }
    addStep('Bluetooth radio', true, 'Bluetooth is on.');

    final paired = await listBluetoothPrinters();
    BluetoothInfo? matchedPrinter;
    for (final device in paired) {
      if (normalizeMacAddress(device.macAdress) == mac) {
        matchedPrinter = device;
        break;
      }
    }

    if (matchedPrinter == null) {
      addStep(
        'Pairing',
        false,
        'Printer $mac is not in the paired devices list.',
      );
      return finish(
        passed: false,
        summary:
            'Pair the printer in Android Bluetooth settings, then choose it again in Settings → Printer.',
      );
    }
    addStep(
      'Pairing',
      true,
      'Found paired printer: ${matchedPrinter.name}',
    );

    try {
      var connected = await _connectBluetoothPrinter(mac);
      if (!connected) {
        connected = await _connectBluetoothPrinter(mac);
      }

      if (!connected) {
        addStep(
          'Connection',
          false,
          'Could not open a Bluetooth link to $mac.',
        );
        return finish(
          passed: false,
          summary:
              'Printer is paired but not reachable. Turn it on and keep it nearby.',
        );
      }
      addStep('Connection', true, 'Connected to the printer.');

      if (sendTestReceipt) {
        final ok = await PrintBluetoothThermal.writeBytes(
          buildBluetoothTestReceiptBytes(),
        );
        if (!ok) {
          addStep(
            'Test print',
            false,
            'Printer did not accept the test receipt.',
          );
          return finish(
            passed: false,
            summary: 'Connected, but the test print failed.',
          );
        }
        addStep('Test print', true, 'Test receipt sent successfully.');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } else {
        addStep('Test print', true, 'Skipped sending paper (connection only).');
      }

      return finish(
        passed: true,
        summary: sendTestReceipt
            ? 'Bluetooth printer is ready. Check the test receipt.'
            : 'Bluetooth connection test passed.',
      );
    } catch (error) {
      addStep(
        'Connection',
        false,
        error is ReceiptPrintException ? error.message : error.toString(),
      );
      return finish(
        passed: false,
        summary: 'Bluetooth test failed before printing.',
      );
    } finally {
      await _resetBluetoothConnection();
      addStep('Cleanup', true, 'Bluetooth connection closed.');
    }
  }

  static Future<void> _ensureBluetoothPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return;

    var granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (granted) return;

    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    final connectGranted =
        statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;

    if (!granted && !connectGranted && !scanGranted) {
      throw ReceiptPrintException(
        'Bluetooth permission is required. Enable Nearby devices for ${AppBrand.shortName} in Android settings.',
      );
    }
  }

  static Future<void> _resetBluetoothConnection() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (error) {
      debugPrint('Bluetooth disconnect: $error');
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  static Future<bool> _connectBluetoothPrinter(String macAddress) async {
    await _resetBluetoothConnection();
    return PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }
  static Future<void> sendEscPos({
    required PrinterConfig config,
    required List<int> bytes,
    bool openDrawer = false,
  }) async {
    if (kIsWeb) {
      throw ReceiptPrintException('Printing is not available in the browser.');
    }

    if (!config.isConfigured) {
      throw ReceiptPrintException(
        'Store printer is not set up yet. Ask your manager or admin to configure it.',
      );
    }

    final payload = List<int>.from(bytes);
    if (openDrawer) {
      payload.addAll(kCashDrawerKickBytes);
    }

    switch (config.type) {
      case PrinterConnectionType.network:
        await _sendNetwork(
          host: config.host.trim(),
          port: config.port > 0 ? config.port : 9100,
          bytes: payload,
        );
      case PrinterConnectionType.bluetooth:
        await _sendBluetooth(
          macAddress: config.device.trim(),
          bytes: payload,
        );
      case PrinterConnectionType.usb:
        await _sendUsb(
          deviceId: config.device.trim(),
          bytes: payload,
        );
    }
  }

  static Future<List<BluetoothInfo>> listBluetoothPrinters() async {
    if (kIsWeb) return const [];
    try {
      await _ensureBluetoothPermissions();
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (error) {
      debugPrint('Bluetooth scan: $error');
      return const [];
    }
  }

  static Future<List<String>> listUsbPrinterIds() async {
    if (kIsWeb || !Platform.isAndroid) return const [];
    try {
      final devices = await UsbSerial.listDevices();
      return devices
          .map((device) {
            final name = device.productName?.trim();
            final id = '${device.vid}:${device.pid}';
            if (name == null || name.isEmpty) return id;
            return '$id · $name';
          })
          .toList(growable: false);
    } catch (error) {
      debugPrint('USB scan: $error');
      return const [];
    }
  }

  static Future<void> _sendNetwork({
    required String host,
    required int port,
    required List<int> bytes,
  }) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      socket.add(bytes);
      await socket.flush();
      await socket.close();
    } catch (error) {
      debugPrint('Network printer: $error');
      throw ReceiptPrintException(
        'Could not reach printer at $host:$port. Check the IP, power, and network.',
      );
    }
  }

  static Future<void> _sendBluetooth({
    required String macAddress,
    required List<int> bytes,
  }) async {
    await _ensureBluetoothPermissions();

    final mac = normalizeMacAddress(macAddress);
    if (!_macPattern.hasMatch(mac)) {
      throw ReceiptPrintException(
        'Invalid Bluetooth MAC address: $macAddress',
      );
    }

    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) {
      throw ReceiptPrintException(
        'Turn on Bluetooth on this tablet, then try again.',
      );
    }

    try {
      var connected = await _connectBluetoothPrinter(mac);
      if (!connected) {
        connected = await _connectBluetoothPrinter(mac);
      }

      if (!connected) {
        final paired = await listBluetoothPrinters();
        final stillPaired = paired.any(
          (device) => normalizeMacAddress(device.macAdress) == mac,
        );
        if (!stillPaired) {
          throw ReceiptPrintException(
            'Printer is not paired anymore. Pair it in Android Bluetooth settings, then open Settings → Printer and choose it again.',
          );
        }
        throw ReceiptPrintException(
          'Could not connect to Bluetooth printer $mac. Make sure the printer is on and nearby.',
        );
      }

      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      if (!ok) {
        throw ReceiptPrintException('Bluetooth printer rejected the print job.');
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    } catch (error) {
      if (error is ReceiptPrintException) rethrow;
      debugPrint('Bluetooth printer: $error');
      throw ReceiptPrintException(
        'Bluetooth print failed for $mac. Check pairing and power.',
      );
    } finally {
      await _resetBluetoothConnection();
    }
  }

  static Future<void> _sendUsb({
    required String deviceId,
    required List<int> bytes,
  }) async {
    if (!Platform.isAndroid) {
      throw ReceiptPrintException('USB printing is supported on Android tablets only.');
    }

    final normalizedId = deviceId.split('·').first.trim();
    final parts = normalizedId.split(':');
    if (parts.length != 2) {
      throw ReceiptPrintException(
        'USB printer ID must look like 1234:5678 (vendor:product).',
      );
    }

    final vendorId = int.tryParse(parts[0].trim());
    final productId = int.tryParse(parts[1].trim());
    if (vendorId == null || productId == null) {
      throw ReceiptPrintException('Invalid USB printer ID: $deviceId');
    }

    UsbPort? port;
    try {
      final devices = await UsbSerial.listDevices();
      UsbDevice? target;
      for (final device in devices) {
        if (device.vid == vendorId && device.pid == productId) {
          target = device;
          break;
        }
      }
      if (target == null) {
        throw ReceiptPrintException(
          'USB printer $normalizedId not found. Connect it with an OTG cable.',
        );
      }

      port = await target.create();
      if (port == null) {
        throw ReceiptPrintException('Could not open USB printer port.');
      }

      final opened = await port.open();
      if (!opened) {
        throw ReceiptPrintException('Could not open USB printer connection.');
      }

      await port.write(Uint8List.fromList(bytes));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } catch (error) {
      if (error is ReceiptPrintException) rethrow;
      debugPrint('USB printer: $error');
      throw ReceiptPrintException('USB print failed for $deviceId.');
    } finally {
      await port?.close();
    }
  }
}
