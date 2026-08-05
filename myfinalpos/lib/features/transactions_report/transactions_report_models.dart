import '../../core/utils/format_utils.dart';

class TransactionReportPagination {
  const TransactionReportPagination({
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
  });

  final int page;
  final int perPage;
  final int total;
  final int totalPages;

  factory TransactionReportPagination.fromJson(Map<String, dynamic> json) {
    return TransactionReportPagination(
      page: toInt(json['page']),
      perPage: toInt(json['per_page']),
      total: toInt(json['total']),
      totalPages: toInt(json['total_pages']),
    );
  }
}

class TransactionReportRange {
  const TransactionReportRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  factory TransactionReportRange.fromJson(Map<String, dynamic> json) {
    return TransactionReportRange(
      start: DateTime.tryParse(json['start']?.toString() ?? '') ??
          DateTime.now(),
      end: DateTime.tryParse(json['end']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class TransactionReportResponse {
  const TransactionReportResponse({
    required this.view,
    required this.range,
    required this.pagination,
    required this.orderRows,
    required this.periodRows,
  });

  final String view;
  final TransactionReportRange range;
  final TransactionReportPagination pagination;
  final List<TransactionReportOrderRow> orderRows;
  final List<TransactionReportPeriodRow> periodRows;

  factory TransactionReportResponse.fromJson(Map<String, dynamic> json) {
    final rows = (json['rows'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final view = json['view']?.toString() ?? 'details';

    return TransactionReportResponse(
      view: view,
      range: TransactionReportRange.fromJson(
        Map<String, dynamic>.from(json['range'] as Map? ?? const {}),
      ),
      pagination: TransactionReportPagination.fromJson(
        Map<String, dynamic>.from(json['pagination'] as Map? ?? const {}),
      ),
      orderRows: view == 'details' || view == 'transactions'
          ? rows.map(TransactionReportOrderRow.fromJson).toList()
          : const [],
      periodRows: view == 'hourly' || view == 'daily' || view == 'monthly'
          ? rows.map(TransactionReportPeriodRow.fromJson).toList()
          : const [],
    );
  }
}

class TransactionReportOrderRow {
  const TransactionReportOrderRow({
    required this.id,
    required this.receiptNumber,
    required this.date,
    required this.time,
    required this.createdAt,
    required this.cashierName,
    required this.customerName,
    required this.paymentMethod,
    required this.total,
    required this.discount,
    required this.costs,
    required this.profits,
    required this.itemsCount,
    required this.itemsSummary,
    required this.status,
    required this.refundedAmount,
    required this.canRefund,
    required this.items,
  });

  final int id;
  final String receiptNumber;
  final String date;
  final String time;
  final DateTime? createdAt;
  final String cashierName;
  final String customerName;
  final String paymentMethod;
  final double total;
  final double discount;
  final double costs;
  final double profits;
  final int itemsCount;
  final String itemsSummary;
  final String status;
  final double refundedAmount;
  final bool canRefund;
  final List<TransactionReportLineItem> items;

  factory TransactionReportOrderRow.fromJson(Map<String, dynamic> json) {
    final itemMaps = (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item));

    return TransactionReportOrderRow(
      id: toInt(json['id']),
      receiptNumber: json['receipt_number']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      cashierName: json['cashier_name']?.toString() ?? 'Staff',
      customerName: json['customer_name']?.toString() ?? 'Walk In Farmer',
      paymentMethod: json['payment_method']?.toString() ?? 'Cash',
      total: toDouble(json['total']),
      discount: toDouble(json['discount']),
      costs: toDouble(json['costs']),
      profits: toDouble(json['profits']),
      itemsCount: toInt(json['items_count']),
      itemsSummary: json['items_summary']?.toString() ?? '',
      status: json['status']?.toString() ?? 'completed',
      refundedAmount: toDouble(json['refunded_amount']),
      canRefund: json['can_refund'] == true,
      items: itemMaps.map(TransactionReportLineItem.fromJson).toList(),
    );
  }
}

class TransactionReportLineItem {
  const TransactionReportLineItem({
    required this.orderItemId,
    required this.productId,
    required this.productName,
    required this.varietyName,
    required this.quantity,
    required this.refundedQuantity,
    required this.price,
    required this.total,
  });

  final int orderItemId;
  final int productId;
  final String productName;
  final String? varietyName;
  final double quantity;
  final double refundedQuantity;
  final double price;
  final double total;

  factory TransactionReportLineItem.fromJson(Map<String, dynamic> json) {
    return TransactionReportLineItem(
      orderItemId: toInt(json['order_item_id']),
      productId: toInt(json['product_id']),
      productName: json['product_name']?.toString() ?? 'Item',
      varietyName: json['variety_name']?.toString(),
      quantity: toDouble(json['quantity']),
      refundedQuantity: toDouble(json['refunded_quantity']),
      price: toDouble(json['price']),
      total: toDouble(json['total']),
    );
  }

  String get displayName =>
      varietyName == null || varietyName!.isEmpty
          ? productName
          : '$productName · $varietyName';
}

class TransactionReportPeriodRow {
  const TransactionReportPeriodRow({
    required this.periodKey,
    required this.label,
    required this.total,
    required this.grossTotal,
    required this.refundedAmount,
    required this.refundedTransactions,
    required this.status,
    required this.transactions,
    required this.items,
    required this.discount,
    required this.costs,
    required this.expenses,
    required this.profits,
    required this.bankTransfer,
    required this.bestSeller,
  });

  final String periodKey;
  final String label;
  final double total;
  final double grossTotal;
  final double refundedAmount;
  final int refundedTransactions;
  final String status;
  final int transactions;
  final double items;
  final double discount;
  final double costs;
  final double expenses;
  final double profits;
  final double bankTransfer;
  final String bestSeller;

  factory TransactionReportPeriodRow.fromJson(Map<String, dynamic> json) {
    return TransactionReportPeriodRow(
      periodKey: json['period_key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      total: toDouble(json['total']),
      grossTotal: toDouble(json['gross_total']),
      refundedAmount: toDouble(json['refunded_amount']),
      refundedTransactions: toInt(json['refunded_transactions']),
      status: json['status']?.toString() ?? 'completed',
      transactions: toInt(json['transactions']),
      items: toDouble(json['items']),
      discount: toDouble(json['discount']),
      costs: toDouble(json['costs']),
      expenses: toDouble(json['expenses']),
      profits: toDouble(json['profits']),
      bankTransfer: toDouble(json['bank_transfer']),
      bestSeller: json['best_seller']?.toString() ?? '',
    );
  }
}

enum TransactionReportTab {
  details('details', 'Details'),
  transactions('transactions', 'Transactions'),
  hourly('hourly', 'Hourly'),
  daily('daily', 'Daily'),
  monthly('monthly', 'Monthly');

  const TransactionReportTab(this.apiView, this.label);

  final String apiView;
  final String label;
}
