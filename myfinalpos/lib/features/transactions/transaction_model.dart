import 'dart:math';

import '../../core/utils/format_utils.dart';
import '../../models/order_payment.dart';

int _toInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class TransactionItem {
  const TransactionItem({
    required this.id,
    required this.orderId,
    required this.orderItemId,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.varietyName,
    required this.quantity,
    required this.refundedQuantity,
    required this.unitPrice,
    required this.discount,
    required this.subtotal,
    required this.imageUrl,
  });

  final int id;
  final int orderId;
  final int orderItemId;
  final int productId;
  final String productName;
  final String sku;
  final String? varietyName;
  final double quantity;
  final double refundedQuantity;
  final double unitPrice;
  final double discount;
  final double subtotal;
  final String? imageUrl;

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    final quantity = _toDouble(json['quantity']);
    final unitPrice = _toDouble(json['price'] ?? json['unit_price']);
    final subtotal = _toDouble(json['total']);
    final rawSku = json['sku'] ?? json['product_sku'];

    return TransactionItem(
      id: _toInt(json['id']),
      orderId: _toInt(json['order_id']),
      orderItemId: _toInt(json['order_item_id'] ?? json['id']),
      productId: _toInt(json['product_id']),
      productName: json['product_name']?.toString() ??
          json['name']?.toString() ??
          'Unknown item',
      sku: rawSku?.toString() ?? 'SKU-${json['product_id'] ?? '000'}',
      varietyName: json['variety_name']?.toString(),
      quantity: quantity,
      refundedQuantity: _toDouble(json['refunded_quantity']),
      unitPrice: unitPrice,
      discount: max(
        _toDouble(json['discount_amount']),
        max(0.0, (unitPrice * quantity) - subtotal),
      ),
      subtotal: subtotal,
      imageUrl: json['image']?.toString() ?? json['image_url']?.toString(),
    );
  }

  bool get hasRefundableQuantity => quantity - refundedQuantity > 0;

  double get remainingQuantity =>
      quantity - refundedQuantity < 0 ? 0 : quantity - refundedQuantity;

  double get refundedAmount {
    if (refundedQuantity <= 0 || quantity <= 0) return 0;
    return subtotal * refundedQuantity / quantity;
  }

  double get remainingSubtotal => subtotal - refundedAmount;
}

class TransactionRecord {
  TransactionRecord({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerType,
    required this.paymentMethod,
    required this.reference,
    required this.status,
    required this.cashierName,
    required this.createdAt,
    required this.subtotal,
    required this.discountAmount,
    required this.couponDiscount,
    required this.loyaltyDiscount,
    required this.loyaltyPointsRedeemed,
    required this.vat,
    required this.serviceCharge,
    required this.totalAmount,
    required this.refundedAmount,
    required this.changeAmount,
    required this.items,
    this.splitPayments = const [],
  });

  final int id;
  final int customerId;
  final String customerName;
  final String customerType;
  final String paymentMethod;
  final String reference;
  final String status;
  final String cashierName;
  final DateTime createdAt;
  final double subtotal;
  final double discountAmount;
  final double couponDiscount;
  final double loyaltyDiscount;
  final int loyaltyPointsRedeemed;
  final double vat;
  final double serviceCharge;
  final double totalAmount;
  final double refundedAmount;
  final double changeAmount;
  final List<TransactionItem> items;
  final List<OrderPayment> splitPayments;

  bool get isSplitPayment {
    if (splitPayments.length >= 2) return true;
    return paymentMethod.toLowerCase().startsWith('split');
  }

  String get paymentSummaryLabel {
    if (isSplitPayment) {
      return 'Split (${splitPayments.map((p) => p.paymentMethod).join(' + ')})';
    }
    return paymentMethod;
  }

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) => TransactionItem.fromJson(Map<String, dynamic>.from(raw)))
        .toList();
    final payments = (json['payments'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) => OrderPayment.fromJson(Map<String, dynamic>.from(raw)))
        .toList();

    return TransactionRecord(
      id: _toInt(json['id']),
      customerId: _toInt(json['customer_id']),
      customerName: (json['customer_name'] ?? 'Walk In Farmer').toString(),
      customerType: (json['customer_type'] ??
              json['customer_order_type'] ??
              'Retail')
          .toString(),
      paymentMethod: (json['payment_method'] ?? 'Cash').toString(),
      reference: (json['reference'] ?? '').toString(),
      status: (json['status'] ?? 'completed').toString(),
      cashierName: (json['cashier_name'] ?? 'Cashier').toString(),
      createdAt: parseServerDateTime((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      subtotal: _toDouble(json['subtotal']),
      discountAmount: _toDouble(json['discount_amount']),
      couponDiscount: _toDouble(json['coupon_discount']),
      loyaltyDiscount: _toDouble(json['loyalty_discount']),
      loyaltyPointsRedeemed: _toInt(json['loyalty_points_redeemed']),
      vat: _toDouble(json['vat']),
      serviceCharge: _toDouble(json['service_charge']),
      totalAmount: _toDouble(json['total_amount']),
      refundedAmount: _toDouble(json['refunded_amount']),
      changeAmount: _toDouble(json['client_change'] ?? json['change_amount']),
      items: items,
      splitPayments: payments,
    );
  }

  String get receiptNumber => 'RCP-${id.toString().padLeft(6, '0')}';

  double get grandTotal => totalAmount;

  bool get hasRefunds => refundedAmount > 0.009;

  double get remainingTotal {
    final remaining = grandTotal - refundedAmount;
    return remaining < 0 ? 0 : remaining;
  }

  List<TransactionItem> get refundedItems =>
      items.where((item) => item.refundedQuantity > 0).toList(growable: false);

  double get totalQuantity =>
      items.fold<double>(0, (sum, item) => sum + item.quantity);

  String get displayDate {
    final month = createdAt.month.toString().padLeft(2, '0');
    final day = createdAt.day.toString().padLeft(2, '0');
    return '$month/$day/${createdAt.year}';
  }

  String get displayTime {
    final hour = createdAt.hour;
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '$h12:$minute $ampm';
  }

  bool get isToday {
    final now = DateTime.now();
    return createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
  }

  String get displayGroupLabel {
    if (isToday) return 'Today';
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    if (createdAt.year == yesterday.year &&
        createdAt.month == yesterday.month &&
        createdAt.day == yesterday.day) {
      return 'Yesterday';
    }
    return displayDate;
  }
}

enum TransactionFilterType { all, today, cash, card, refunded }

class RefundLineItem {
  const RefundLineItem({
    required this.id,
    required this.orderItemId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.amount,
  });

  final int id;
  final int orderItemId;
  final int productId;
  final String productName;
  final double quantity;
  final double amount;

  factory RefundLineItem.fromJson(Map<String, dynamic> json) {
    return RefundLineItem(
      id: _toInt(json['id']),
      orderItemId: _toInt(json['order_item_id']),
      productId: _toInt(json['product_id']),
      productName: json['product_name']?.toString() ?? 'Item',
      quantity: _toDouble(json['quantity']),
      amount: _toDouble(json['amount']),
    );
  }
}

class RefundRecord {
  const RefundRecord({
    required this.id,
    required this.orderId,
    required this.refundType,
    required this.amount,
    required this.reason,
    required this.createdAt,
    required this.customerName,
    required this.paymentMethod,
    required this.orderStatus,
    required this.items,
  });

  final int id;
  final int orderId;
  final String refundType;
  final double amount;
  final String reason;
  final DateTime createdAt;
  final String customerName;
  final String paymentMethod;
  final String orderStatus;
  final List<RefundLineItem> items;

  factory RefundRecord.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) => RefundLineItem.fromJson(Map<String, dynamic>.from(raw)))
        .toList();

    return RefundRecord(
      id: _toInt(json['id']),
      orderId: _toInt(json['order_id']),
      refundType: (json['refund_type'] ?? 'items').toString(),
      amount: _toDouble(json['amount']),
      reason: (json['reason'] ?? '').toString(),
      createdAt: parseServerDateTime((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      customerName: (json['customer_name'] ?? 'Walk In Farmer').toString(),
      paymentMethod: (json['payment_method'] ?? 'Cash').toString(),
      orderStatus: (json['order_status'] ?? 'completed').toString(),
      items: items,
    );
  }

  String get receiptNumber => 'RCP-${orderId.toString().padLeft(6, '0')}';

  String get displayTime {
    final hour = createdAt.hour;
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '$h12:$minute $ampm';
  }
}

class TransactionGroup {
  const TransactionGroup({
    required this.label,
    required this.transactions,
  });

  final String label;
  final List<TransactionRecord> transactions;
}

class TransactionApiResult {
  const TransactionApiResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}
