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
    this.refundedAmount = 0,
    this.itemRefundedQuantities = const [],
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

  /// Units sold on the order (before refunds). A double because goods sold
  /// by weight/volume come through as decimals ("2.500").
  final double itemCount;
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

  /// Money already paid back on this order (VAT included, like [total]).
  final double refundedAmount;

  /// refunded_quantity of each entry in [items], same order; may be empty
  /// for records that carry no per-line refund data.
  final List<double> itemRefundedQuantities;

  double get _itemDiscountSum =>
      items.fold<double>(0, (sum, item) => sum + item.discount);

  /// Manual + item-level discount (see [totalDiscount] for the max()).
  double get manualDiscount => max(discountAmount, _itemDiscountSum);

  // Never let the aggregated total undercount what each item row already
  // shows - the backend's combined discount_amount should already cover
  // the item-level portion, but max() guards against it lagging behind
  // the per-item fallback (see SalesLineItem.discount).
  double get totalDiscount => manualDiscount + couponDiscount + loyaltyDiscount;

  /// Price of the goods before any discount. subtotal is stored net of
  /// every discount (manual, item, coupon, loyalty), so they are added back.
  double get grossSubtotal => subtotal + totalDiscount;

  bool get isWalkIn =>
      customerId == null || customerId! <= 0 || Customer.isWalkInName(customerName);

  double refundedQuantityAt(int index) =>
      index >= 0 && index < itemRefundedQuantities.length
          ? itemRefundedQuantities[index]
          : 0;

  bool get _hasRefundedUnits =>
      itemRefundedQuantities.any((quantity) => quantity > 0.0005);

  bool get _allUnitsReturned {
    if (items.isEmpty) return false;
    for (var i = 0; i < items.length; i++) {
      if (items[i].quantity - refundedQuantityAt(i) > 0.0005) return false;
    }
    return true;
  }

  bool get hasRefund => refundedAmount > 0.005 || _hasRefundedUnits;

  /// Everything on the order was given back - it is no longer a sale.
  bool get isFullyRefunded {
    if (status == 'refunded') return true;
    if (total > 0.005) return refundedAmount >= total - 0.005;
    // A ₱0 order (fully discounted) refunds no money; it is refunded once
    // every unit has come back.
    return _allUnitsReturned;
  }

  /// What the store kept from this order: total less refunds.
  double get netTotal =>
      isFullyRefunded ? 0 : max(0.0, total - refundedAmount);

  /// Share of the order still sold after refunds (1 = untouched).
  double get netFactor {
    if (isFullyRefunded) return 0;
    if (total <= 0.005) return 1;
    return netTotal / total;
  }

  double get netVat => vat * netFactor;

  double get netSubtotal => subtotal * netFactor;

  /// Line items reduced to what was not refunded. Lines are scaled by their
  /// own remaining quantity; an older refund that recorded only an amount
  /// (no refunded_quantity) scales every line by the money still kept.
  List<SalesLineItem> get netItems {
    if (isFullyRefunded) return const [];
    if (!hasRefund) return items;

    final byUnits = _hasRefundedUnits;
    final moneyFactor = netFactor;
    final result = <SalesLineItem>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final double remaining;
      final double factor;
      if (byUnits) {
        remaining = max(0.0, item.quantity - refundedQuantityAt(i));
        factor = item.quantity > 0 ? remaining / item.quantity : 1.0;
      } else {
        factor = moneyFactor;
        remaining = item.quantity * factor;
      }
      if (remaining <= 0.0005) continue;
      result.add(
        factor >= 1
            ? item
            : SalesLineItem(
                productId: item.productId,
                productName: item.productName,
                quantity: remaining,
                price: item.price,
                total: item.total * factor,
                discount: item.discount * factor,
                varietyId: item.varietyId,
                varietyName: item.varietyName,
              ),
      );
    }
    return result;
  }

  /// Units still sold after refunds.
  double get netItemCount =>
      netItems.fold<double>(0, (sum, item) => sum + item.quantity);

  factory SalesHistoryRecord.fromOrderJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    final lineItems = rawItems.map(SalesLineItem.fromJson).toList();
    // Quantities arrive as DECIMAL strings ("2.000") - parse as doubles;
    // int parsing turned every one of them into 0.
    final itemCount =
        lineItems.fold<double>(0, (sum, item) => sum + item.quantity);
    final refundedQuantities = rawItems
        .map((raw) => max(0.0, toDouble(raw['refunded_quantity'])))
        .toList();

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
      refundedAmount: max(0.0, toDouble(json['refunded_amount'])),
      itemRefundedQuantities: refundedQuantities,
    );
  }
}
