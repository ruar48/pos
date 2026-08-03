import 'package:shared_preferences/shared_preferences.dart';

import 'printer_settings.dart';

class DevicePrinterSettings {
  const DevicePrinterSettings({
    required this.config,
    required this.hasLocalConfig,
  });

  final PrinterConfig config;
  final bool hasLocalConfig;

  static const _hasLocalKey = 'device_printer_has_local_config';
  static const _typeKey = 'device_printer_type';
  static const _hostKey = 'device_printer_host';
  static const _deviceKey = 'device_printer_device';
  static const _portKey = 'device_printer_port';
  static const _paperWidthKey = 'device_printer_paper_width_chars';

  static Future<DevicePrinterSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLocal = prefs.getBool(_hasLocalKey) ?? false;
    final port = prefs.getInt(_portKey) ?? 9100;
    final paperWidth = prefs.getInt(_paperWidthKey) ?? 32;

    return DevicePrinterSettings(
      hasLocalConfig: hasLocal,
      config: PrinterConfig(
        type: PrinterConnectionType.parse(prefs.getString(_typeKey)),
        host: (prefs.getString(_hostKey) ?? '').trim(),
        device: (prefs.getString(_deviceKey) ?? '').trim(),
        port: port > 0 ? port : 9100,
        paperWidthChars: paperWidth > 0 ? paperWidth : 32,
      ),
    );
  }

  static Future<void> save(PrinterConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasLocalKey, true);
    await prefs.setString(_typeKey, config.type.apiValue);
    await prefs.setString(_hostKey, config.host.trim());
    await prefs.setString(_deviceKey, config.device.trim());
    await prefs.setInt(_portKey, config.port > 0 ? config.port : 9100);
    await prefs.setInt(
      _paperWidthKey,
      config.paperWidthChars > 0 ? config.paperWidthChars : 32,
    );
  }
}
