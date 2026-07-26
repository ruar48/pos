import '../core/utils/format_utils.dart';

enum CouponDiscountType { fixed, percentage }

class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.startDate,
    required this.endDate,
    this.description,
    this.minOrderAmount = 0,
    this.maxUses,
    this.usageCount = 0,
    this.isActive = true,
    this.createdAt,
  });

  final int id;
  final String code;
  final String? description;
  final CouponDiscountType discountType;
  final double discountValue;
  final double minOrderAmount;
  final DateTime startDate;
  final DateTime endDate;
  final int? maxUses;
  final int usageCount;
  final bool isActive;
  final DateTime? createdAt;

  factory Coupon.fromJson(Map<String, dynamic> json) {
    final typeRaw = (json['discount_type'] ?? 'fixed').toString().toLowerCase();
    return Coupon(
      id: toInt(json['id']),
      code: (json['code'] ?? '').toString().toUpperCase(),
      description: json['description']?.toString(),
      discountType: typeRaw == 'percentage'
          ? CouponDiscountType.percentage
          : CouponDiscountType.fixed,
      discountValue: toDouble(json['discount_value']),
      minOrderAmount: toDouble(json['min_order_amount']),
      startDate: _parseDate(json['start_date']),
      endDate: _parseDate(json['end_date']),
      maxUses: json['max_uses'] == null ? null : toInt(json['max_uses']),
      usageCount: toInt(json['usage_count']),
      isActive: json['status'] == true || json['status'].toString() == '1',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }

  static DateTime _parseDate(dynamic value) {
    final raw = value?.toString() ?? '';
    return DateTime.tryParse(raw) ?? DateTime.now();
  }

  bool get isCurrentlyValid {
    if (!isActive) return false;
    final today = DateTime.now();
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    if (today.isBefore(start) || today.isAfter(end)) return false;
    if (maxUses != null && usageCount >= maxUses!) return false;
    return true;
  }

  bool meetsMinimumOrder(double subtotal) => subtotal >= minOrderAmount;

  double discountForSubtotal(double subtotal) {
    if (subtotal <= 0 || !isCurrentlyValid || !meetsMinimumOrder(subtotal)) {
      return 0;
    }

    if (discountType == CouponDiscountType.percentage) {
      return (subtotal * (discountValue / 100)).clamp(0, subtotal).toDouble();
    }

    return discountValue.clamp(0, subtotal).toDouble();
  }

  String discountLabel(String currencySymbol) {
    if (discountType == CouponDiscountType.percentage) {
      final trimmed = discountValue % 1 == 0
          ? discountValue.toInt().toString()
          : discountValue.toStringAsFixed(1);
      return '$trimmed% off';
    }
    return formatMoney(currencySymbol, discountValue);
  }

  String get statusLabel {
    if (!isActive) return 'Inactive';
    if (!isCurrentlyValid) {
      final today = DateTime.now();
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      if (today.isBefore(start)) return 'Scheduled';
      return 'Expired';
    }
    return 'Active';
  }
}
