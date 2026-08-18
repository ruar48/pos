class InventoryReportTotals {
  const InventoryReportTotals({
    required this.beginning,
    required this.added,
    required this.deducted,
    required this.ending,
    required this.sold,
    required this.valueCost,
    required this.valueRetail,
    required this.valueMargin,
    required this.lowStock,
    required this.outOfStock,
    required this.items,
  });

  final double beginning;
  final double added;
  final double deducted;
  final double ending;
  final double sold;
  final double valueCost;
  final double valueRetail;
  final double valueMargin;
  final int lowStock;
  final int outOfStock;
  final int items;

  factory InventoryReportTotals.fromJson(Map<String, dynamic> json) {
    return InventoryReportTotals(
      beginning: (json['beginning'] as num?)?.toDouble() ?? 0,
      added: (json['added'] as num?)?.toDouble() ?? 0,
      deducted: (json['deducted'] as num?)?.toDouble() ?? 0,
      ending: (json['ending'] as num?)?.toDouble() ?? 0,
      sold: (json['sold'] as num?)?.toDouble() ?? 0,
      valueCost: (json['value_cost'] as num?)?.toDouble() ?? 0,
      valueRetail: (json['value_retail'] as num?)?.toDouble() ?? 0,
      valueMargin: (json['value_margin'] as num?)?.toDouble() ?? 0,
      lowStock: (json['low_stock'] as num?)?.toInt() ?? 0,
      outOfStock: (json['out_of_stock'] as num?)?.toInt() ?? 0,
      items: (json['items'] as num?)?.toInt() ?? 0,
    );
  }
}

class InventoryReportRow {
  const InventoryReportRow({
    required this.productId,
    required this.name,
    required this.sku,
    required this.category,
    required this.unit,
    required this.beginning,
    required this.added,
    required this.deducted,
    required this.ending,
    required this.liveStock,
    required this.sold,
    required this.valueCost,
    required this.valueRetail,
    required this.isLowStock,
    required this.isOutOfStock,
    this.imageUrl,
  });

  final int productId;
  final String name;
  final String? sku;
  final String category;
  final String? unit;
  final double beginning;
  final double added;
  final double deducted;
  final double ending;
  final double liveStock;
  final double sold;
  final double valueCost;
  final double valueRetail;
  final bool isLowStock;
  final bool isOutOfStock;
  final String? imageUrl;

  double get valueMargin => valueRetail - valueCost;

  factory InventoryReportRow.fromJson(Map<String, dynamic> json) {
    return InventoryReportRow(
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? 'Item',
      sku: json['sku'] as String?,
      category: (json['category'] as String?) ?? 'Uncategorized',
      unit: json['unit'] as String?,
      beginning: (json['beginning'] as num?)?.toDouble() ?? 0,
      added: (json['added'] as num?)?.toDouble() ?? 0,
      deducted: (json['deducted'] as num?)?.toDouble() ?? 0,
      ending: (json['ending'] as num?)?.toDouble() ?? 0,
      liveStock: (json['live_stock'] as num?)?.toDouble() ?? 0,
      sold: (json['sold'] as num?)?.toDouble() ?? 0,
      valueCost: (json['value_cost'] as num?)?.toDouble() ?? 0,
      valueRetail: (json['value_retail'] as num?)?.toDouble() ?? 0,
      isLowStock: json['is_low_stock'] == true,
      isOutOfStock: json['is_out_of_stock'] == true,
      imageUrl: json['image_url'] as String?,
    );
  }
}

class InventoryReport {
  const InventoryReport({
    required this.start,
    required this.end,
    required this.valuationAsOf,
    required this.rows,
    required this.totals,
  });

  final String start;
  final String end;
  final String valuationAsOf;
  final List<InventoryReportRow> rows;
  final InventoryReportTotals totals;

  factory InventoryReport.fromJson(Map<String, dynamic> json) {
    final range = json['range'] as Map<String, dynamic>? ?? const {};
    final rows = (json['rows'] as List<dynamic>? ?? const [])
        .map((row) => InventoryReportRow.fromJson(row as Map<String, dynamic>))
        .toList();

    return InventoryReport(
      start: (range['start'] as String?) ?? '',
      end: (range['end'] as String?) ?? '',
      valuationAsOf: (json['valuation_as_of'] as String?) ?? '',
      rows: rows,
      totals: InventoryReportTotals.fromJson(
        json['totals'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}
