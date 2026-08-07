import 'dart:math';

import '../core/utils/format_utils.dart';
import 'customer.dart';
import 'sales_line_item.dart';

class SalesHistoryRecord {
  const SalesHistoryRecord({
    required this.localId,
    required this.orderId,
    this.customerId,
    this.branchId,
    this.branchName,
    this.cashierUserId,
    this.cashierName,
    required this.customerName,
    required this.paymentMethod,
    required this.itemCount,
    required this.subtotal,
    required this.discountAmount,
    required this.couponDiscount,
    required this.loyaltyDiscount,
    required this.loyaltyPointsRedeemed,
    required this.vat,
    required this.total,
    required this.clientChange,
    required this.reference,
    required this.status,
    required this.createdAt,
    required this.items,
  });

  final int localId;
  final int orderId;
  final int? customerId;
  final int? branchId;
  final String? branchName;
  final int? cashierUserId;
  final String? cashierName;
  final String customerName;
  final String paymentMethod;
  final int itemCount;
  final double subtotal;
  final double discountAmount;
  final double couponDiscount;
  final double loyaltyDiscount;
  final int loyaltyPointsRedeemed;
  final double vat;
  final double total;
  final double clientChange;
  final String reference;
  final String status;
  final DateTime createdAt;
  final List<SalesLineItem> items;

  double get _itemDiscountSum =>
      items.fold<double>(0, (sum, item) => sum + item.discount);

  // Never let the aggregated total undercount what each item row already
  // shows - the backend's combined discount_amount should already cover
  // the item-level portion, but max() guards against it lagging behind
  // the per-item fallback (see SalesLineItem.discount).
  double get totalDiscount =>
      max(discountAmount, _itemDiscountSum) + couponDiscount + loyaltyDiscount;

  bool get isWalkIn =>
      customerId == null || customerId! <= 0 || Customer.isWalkInName(customerName);

  factory SalesHistoryRecord.fromOrderJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const []);
    final lineItems = items
        .whereType<Map>()
        .map((raw) => SalesLineItem.fromJson(Map<String, dynamic>.from(raw)))
        .toList();
    final itemCount = items.fold<int>(0, (sum, item) {
      if (item is! Map<String, dynamic>) return sum;
      return sum + toInt(item['quantity']);
    });

    final rawCustomerId = json['customer_id'];
    final parsedCustomerId =
        rawCustomerId == null ? null : toInt(rawCustomerId);
    final rawBranchId = json['branch_id'];
    final parsedBranchId = rawBranchId == null ? 1 : toInt(rawBranchId);

    return SalesHistoryRecord(
      localId: toInt(json['id']),
      orderId: toInt(json['id']),
      customerId: parsedCustomerId != null && parsedCustomerId > 0
          ? parsedCustomerId
          : null,
      branchId: parsedBranchId > 0 ? parsedBranchId : 1,
      branchName: (json['branch_name'] ?? 'Main Branch').toString(),
      cashierUserId: json['cashier_user_id'] == null
          ? null
          : toInt(json['cashier_user_id']),
      cashierName: json['cashier_name']?.toString(),
      customerName: (json['customer_name'] ?? 'Walk In Farmer').toString(),
      paymentMethod: (json['payment_method'] ?? 'Cash').toString(),
      itemCount: itemCount,
      subtotal: toDouble(json['subtotal']),
      discountAmount: toDouble(json['discount_amount']),
      couponDiscount: toDouble(json['coupon_discount']),
      loyaltyDiscount: toDouble(json['loyalty_discount']),
      loyaltyPointsRedeemed: toInt(json['loyalty_points_redeemed']),
      vat: toDouble(json['vat']),
      total: toDouble(json['total_amount']),
      clientChange: toDouble(json['client_change']),
      reference: (json['reference'] ?? '').toString(),
      status: (json['status'] ?? 'completed').toString(),
      createdAt: parseServerDateTime((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      items: lineItems,
    );
  }
}
