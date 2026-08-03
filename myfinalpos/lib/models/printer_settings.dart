import 'app_settings.dart';

enum PrinterConnectionType {
  network,
  bluetooth,
  usb;

  static PrinterConnectionType parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'bluetooth':
        return PrinterConnectionType.bluetooth;
      case 'usb':
        return PrinterConnectionType.usb;
      default:
        return PrinterConnectionType.network;
    }
  }

  String get apiValue => name;

  String get label {
    switch (this) {
      case PrinterConnectionType.network:
        return 'Network (IP / LAN)';
      case PrinterConnectionType.bluetooth:
        return 'Bluetooth';
      case PrinterConnectionType.usb:
        return 'USB';
    }
  }
}

class PrinterConfig {
  const PrinterConfig({
    this.type = PrinterConnectionType.network,
    this.host = '',
    this.port = 9100,
    this.device = '',
    this.paperWidthChars = 42,
  });

  final PrinterConnectionType type;
  final String host;
  final int port;
  /// Bluetooth MAC address, or USB `vendorId:productId`.
  final String device;
  /// Characters per line the physical printer actually fits (Font A).
  /// 58mm printers are usually 32, 80mm printers are usually 42 or 48 -
  /// but this varies by model/font, so it's adjustable per device.
  final int paperWidthChars;

  bool get isConfigured {
    switch (type) {
      case PrinterConnectionType.network:
        return host.trim().isNotEmpty;
      case PrinterConnectionType.bluetooth:
      case PrinterConnectionType.usb:
        return device.trim().isNotEmpty;
    }
  }

  String get statusLabel {
    if (!isConfigured) return 'Not set';
    switch (type) {
      case PrinterConnectionType.network:
        return 'Network · ${host.trim()}:${port > 0 ? port : 9100}';
      case PrinterConnectionType.bluetooth:
        return 'Bluetooth · ${device.trim()}';
      case PrinterConnectionType.usb:
        return 'USB · ${device.trim()}';
    }
  }

  factory PrinterConfig.fromSettings(AppSettingsModel settings) {
    return PrinterConfig(
      type: PrinterConnectionType.parse(settings.printerType),
      host: settings.printerHost,
      port: settings.printerPort > 0 ? settings.printerPort : 9100,
      device: settings.printerDevice,
    );
  }

  PrinterConfig copyWith({
    PrinterConnectionType? type,
    String? host,
    int? port,
    String? device,
    int? paperWidthChars,
  }) {
    return PrinterConfig(
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      device: device ?? this.device,
      paperWidthChars: paperWidthChars ?? this.paperWidthChars,
    );
  }
}
