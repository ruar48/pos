import 'dart:async';
import 'dart:io';

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

  /// Latin-1 letters PC437 has, keyed by code point. Each byte is the same
  /// letter in PC850 too, so text stays right whichever of the two a
  /// printer defaults to - safer than sending `ESC t`, whose code-table
  /// numbers differ between printer brands.
  static const Map<int, int> _pc437Letters = {
    0xC4: 0x8E, // Ä
    0xC5: 0x8F, // Å
    0xC6: 0x92, // Æ
    0xC7: 0x80, // Ç
    0xC9: 0x90, // É
    0xD1: 0xA5, // Ñ
    0xD6: 0x99, // Ö
    0xDC: 0x9A, // Ü
    0xDF: 0xE1, // ß
    0xE0: 0x85, // à
    0xE1: 0xA0, // á
    0xE2: 0x83, // â
    0xE4: 0x84, // ä
    0xE5: 0x86, // å
    0xE6: 0x91, // æ
    0xE7: 0x87, // ç
    0xE8: 0x8A, // è
    0xE9: 0x82, // é
    0xEA: 0x88, // ê
    0xEB: 0x89, // ë
    0xEC: 0x8D, // ì
    0xED: 0xA1, // í
    0xEE: 0x8C, // î
    0xEF: 0x8B, // ï
    0xF1: 0xA4, // ñ
    0xF2: 0x95, // ò
    0xF3: 0xA2, // ó
    0xF4: 0x93, // ô
    0xF6: 0x94, // ö
    0xF7: 0xF6, // ÷
    0xF9: 0x97, // ù
    0xFA: 0xA3, // ú
    0xFB: 0x96, // û
    0xFC: 0x81, // ü
    0xFF: 0x98, // ÿ
  };

  /// Plain-ASCII stand-in for each of U+00C0-U+00FF (indexed from 0xC0),
  /// used for the ones [_pc437Letters] doesn't cover.
  static const String _latin1Fold = 'AAAAAAACEEEEIIIIDNOOOOOxOUUUUYPs'
      'aaaaaaaceeeeiiiidnooooo/ouuuuypy';

  /// Encodes printable text as exactly one byte per character for the
  /// printer's single-byte code page (PC437 after `ESC @`). UTF-8 sent "ñ"
  /// as two bytes, which printed as two wrong glyphs and pushed every
  /// padded column one place right. Anything with no byte becomes '?' so a
  /// row keeps the width the layout counted; line endings are the
  /// caller's job.
  static List<int> encodeText(String text) {
    final bytes = <int>[];
    for (final rune in text.runes) {
      if (rune >= 0x20 && rune <= 0x7E) {
        bytes.add(rune);
      } else if (rune >= 0xC0 && rune <= 0xFF) {
        bytes.add(_pc437Letters[rune] ?? _latin1Fold.codeUnitAt(rune - 0xC0));
      } else if (rune == 0x20B1) {
        bytes.add(0x50); // ₱ isn't in PC437/PC850 - print "P".
      } else if (rune >= 0x0300 && rune <= 0x036F) {
        // Combining accent of a decomposed letter ("n" + U+0303) - the
        // base letter already printed, so drop the accent.
        continue;
      } else {
        bytes.add(0x3F);
      }
    }
    return bytes;
  }

  /// Deliberately plain: no init, no bold/center ESC sequences, no feed/cut
  /// - just text and line feeds. This receipt keeps garbling even on
  /// this short 4-line test regardless of chunk pacing, so the next thing
  /// to rule out is whether the ESC/POS control bytes themselves (which a
  /// non-standard clone controller could be misinterpreting as literal
  /// characters) are the source, rather than the transport layer. If this
  /// still garbles too, the corruption is happening below the byte content
  /// entirely (plugin/OS/RF), not from anything this app is sending.
  static List<int> buildBluetoothTestReceiptBytes() {
    const title = '${AppBrand.shortName} BT Test';
    const subtitle = 'Bluetooth printer OK';
    final bytes = <int>[];

    void line(String text) {
      // Same encoding as real receipts - AppBrand.shortName contains 'ñ',
      // which must go out as its single PC437 byte, not UTF-8.
      bytes.addAll(encodeText(text));
      bytes.add(0x0A);
    }

    line(title);
    line(subtitle);
    line('');
    line('If you can read this, Bluetooth printing works.');
    line('');
    line('');
    return bytes;
  }

  /// Tail of the print queue. Every job that talks to the printer (receipt,
  /// drawer kick, Bluetooth test) chains onto it so only one runs at a
  /// time - overlapping jobs share one Bluetooth link, and each job's
  /// connect/disconnect cut the other off (truncated receipts, lost drawer
  /// kick).
  static Future<void> _queueTail = Future<void>.value();
  static int _queuedJobs = 0;
  static final ValueNotifier<bool> _busy = ValueNotifier<bool>(false);

  /// True while a print job is running or waiting its turn - lets the UI
  /// hold off a manual print while e.g. the checkout auto-print is going.
  static ValueListenable<bool> get busy => _busy;

  /// Runs [job] after every job queued before it. Never call this from
  /// inside a job - it would wait on itself.
  @visibleForTesting
  static Future<T> runExclusive<T>(Future<T> Function() job) {
    _queuedJobs++;
    _busy.value = true;
    final result = _queueTail.then((_) => job());
    // The caller gets the job's error from `result`; the queue ignores it
    // so one failed print doesn't block the next. The timeout is a valve
    // for a job stuck in a plugin call, which would otherwise block all
    // printing until the app restarts.
    _queueTail = result
        .timeout(const Duration(seconds: 60))
        .then<void>((_) {}, onError: (_) {})
        .whenComplete(() {
      _queuedJobs--;
      if (_queuedJobs == 0) _busy.value = false;
    });
    return result;
  }

  static Future<BluetoothPrinterTestResult> testBluetoothConnection({
    required String macAddress,
    bool sendTestReceipt = true,
  }) {
    // Queued like a print job: it connects and disconnects the same
    // Bluetooth link a receipt in progress would be using.
    return runExclusive(
      () => _testBluetoothConnection(
        macAddress: macAddress,
        sendTestReceipt: sendTestReceipt,
      ),
    );
  }

  static Future<BluetoothPrinterTestResult> _testBluetoothConnection({
    required String macAddress,
    required bool sendTestReceipt,
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
        // Must match the real receipt path exactly (settle delay + paced
        // line writes via _writeInChunks) - this used to call
        // PrintBluetoothThermal.writeBytes directly in one shot, so the
        // test print never actually exercised the pacing fix and could
        // garble even after that fix was applied to real receipts.
        bool ok;
        try {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await _writeInChunks(buildBluetoothTestReceiptBytes());
          ok = true;
        } catch (error) {
          ok = false;
        }
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

    await runExclusive(() async {
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
    });
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
    // A printer that stops reading (paper out, jammed, dropped off WiFi)
    // leaves flush/close pending forever, which would hang the job and
    // every job queued behind it.
    const ioTimeout = Duration(seconds: 10);
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      // Same reasoning as the Bluetooth path: many cheap thermal printers
      // (including network/WiFi ones, which are often just a small
      // serial-to-LAN bridge with a tiny receive buffer) drop or corrupt
      // bytes when a full receipt is written in one burst - writing in
      // small paced chunks avoids overflowing that buffer.
      const chunkSize = 256;
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, bytes.length);
        socket.add(bytes.sublist(offset, end));
        await socket.flush().timeout(ioTimeout);
        if (end < bytes.length) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      await socket.close().timeout(ioTimeout);
    } catch (error) {
      socket?.destroy();
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

      // Give the printer's buffer a moment to settle right after connecting
      // — writing a full receipt immediately on a fresh connection is a
      // known cause of dropped/garbled bytes on cheap thermal printers.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _writeInChunks(bytes);

      await Future<void>.delayed(const Duration(milliseconds: 400));
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

  /// Writes bytes to the connected Bluetooth printer one line per write
  /// with a short pause between writes — some cheap thermal printers
  /// silently drop or corrupt bytes when a large payload (a full receipt)
  /// is written in one burst, which can show up as a single line printing
  /// misaligned or with missing characters even though the generated text
  /// is correct.
  ///
  /// Each write is a whole line up to and including its line ending, never
  /// part of one: receipts wrapped mid-word at arbitrary points (e.g. "Re"
  /// / "ceipt No:") because if the printer times out its input buffer
  /// during a pause, it force-linefeeds whatever partial line it has. The
  /// earlier 32-byte sub-chunking of long lines still did that to every
  /// padded 48-column row (50 bytes with CRLF).
  static Future<void> _writeInChunks(List<int> bytes) async {
    const delay = Duration(milliseconds: 40);

    for (final segment in splitIntoLineSegments(bytes)) {
      final ok = await PrintBluetoothThermal.writeBytes(segment);
      if (!ok) {
        throw ReceiptPrintException('Bluetooth printer rejected the print job.');
      }
      await Future<void>.delayed(delay);
    }
  }

  /// Splits a byte stream into segments that each end at a line feed
  /// (0x0A - the end of a CRLF, or the bare LF the test receipt uses), so
  /// a paced write never lands mid-line. Any trailing bytes without a line
  /// ending (e.g. the feed/cut control bytes at the end of a receipt) form
  /// a final segment on their own.
  @visibleForTesting
  static List<List<int>> splitIntoLineSegments(List<int> bytes) {
    final segments = <List<int>>[];
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) {
        segments.add(bytes.sublist(start, i + 1));
        start = i + 1;
      }
    }
    if (start < bytes.length) {
      segments.add(bytes.sublist(start));
    }
    return segments;
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

      const chunkSize = 256;
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, bytes.length);
        await port.write(Uint8List.fromList(bytes.sublist(offset, end)));
        if (end < bytes.length) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
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
