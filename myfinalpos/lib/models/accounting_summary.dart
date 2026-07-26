import '../core/utils/format_utils.dart';

class AccountingTrendPoint {
  const AccountingTrendPoint({
    required this.date,
    required this.label,
    required this.total,
    required this.orderCount,
  });

  final String date;
  final String label;
  final double total;
  final int orderCount;

  factory AccountingTrendPoint.fromJson(Map<String, dynamic> json) {
    return AccountingTrendPoint(
      date: (json['date'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      total: toDouble(json['total']),
      orderCount: toInt(json['order_count']),
    );
  }
}

class AccountingPaymentMethodRow {
  const AccountingPaymentMethodRow({
    required this.paymentMethod,
    required this.orderCount,
    required this.netTotal,
  });

  final String paymentMethod;
  final int orderCount;
  final double netTotal;

  factory AccountingPaymentMethodRow.fromJson(Map<String, dynamic> json) {
    return AccountingPaymentMethodRow(
      paymentMethod: (json['payment_method'] ?? 'Cash').toString(),
      orderCount: toInt(json['order_count']),
      netTotal: toDouble(json['net_total']),
    );
  }
}

class AccountingRecentOrder {
  const AccountingRecentOrder({
    required this.orderId,
    required this.customerName,
    required this.subtotal,
    required this.vat,
    required this.discountTotal,
    required this.total,
    required this.paymentMethod,
    required this.status,
    this.createdAt,
  });

  final int orderId;
  final String customerName;
  final double subtotal;
  final double vat;
  final double discountTotal;
  final double total;
  final String paymentMethod;
  final String status;
  final DateTime? createdAt;

  factory AccountingRecentOrder.fromJson(Map<String, dynamic> json) {
    return AccountingRecentOrder(
      orderId: toInt(json['order_id']),
      customerName: (json['customer_name'] ?? 'Walk In Farmer').toString(),
      subtotal: toDouble(json['subtotal']),
      vat: toDouble(json['vat']),
      discountTotal: toDouble(json['discount_total']),
      total: toDouble(json['total']),
      paymentMethod: (json['payment_method'] ?? 'Cash').toString(),
      status: (json['status'] ?? 'completed').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'refunded':
        return 'Refunded';
      case 'partial_refund':
        return 'Partial Refund';
      default:
        return 'Completed';
    }
  }
}

class AccountingSummary {
  const AccountingSummary({
    required this.period,
    required this.grossSales,
    required this.netSales,
    required this.vatCollected,
    required this.totalDiscounts,
    required this.manualDiscounts,
    required this.couponDiscounts,
    required this.loyaltyDiscounts,
    required this.orderCount,
    required this.averageOrderValue,
    required this.refundedAmount,
    required this.refundCount,
    required this.todayNetSales,
    required this.todayOrderCount,
    required this.monthNetSales,
    required this.monthOrderCount,
    required this.paymentMethods,
    required this.recentOrders,
    required this.trend,
  });

  final String period;
  final double grossSales;
  final double netSales;
  final double vatCollected;
  final double totalDiscounts;
  final double manualDiscounts;
  final double couponDiscounts;
  final double loyaltyDiscounts;
  final int orderCount;
  final double averageOrderValue;
  final double refundedAmount;
  final int refundCount;
  final double todayNetSales;
  final int todayOrderCount;
  final double monthNetSales;
  final int monthOrderCount;
  final List<AccountingPaymentMethodRow> paymentMethods;
  final List<AccountingRecentOrder> recentOrders;
  final List<AccountingTrendPoint> trend;

  factory AccountingSummary.fromJson(Map<String, dynamic> json) {
    final trendRaw = json['trend'] as List<dynamic>? ?? const [];
    final paymentRaw = json['payment_methods'] as List<dynamic>? ?? const [];
    final recentRaw = json['recent_orders'] as List<dynamic>? ?? const [];

    return AccountingSummary(
      period: (json['period'] ?? 'all').toString(),
      grossSales: toDouble(json['gross_sales']),
      netSales: toDouble(json['net_sales']),
      vatCollected: toDouble(json['vat_collected']),
      totalDiscounts: toDouble(json['total_discounts']),
      manualDiscounts: toDouble(json['manual_discounts']),
      couponDiscounts: toDouble(json['coupon_discounts']),
      loyaltyDiscounts: toDouble(json['loyalty_discounts']),
      orderCount: toInt(json['order_count']),
      averageOrderValue: toDouble(json['average_order_value']),
      refundedAmount: toDouble(json['refunded_amount']),
      refundCount: toInt(json['refund_count']),
      todayNetSales: toDouble(json['today_net_sales']),
      todayOrderCount: toInt(json['today_order_count']),
      monthNetSales: toDouble(json['month_net_sales']),
      monthOrderCount: toInt(json['month_order_count']),
      paymentMethods: paymentRaw
          .map(
            (item) => AccountingPaymentMethodRow.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      recentOrders: recentRaw
          .map(
            (item) => AccountingRecentOrder.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      trend: trendRaw
          .map(
            (item) => AccountingTrendPoint.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }

  static AccountingSummary empty({String period = 'all'}) => AccountingSummary(
        period: period,
        grossSales: 0,
        netSales: 0,
        vatCollected: 0,
        totalDiscounts: 0,
        manualDiscounts: 0,
        couponDiscounts: 0,
        loyaltyDiscounts: 0,
        orderCount: 0,
        averageOrderValue: 0,
        refundedAmount: 0,
        refundCount: 0,
        todayNetSales: 0,
        todayOrderCount: 0,
        monthNetSales: 0,
        monthOrderCount: 0,
        paymentMethods: const [],
        recentOrders: const [],
        trend: const [],
      );
}
