import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/printer_settings.dart';
import 'printer_transport.dart';
import 'receipt_print_exception.dart';

export 'receipt_print_exception.dart';

/// 58mm thermal paper ≈ 32 characters per line (Font A).
const int kThermalWidth = 32;
const String kReceiptFooterThanks = 'MARAMING SALAMAT PO!';

class ReceiptStoreConfig {
  const ReceiptStoreConfig({
    this.logoText = '[ Farm & Tractor ]',
    this.logoImagePath,
    this.storeName = 'GREEN FARM MART',
    this.storeSubtitle = 'AGRICULTURE RETAIL STORE',
    this.addressLine1 = 'Purok 3, Brgy. Sto. Rosario,',
    this.addressLine2 = 'Angeles City, Pampanga 2009',
    this.tin = '123-456-789-000',
    this.taxStatus = 'NON-VAT REGISTERED',
    this.posTerminalId = 'POS-01',
    this.ptuNo = 'PTU-123456789',
    this.atpNo = 'ATP-987654321',
    this.atpDateIssued = '01/15/2026',
    this.seriesRange = '0000001 - 9999999',
  });

  final String logoText;
  final String? logoImagePath;
  final String storeName;
  final String storeSubtitle;
  final String addressLine1;
  final String addressLine2;
  final String tin;
  final String taxStatus;
  final String posTerminalId;
  final String ptuNo;
  final String atpNo;
  final String atpDateIssued;
  final String seriesRange;

  ReceiptStoreConfig copyWith({
    String? logoText,
    String? logoImagePath,
    bool clearLogoImage = false,
    String? storeName,
    String? storeSubtitle,
    String? addressLine1,
    String? addressLine2,
    String? tin,
    String? taxStatus,
    String? posTerminalId,
    String? ptuNo,
    String? atpNo,
    String? atpDateIssued,
    String? seriesRange,
  }) {
    return ReceiptStoreConfig(
      logoText: logoText ?? this.logoText,
      logoImagePath: clearLogoImage ? null : (logoImagePath ?? this.logoImagePath),
      storeName: storeName ?? this.storeName,
      storeSubtitle: storeSubtitle ?? this.storeSubtitle,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      tin: tin ?? this.tin,
      taxStatus: taxStatus ?? this.taxStatus,
      posTerminalId: posTerminalId ?? this.posTerminalId,
      ptuNo: ptuNo ?? this.ptuNo,
      atpNo: atpNo ?? this.atpNo,
      atpDateIssued: atpDateIssued ?? this.atpDateIssued,
      seriesRange: seriesRange ?? this.seriesRange,
    );
  }

  static Future<ReceiptStoreConfig> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    const defaults = ReceiptStoreConfig();
    return ReceiptStoreConfig(
      logoText: prefs.getString('store_logo_text') ?? defaults.logoText,
      logoImagePath: prefs.getString('store_logo_image_path'),
      storeName: prefs.getString('store_name') ?? defaults.storeName,
      storeSubtitle: prefs.getString('store_subtitle') ?? defaults.storeSubtitle,
      addressLine1:
          prefs.getString('store_address_line1') ?? defaults.addressLine1,
      addressLine2:
          prefs.getString('store_address_line2') ?? defaults.addressLine2,
      tin: prefs.getString('store_tin') ?? defaults.tin,
      taxStatus: prefs.getString('store_tax_status') ?? defaults.taxStatus,
      posTerminalId:
          prefs.getString('store_pos_terminal_id') ?? defaults.posTerminalId,
      ptuNo: prefs.getString('store_ptu_no') ?? defaults.ptuNo,
      atpNo: prefs.getString('store_atp_no') ?? defaults.atpNo,
      atpDateIssued:
          prefs.getString('store_atp_date_issued') ?? defaults.atpDateIssued,
      seriesRange: prefs.getString('store_series_range') ?? defaults.seriesRange,
    );
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('store_logo_text', logoText);
    if (logoImagePath == null || logoImagePath!.isEmpty) {
      await prefs.remove('store_logo_image_path');
    } else {
      await prefs.setString('store_logo_image_path', logoImagePath!);
    }
    await prefs.setString('store_name', storeName);
    await prefs.setString('store_subtitle', storeSubtitle);
    await prefs.setString('store_address_line1', addressLine1);
    await prefs.setString('store_address_line2', addressLine2);
    await prefs.setString('store_tin', tin);
    await prefs.setString('store_tax_status', taxStatus);
    await prefs.setString('store_pos_terminal_id', posTerminalId);
    await prefs.setString('store_ptu_no', ptuNo);
    await prefs.setString('store_atp_no', atpNo);
    await prefs.setString('store_atp_date_issued', atpDateIssued);
    await prefs.setString('store_series_range', seriesRange);
  }

  static Future<String?> saveLogoImage(Uint8List bytes) async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/receipt_store_logo.png');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<void> deleteLogoImage(String? path) async {
    if (path == null || path.isEmpty || kIsWeb) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  factory ReceiptStoreConfig.fromJson(Map<String, dynamic> json) {
    const defaults = ReceiptStoreConfig();
    return ReceiptStoreConfig(
      logoText: (json['logo_text'] ?? defaults.logoText).toString(),
      storeName: (json['store_name'] ?? defaults.storeName).toString(),
      storeSubtitle:
          (json['store_subtitle'] ?? defaults.storeSubtitle).toString(),
      addressLine1:
          (json['address_line1'] ?? defaults.addressLine1).toString(),
      addressLine2:
          (json['address_line2'] ?? defaults.addressLine2).toString(),
      tin: (json['tin'] ?? defaults.tin).toString(),
      taxStatus: (json['tax_status'] ?? defaults.taxStatus).toString(),
      posTerminalId:
          (json['pos_terminal_id'] ?? defaults.posTerminalId).toString(),
      ptuNo: (json['ptu_no'] ?? defaults.ptuNo).toString(),
      atpNo: (json['atp_no'] ?? defaults.atpNo).toString(),
      atpDateIssued:
          (json['atp_date_issued'] ?? defaults.atpDateIssued).toString(),
      seriesRange: (json['series_range'] ?? defaults.seriesRange).toString(),
    );
  }

  Future<Map<String, dynamic>> toJson() async {
    String? logoBase64;
    if (logoImagePath != null && logoImagePath!.isNotEmpty && !kIsWeb) {
      final file = File(logoImagePath!);
      if (await file.exists()) {
        logoBase64 = base64Encode(await file.readAsBytes());
      }
    }

    return {
      'logo_text': logoText,
      'logo_image_url': null,
      'logo_image_base64': logoBase64,
      'store_name': storeName,
      'store_subtitle': storeSubtitle,
      'address_line1': addressLine1,
      'address_line2': addressLine2,
      'tin': tin,
      'tax_status': taxStatus,
      'pos_terminal_id': posTerminalId,
      'ptu_no': ptuNo,
      'atp_no': atpNo,
      'atp_date_issued': atpDateIssued,
      'series_range': seriesRange,
    };
  }

  static Future<ReceiptStoreConfig> applyApiPayload(
    Map<String, dynamic>? json,
  ) async {
    if (json == null || json.isEmpty) {
      return loadFromPrefs();
    }

    var config = ReceiptStoreConfig.fromJson(json);
    final logoBase64 = (json['logo_image_base64'] ?? '').toString().trim();
    if (logoBase64.isNotEmpty && !kIsWeb) {
      try {
        final bytes = base64Decode(
          logoBase64.contains(',')
              ? logoBase64.split(',').last
              : logoBase64,
        );
        final path = await saveLogoImage(bytes);
        if (path != null) {
          config = config.copyWith(logoImagePath: path);
        }
      } catch (_) {}
    }

    await config.saveToPrefs();
    return config;
  }
}

class ReceiptLineItem {
  const ReceiptLineItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  final String name;
  final int quantity;
  final double unitPrice;
  final double total;
}

class ReceiptData {
  ReceiptData({
    required this.orderId,
    required this.invoiceNumber,
    required this.customerName,
    required this.paymentMethod,
    required this.items,
    required this.subtotal,
    required this.vat,
    required this.discount,
    required this.manualDiscount,
    required this.couponDiscount,
    required this.loyaltyDiscount,
    required this.total,
    required this.amountTendered,
    required this.change,
    required this.currencySymbol,
    required this.cashierName,
    required this.itemCount,
    this.customerTin = '',
    this.customerAddress = '',
    this.reference = '',
    this.receiptNote = '',
    this.orderType = 'Retail',
    this.loyaltyPointsEarned = 0,
    this.loyaltyBalance = 0,
    this.isLoyaltyCustomer = false,
    this.isVatRegistered = false,
    this.store = const ReceiptStoreConfig(),
    this.splitPayments,
    DateTime? dateTime,
  }) : dateTime = dateTime ?? DateTime.now();

  final int orderId;
  final String invoiceNumber;
  final String customerName;
  final String customerTin;
  final String customerAddress;
  final String paymentMethod;
  final String orderType;
  final String reference;
  final String receiptNote;
  final String cashierName;
  final List<ReceiptLineItem> items;
  final int itemCount;
  final double subtotal;
  final double vat;
  final double discount;
  final double manualDiscount;
  final double couponDiscount;
  final double loyaltyDiscount;
  final double total;
  final double amountTendered;
  final double change;
  final String currencySymbol;
  final int loyaltyPointsEarned;
  final int loyaltyBalance;
  final bool isLoyaltyCustomer;
  final bool isVatRegistered;
  final ReceiptStoreConfig store;
  final List<ReceiptPaymentLine>? splitPayments;
  final DateTime dateTime;

  bool get hasSplitPayments =>
      splitPayments != null && splitPayments!.isNotEmpty;

  bool get includesCashPayment {
    if (hasSplitPayments) {
      return splitPayments!.any(
        (line) => line.paymentMethod.toLowerCase() == 'cash',
      );
    }
    return paymentMethod.toLowerCase() == 'cash';
  }
}

class ReceiptPaymentLine {
  const ReceiptPaymentLine({
    required this.paymentMethod,
    required this.amount,
    this.reference = '',
  });

  final String paymentMethod;
  final double amount;
  final String reference;
}

ReceiptData sampleReceiptPreview({
  required ReceiptStoreConfig store,
  String currencySymbol = '₱',
  double taxRate = 0,
}) {
  const subtotal = 960.0;
  final vat = taxRate > 0 ? subtotal * taxRate : 0.0;
  final total = subtotal + vat;
  const tendered = 1000.0;

  return ReceiptData(
    orderId: 1,
    invoiceNumber: 'INV-000001',
    customerName: 'Walk In Farmer',
    paymentMethod: 'Cash',
    items: const [
      ReceiptLineItem(
        name: 'ACC Feeds 40kg',
        quantity: 3,
        unitPrice: 320,
        total: 960,
      ),
    ],
    subtotal: subtotal,
    vat: vat,
    discount: 0,
    manualDiscount: 0,
    couponDiscount: 0,
    loyaltyDiscount: 0,
    total: total,
    amountTendered: tendered,
    change: tendered - total,
    currencySymbol: currencySymbol,
    cashierName: 'Cashier',
    itemCount: 1,
    isVatRegistered: taxRate > 0,
    store: store,
  );
}

class ThermalReceiptLayout {
  ThermalReceiptLayout(this.data);

  final ReceiptData data;

  List<String> buildLines() {
    final s = data.store;
    final lines = <String>[];

    void add(String? line) {
      if (line != null && line.isNotEmpty) lines.add(line);
    }

    add(_center(s.logoText.trim().isEmpty ? '[ Store ]' : s.logoText.trim()));
    add('');
    add(_center(s.storeName));
    add(_center(s.storeSubtitle));
    add(_center(s.addressLine1));
    add(_center(s.addressLine2));
    add('');
    add(_center('INVOICE'));
    add('');
    add(_labelValue('INV NO', data.invoiceNumber));
    add(_labelValue('DATE', _formatDate(data.dateTime)));
    add(_labelValue('TIME', _formatTime(data.dateTime)));
    add(_labelValue('CASHIER', _shortCashier(data.cashierName)));
    add(_labelValue('POS', s.posTerminalId));
    add('');
    add(_labelValue('CUSTOMER', _clip(data.customerName, 22)));
    final customerTin = _clip(data.customerTin, 22);
    if (customerTin.isNotEmpty) {
      add(_labelValue('TIN', customerTin));
    }
    final customerAddress = _clip(data.customerAddress, 22);
    if (customerAddress.isNotEmpty) {
      add(_labelValue('ADDRESS', customerAddress));
    }
    if (data.isLoyaltyCustomer || data.loyaltyPointsEarned > 0) {
      add(_labelValue('POINTS EARNED', '${data.loyaltyPointsEarned}'));
      add(_labelValue('TOTAL POINTS', '${data.loyaltyBalance}'));
    }
    add('');
    add(_divider());
    for (final item in data.items) {
      lines.addAll(_formatItemLines(item));
    }
    add(_divider());
    final totalDiscount =
        data.manualDiscount + data.couponDiscount + data.loyaltyDiscount;
    add(_amountRow('SUBTOTAL', _money(data.subtotal)));
    if (totalDiscount > 0) {
      add(_amountRow('DISCOUNT', _money(-totalDiscount)));
    }
    if (data.vat > 0) {
      add(_amountRow('VAT', _money(data.vat)));
    }
    add(_shortDivider());
    add(_amountRow('TOTAL', _money(data.total), emphasize: true));
    add(_shortDivider());
    if (data.hasSplitPayments) {
      for (final payment in data.splitPayments!) {
        add(_amountRow(payment.paymentMethod, _money(payment.amount)));
        if (payment.reference.trim().isNotEmpty) {
          add(_labelValue('Ref', payment.reference.trim()));
        }
      }
    } else if (data.paymentMethod.toLowerCase() == 'cash') {
      add(_amountRow('Cash', _money(data.amountTendered)));
      add(_amountRow('Change', _money(data.change)));
    }
    add(_labelValue('Payment Type', data.paymentMethod));
    add(_amountRow('Total Qty', '${data.itemCount}'));
    _addReceiptFooter(add, receiptNote: data.receiptNote);

    return lines;
  }

  /// On-screen preview lines — matches the web admin receipt preview layout.
  List<String> buildPreviewLines() {
    final s = data.store;
    final lines = <String>[];

    void add(String? line) {
      if (line != null && line.isNotEmpty) {
        lines.add(line.trim());
      }
    }

    String previewMoney(double amount) =>
        '${data.currencySymbol}${amount.toStringAsFixed(2)}';

    String previewLabelValue(String label, String value) {
      final gap = kThermalWidth - label.length - value.length;
      if (gap >= 1) {
        return '$label${' ' * gap}$value';
      }
      return '$label $value';
    }

    add(s.logoText.trim().isEmpty ? '[ Store ]' : s.logoText.trim());
    add('');
    add(s.storeName);
    add(s.storeSubtitle);
    add(s.addressLine1);
    add(s.addressLine2);
    add('');
    add('INVOICE');
    add('');
    add(previewLabelValue('INV NO', data.invoiceNumber));
    add(previewLabelValue('DATE', _formatDate(data.dateTime)));
    add(previewLabelValue('TIME', _formatTime(data.dateTime)));
    add(previewLabelValue('CASHIER', _shortCashier(data.cashierName)));
    add(previewLabelValue('POS', s.posTerminalId));
    add('');
    add(previewLabelValue('CUSTOMER', _clip(data.customerName, 22)));
    if (data.isLoyaltyCustomer || data.loyaltyPointsEarned > 0) {
      add(previewLabelValue('POINTS EARNED', '${data.loyaltyPointsEarned}'));
      add(previewLabelValue('TOTAL POINTS', '${data.loyaltyBalance}'));
    }
    add('');
    add(_divider());
    if (data.items.isNotEmpty) {
      for (final item in data.items) {
        for (final line in _formatItemLines(item)) {
          add(line);
        }
      }
    } else {
      add(
        _composeItemLine(
          name: 'Sample Product',
          unitPrice: data.subtotal,
          quantity: 1,
          total: data.subtotal,
        ),
      );
    }
    add(_divider());
    add(previewLabelValue('SUBTOTAL', previewMoney(data.subtotal)));
    if (data.vat > 0) {
      add(previewLabelValue('VAT', previewMoney(data.vat)));
    }
    add(_doubleDivider());
    add(previewLabelValue('TOTAL', previewMoney(data.total)));
    add(_shortDivider());
    if (data.hasSplitPayments) {
      for (final payment in data.splitPayments!) {
        add(previewLabelValue(payment.paymentMethod, previewMoney(payment.amount)));
        if (payment.reference.trim().isNotEmpty) {
          add(previewLabelValue('Ref', payment.reference.trim()));
        }
      }
    } else if (data.paymentMethod.toLowerCase() == 'cash') {
      add(previewLabelValue('Cash', previewMoney(data.amountTendered)));
      add(previewLabelValue('Change', previewMoney(data.change)));
    }
    add(previewLabelValue('Payment Type', data.paymentMethod));
    add(previewLabelValue('Total Qty', '${data.itemCount}'));
    _addReceiptFooter(add, receiptNote: data.receiptNote);

    return lines;
  }

  List<String> buildTextLines() => buildLines();

  static void _addReceiptFooter(
    void Function(String? line) add, {
    String receiptNote = '',
  }) {
    add('');
    final note = receiptNote.trim();
    if (note.isNotEmpty) {
      add(_center('NOTE:'));
      for (final line in _wrapCenteredLines(note, kThermalWidth)) {
        add(line);
      }
      add('');
    }
    add(_center(kReceiptFooterThanks));
    add('');
    add(_center('NO REFUND POLICY'));
    add(_center('3 DAYS EXCHANGE POLICY'));
    add(_center('WITH PENALTY'));
    add('');
  }

  static String centerLine(String text) {
    return _center(text);
  }

  static bool _isGrandTotalLine(String line, String totalText) {
    final trimmed = line.trim();
    return trimmed.startsWith('TOTAL') &&
        !trimmed.startsWith('TOTAL POINTS') &&
        !trimmed.startsWith('Total Qty') &&
        trimmed.contains(totalText);
  }

  String formatMoney(double value) => _money(value);

  static String _center(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length >= kThermalWidth) {
      return trimmed.substring(0, kThermalWidth);
    }
    final pad = ((kThermalWidth - trimmed.length) / 2).floor();
    return '${' ' * pad}$trimmed'.padRight(kThermalWidth);
  }

  static List<String> _wrapCenteredLines(String text, int width) {
    final words = text.trim().split(RegExp(r'\s+'));
    final wrapped = <String>[];
    var current = '';

    for (final word in words) {
      if (word.isEmpty) continue;
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= width) {
        current = candidate;
        continue;
      }
      if (current.isNotEmpty) {
        wrapped.add(_center(current));
      }
      if (word.length > width) {
        var remaining = word;
        while (remaining.length > width) {
          wrapped.add(_center(remaining.substring(0, width)));
          remaining = remaining.substring(width);
        }
        current = remaining;
      } else {
        current = word;
      }
    }

    if (current.isNotEmpty) {
      wrapped.add(_center(current));
    }

    return wrapped;
  }

  static String _divider() => '-' * kThermalWidth;

  static String _doubleDivider() => '=' * kThermalWidth;

  static String _shortDivider() {
    const dots = '-------- --------';
    final leftPadded = dots.padLeft(
      ((kThermalWidth + dots.length) ~/ 2).clamp(0, kThermalWidth),
    );
    return leftPadded.padRight(kThermalWidth).substring(0, kThermalWidth);
  }

  static String _labelValue(String label, String value) {
    const gap = ': ';
    final prefix = '$label$gap';
    final space = kThermalWidth - prefix.length - value.length;
    if (space >= 1) {
      return '$prefix${' ' * space}$value';
    }
    return ('$prefix$value').padRight(kThermalWidth).substring(0, kThermalWidth);
  }

  static const _amountColWidth = 10;

  static String _amountRow(String label, String amount, {bool emphasize = false}) {
    final amountCol = amount.length > _amountColWidth
        ? amount
        : amount.padLeft(_amountColWidth);
    final space = kThermalWidth - label.length - amountCol.length;
    if (space >= 1) {
      return '$label${' ' * space}$amountCol';
    }
    final maxLabel = (kThermalWidth - amountCol.length - 1).clamp(0, label.length);
    final trimmedLabel = label.substring(0, maxLabel);
    final gap = kThermalWidth - trimmedLabel.length - amountCol.length;
    if (gap >= 1) {
      return '$trimmedLabel${' ' * gap}$amountCol';
    }
    return ('$trimmedLabel $amountCol').padRight(kThermalWidth).substring(0, kThermalWidth);
  }

  String _money(double value) {
    final negative = value < 0;
    final abs = value.abs();
    final fixed = abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts[0];
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    final formatted = '$buffer.${parts[1]}';
    return negative ? '-$formatted' : formatted;
  }

  String _formatUnitPrice(double price) {
    final rounded = (price * 100).round() / 100;
    if ((rounded - rounded.roundToDouble()).abs() < 0.001) {
      return rounded.toInt().toString();
    }
    return rounded.toStringAsFixed(2);
  }

  String _composeItemLine({
    required String name,
    required double unitPrice,
    required int quantity,
    required double total,
  }) {
    final lines = _formatItemLines(
      ReceiptLineItem(
        name: name,
        quantity: quantity,
        unitPrice: unitPrice,
        total: total,
      ),
    );
    return lines.first;
  }

  String? _lineWithRightAmount(String left, String amountCol) {
    const amountWidth = 8;
    final normalized = left.trimRight();
    final spaces = kThermalWidth - normalized.length - amountWidth;
    if (spaces >= 1) {
      return '$normalized${' ' * spaces}$amountCol';
    }
    return null;
  }

  List<String> _formatItemLines(ReceiptLineItem item) {
    const amountWidth = 8;
    final amountCol = _money(item.total).padLeft(amountWidth);
    final meta = '@${_formatUnitPrice(item.unitPrice)}x${item.quantity}';
    final name = item.name.trim();
    final result = <String>[];

    final combined = '$name $meta';
    final singleLine = _lineWithRightAmount(combined, amountCol);
    if (singleLine != null) {
      result.add(singleLine);
    } else {
      var remaining = name;
      while (remaining.length > kThermalWidth) {
        result.add(remaining.substring(0, kThermalWidth));
        remaining = remaining.substring(kThermalWidth).trimLeft();
      }

      final descriptor = remaining.isEmpty ? meta : '$remaining $meta';
      final descriptorLine = _lineWithRightAmount(descriptor, amountCol);
      if (descriptorLine != null) {
        result.add(descriptorLine);
      } else {
        if (remaining.isNotEmpty) {
          result.add(remaining);
        }
        result.add(
          _lineWithRightAmount(meta, amountCol) ??
              amountCol.padLeft(kThermalWidth),
        );
      }
    }

    final gross = item.unitPrice * item.quantity;
    final lineDiscount = gross - item.total;
    if (lineDiscount > 0.009 && gross > 0) {
      final pct = lineDiscount / gross * 100;
      result.add(
        '${_money(lineDiscount)} discount @${pct.toStringAsFixed(2)}%',
      );
    }

    return result;
  }

  static String _formatDate(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$m/$d/${dt.year}';
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h12:$m $ampm';
  }

  static String _shortCashier(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'CASHIER';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.toUpperCase().substring(0, parts.first.length.clamp(0, 8));
    }
    return parts.first.toUpperCase();
  }

  static String _clip(String value, int max) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= max) return trimmed;
    return trimmed.substring(0, max);
  }
}

class _EscPosBuilder {
  final List<int> _bytes = <int>[];

  void init() => _bytes.addAll(<int>[0x1B, 0x40]);

  void text(
    String value, {
    bool bold = false,
    bool center = false,
    bool doubleHeight = false,
  }) {
    if (center) _bytes.addAll(<int>[0x1B, 0x61, 0x01]);
    if (bold) _bytes.addAll(<int>[0x1B, 0x45, 0x01]);
    if (doubleHeight) _bytes.addAll(<int>[0x1D, 0x21, 0x10]);

    for (final line in value.split('\n')) {
      _bytes.addAll('$line\n'.codeUnits);
    }

    if (doubleHeight) _bytes.addAll(<int>[0x1D, 0x21, 0x00]);
    if (bold) _bytes.addAll(<int>[0x1B, 0x45, 0x00]);
    if (center) _bytes.addAll(<int>[0x1B, 0x61, 0x00]);
  }

  void feed(int lines) => _bytes.addAll(<int>[0x1B, 0x64, lines]);

  void cut() => _bytes.addAll(<int>[0x1D, 0x56, 0x00]);

  List<int> build() => List<int>.from(_bytes);
}

class PosReceiptService {
  static Future<bool> printReceiptAndOpenDrawer({
    required ReceiptData receipt,
    required bool autoPrint,
    required bool openDrawer,
    PrinterConfig? printer,
    String? printerHost,
  }) async {
    if (!autoPrint) return false;

    await printReceipt(
      receipt: receipt,
      printer: printer,
      printerHost: printerHost,
      openDrawer: openDrawer,
    );
    return true;
  }

  /// Silent post-payment handling — never opens system PDF UI.
  static Future<bool> autoPrintOnComplete({
    required ReceiptData receipt,
    required bool autoPrint,
    required bool openDrawer,
    bool doublePrint = false,
    PrinterConfig? printer,
    String? printerHost,
  }) async {
    final config = printer ?? _legacyPrinterConfig(printerHost);
    if (!autoPrint || kIsWeb || !config.isConfigured) {
      if (openDrawer && !kIsWeb && config.isConfigured) {
        await openCashDrawer(printer: config);
      }
      return true;
    }

    try {
      await printReceipt(
        receipt: receipt,
        printer: config,
        openDrawer: openDrawer,
      );
      if (doublePrint) {
        await printReceipt(
          receipt: receipt,
          printer: config,
          openDrawer: false,
        );
      }
    } catch (error) {
      debugPrint('Auto print: $error');
    }

    return true;
  }

  static Future<Uint8List> buildPdfBytes(ReceiptData receipt) {
    return _buildPdfDocument(receipt);
  }

  static Future<void> printReceipt({
    required ReceiptData receipt,
    PrinterConfig? printer,
    String? printerHost,
    bool openDrawer = false,
    String? missingHostMessage,
  }) async {
    final config = printer ?? _legacyPrinterConfig(printerHost);
    if (!config.isConfigured) {
      throw ReceiptPrintException(
        missingHostMessage ??
            'Store printer is not set up yet. Ask your manager or admin to configure it.',
      );
    }

    await PrinterTransport.sendEscPos(
      config: config,
      bytes: _buildEscPosBytes(receipt),
      openDrawer: openDrawer,
    );
  }

  static Future<void> downloadReceipt(ReceiptData receipt) async {
    final bytes = await buildPdfBytes(receipt);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'receipt_${receipt.invoiceNumber}.pdf',
    );
  }

  static Future<void> openCashDrawer({
    PrinterConfig? printer,
    String? printerHost,
  }) async {
    if (kIsWeb) return;

    final config = printer ?? _legacyPrinterConfig(printerHost);
    if (!config.isConfigured) return;

    try {
      await PrinterTransport.sendEscPos(
        config: config,
        bytes: const [],
        openDrawer: true,
      );
    } catch (error) {
      debugPrint('Cash drawer: $error');
    }
  }

  static PrinterConfig _legacyPrinterConfig(String? printerHost) {
    final host = (printerHost ?? '').trim();
    if (host.isEmpty) {
      return const PrinterConfig();
    }
    return PrinterConfig(host: host);
  }

  static List<int> _buildEscPosBytes(ReceiptData receipt) {
    final layout = ThermalReceiptLayout(receipt);
    final lines = layout.buildLines();
    final totalText = layout.formatMoney(receipt.total);
    final builder = _EscPosBuilder()..init();

    for (final line in lines) {
      if (line.isEmpty) {
        builder.text('');
        continue;
      }
      if (line == ThermalReceiptLayout.centerLine(receipt.store.storeName)) {
        builder.text(
          receipt.store.storeName,
          center: true,
          bold: true,
          doubleHeight: true,
        );
        continue;
      }
      if (line == ThermalReceiptLayout.centerLine('INVOICE')) {
        builder.text('INVOICE', center: true, bold: true);
        continue;
      }
      if (ThermalReceiptLayout._isGrandTotalLine(line, totalText)) {
        builder.text(line, bold: true);
        continue;
      }
      if (line == ThermalReceiptLayout.centerLine(kReceiptFooterThanks)) {
        builder.text(kReceiptFooterThanks, center: true, bold: true);
        continue;
      }

      final centered = line == ThermalReceiptLayout.centerLine(line.trim());
      builder.text(line, center: centered);
    }

    builder.feed(4);
    builder.cut();
    return builder.build();
  }

  static Future<Uint8List> _buildPdfDocument(ReceiptData receipt) async {
    final doc = pw.Document();
    final layout = ThermalReceiptLayout(receipt);
    final pageFormat = PdfPageFormat(
      58 * PdfPageFormat.mm,
      double.infinity,
      marginLeft: 2 * PdfPageFormat.mm,
      marginRight: 2 * PdfPageFormat.mm,
      marginTop: 2 * PdfPageFormat.mm,
      marginBottom: 2 * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final line in layout.buildLines())
                pw.Text(
                  line,
                  style: pw.TextStyle(
                    fontSize: 9,
                    font: pw.Font.courier(),
                    lineSpacing: 1.2,
                    fontWeight: line.contains(receipt.store.storeName) ||
                            ThermalReceiptLayout._isGrandTotalLine(
                              line,
                              layout.formatMoney(receipt.total),
                            ) ||
                            line.contains('INVOICE') ||
                            line.contains(kReceiptFooterThanks)
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
