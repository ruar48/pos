int toInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// Send a true UTC instant to Laravel (always ends with Z).
String formatApiUtcDateTime(DateTime value) {
  final utc = value.toUtc();
  final iso = utc.toIso8601String();
  if (iso.endsWith('Z')) {
    return iso;
  }
  return '${iso}Z';
}

/// API datetimes from Laravel/MySQL are Philippines local wall clock (no zone suffix).
DateTime? parseServerDateTime(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  var normalized = value.trim();
  if (!normalized.contains('T')) {
    normalized = normalized.replaceFirst(' ', 'T');
  }
  final hasZone = normalized.endsWith('Z') ||
      RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(normalized);
  if (!hasZone) {
    // Stored as Asia/Manila wall clock — parse as local components.
    final parts = normalized.split('T');
    if (parts.length == 2) {
      final date = parts[0].split('-');
      final time = parts[1].split(':');
      if (date.length == 3 && time.length >= 2) {
        return DateTime(
          int.parse(date[0]),
          int.parse(date[1]),
          int.parse(date[2]),
          int.parse(time[0]),
          int.parse(time[1]),
          time.length > 2 ? int.parse(time[2].split('.').first) : 0,
        );
      }
    }
  }
  return DateTime.tryParse(normalized)?.toLocal();
}

String formatMoney(String currencySymbol, double value) {
  return '$currencySymbol${value.toStringAsFixed(2)}';
}

bool shouldShowRefundedAmount(String status, double value) {
  return status == 'refunded' && value.abs() < 0.01;
}

String formatReportMoney(
  String currencySymbol,
  double value, {
  String status = 'completed',
}) {
  if (shouldShowRefundedAmount(status, value)) {
    return 'Refunded';
  }

  return formatMoney(currencySymbol, value);
}

String formatRefundColumn(String currencySymbol, double value) {
  if (value < 0.01) {
    return '—';
  }

  return formatMoney(currencySymbol, value);
}

String generateProductSku(String name, {DateTime? timestamp}) {
  final cleaned = name
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  final time = timestamp ?? DateTime.now();
  final stamp =
      '${time.hour.toString().padLeft(2, '0')}'
      '${time.minute.toString().padLeft(2, '0')}'
      '${time.second.toString().padLeft(2, '0')}';

  if (cleaned.isEmpty) {
    return 'SKU-$stamp';
  }

  return 'SKU-$cleaned-$stamp';
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatShortDate(DateTime value) {
  final month = _monthNames[value.month - 1];
  return '$month ${value.day}, ${value.year}';
}

String formatDateTime(DateTime? value) {
  if (value == null) return '-';
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final meridiem = value.hour >= 12 ? 'PM' : 'AM';
  return '${formatShortDate(value)} $hour:$minute $meridiem';
}
