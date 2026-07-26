class LiveWallSalesReport {
  const LiveWallSalesReport({
    required this.orderCount,
    required this.grossSales,
    required this.netSales,
    required this.averageOrderValue,
  });

  final int orderCount;
  final double grossSales;
  final double netSales;
  final double averageOrderValue;

  factory LiveWallSalesReport.fromJson(Map<String, dynamic> json) {
    final overall = json['overall'] as Map<String, dynamic>? ?? const {};

    return LiveWallSalesReport(
      orderCount: (overall['order_count'] as num?)?.toInt() ?? 0,
      grossSales: (overall['gross_sales'] as num?)?.toDouble() ?? 0,
      netSales: (overall['net_sales'] as num?)?.toDouble() ?? 0,
      averageOrderValue:
          (overall['average_order_value'] as num?)?.toDouble() ?? 0,
    );
  }
}
