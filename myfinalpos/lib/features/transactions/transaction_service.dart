import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/pos_payment_methods.dart';
import '../../core/utils/sales_history_window.dart';
import '../../services/api_session.dart';
import '../../services/orders_api_compat.dart';
import '../../models/printer_settings.dart';
import '../../models/refund_item_request.dart';
import '../receipt/receipt_printer.dart';
import 'transaction_model.dart';

class TransactionService {
  TransactionService(this.baseUrl);

  final String baseUrl;

  Uri _buildUri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl/$path').replace(queryParameters: query);
  }

  /// Every order from an older backend, kept briefly so looking up single
  /// receipts right after loading the list doesn't download 14 MB again
  /// (that backend ignores `order_id` and always sends everything).
  static List<TransactionRecord>? _fullListCache;
  static DateTime? _fullListCachedAt;

  static void _clearFullListCache() {
    _fullListCache = null;
    _fullListCachedAt = null;
  }

  /// Orders from [from] onwards - defaults to the 1st of last month, which
  /// covers the 3-day exchange window with room to spare. Older receipts
  /// are looked up one at a time with [fetchTransactionDetail].
  Future<List<TransactionRecord>> fetchTransactions({
    DateTime? from,
    int? orderId,
  }) async {
    final windowStart = orderId == null ? (from ?? defaultSalesHistoryStart()) : null;
    final uri = _buildUri(
      'get_orders.php',
      ordersDateQuery(from: windowStart, orderId: orderId),
    );
    final response = await apiHttp.get(uri).timeout(OrdersApiCompat.timeout);

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to load transactions: ${response.statusCode}',
      );
    }

    final payload = await decodeJsonOffUiThread(response.body);
    if (payload is! Map || payload['success'] != true) {
      throw FormatException('Invalid response from transaction API');
    }

    final data = payload['data'] as List?;
    if (data == null) return [];

    final all = data
        .whereType<Map>()
        .map(
          (raw) => TransactionRecord.fromJson(Map<String, dynamic>.from(raw)),
        )
        .toList();

    final kept = applyOrderFilters<TransactionRecord>(
      all,
      idOf: (t) => t.id,
      createdAtOf: (t) => t.createdAt,
      from: windowStart,
      orderId: orderId,
    );
    if (kept.length != all.length) {
      _fullListCache = all;
      _fullListCachedAt = DateTime.now();
    }
    return kept;
  }

  Future<List<RefundRecord>> fetchRefunds() async {
    final uri = _buildUri('get_refunds.php');
    final response = await apiHttp.get(uri).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to load refunds: ${response.statusCode}',
      );
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map || payload['success'] != true) {
      throw FormatException('Invalid response from refunds API');
    }

    final data = payload['data'] as List? ?? const [];
    return data
        .whereType<Map>()
        .map((raw) => RefundRecord.fromJson(Map<String, dynamic>.from(raw)))
        .toList();
  }

  Future<TransactionRecord?> fetchTransactionDetail(int orderId) async {
    // Older backend: answer from the full list just downloaded rather than
    // fetching every order again for each receipt. Kept only briefly, and
    // cleared by any refund so a refunded order is never served stale.
    final cache = _fullListCache;
    final cachedAt = _fullListCachedAt;
    if (OrdersApiCompat.serverIgnoresFilters &&
        cache != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(seconds: 45)) {
      for (final transaction in cache) {
        if (transaction.id == orderId) return transaction;
      }
    }

    final transactions = await fetchTransactions(orderId: orderId);
    for (final transaction in transactions) {
      if (transaction.id == orderId) {
        return transaction;
      }
    }
    return null;
  }

  /// Without a limit a stalled request left the cashier looking at nothing,
  /// and tapping Refund again could refund twice.
  static const refundTimeout = Duration(seconds: 20);

  /// Never throws: every failure comes back as an unsuccessful result the
  /// screen can show.
  Future<TransactionApiResult> processRefund({
    required int orderId,
    required String reason,
    required String refundType,
    required List<RefundItemRequest> items,
    int? actorUserId,
    String? refundPin,
  }) async {
    // Whatever happens, the cached copy of the orders is now out of date.
    _clearFullListCache();
    final uri = _buildUri('process_refund.php');
    try {
      final response = await apiHttp
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'order_id': orderId,
              'refund_type': refundType,
              'reason': reason,
              'items': items.map((item) => item.toJson()).toList(),
              'actor_user_id': actorUserId,
              if (refundPin != null && refundPin.isNotEmpty)
                'refund_pin': refundPin,
            }),
          )
          .timeout(refundTimeout);
      return refundResultFromResponse(response.statusCode, response.body);
    } on TimeoutException {
      // The server may still finish the refund after we stop waiting.
      return const TransactionApiResult(
        success: false,
        message: 'No answer from the server after 20 seconds. The refund '
            'may still have gone through - check the order before '
            'refunding again.',
      );
    } on SocketException {
      return const TransactionApiResult(
        success: false,
        message: 'Could not reach the server. Check the connection, then '
            'check the order before refunding again.',
      );
    } catch (error) {
      return TransactionApiResult(
        success: false,
        message: 'Refund failed: $error. Check the order before refunding '
            'again.',
      );
    }
  }

  /// Turns a process_refund.php reply into a result. A gateway error page
  /// (e.g. an HTML 504) is not JSON, and decoding it used to throw so the
  /// cashier saw nothing at all.
  static TransactionApiResult refundResultFromResponse(
    int statusCode,
    String body,
  ) {
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      payload = null;
    }

    final success = statusCode == 200 && payload?['success'] == true;
    final apiMessage = payload?['message']?.toString().trim() ?? '';
    final refundAmount = success
        ? _toMoney(payload?['refund_amount'])
        : null;

    final String message;
    if (apiMessage.isNotEmpty) {
      message = apiMessage;
    } else if (success) {
      message = refundAmount != null
          ? 'Refund processed. Give back '
              '₱${refundAmount.toStringAsFixed(2)} to the customer.'
          : 'Refund processed. Check the order for the refunded amount.';
    } else if (payload == null) {
      // A proxy/server error page: the refund may or may not have run.
      message = 'The server returned an error (HTTP $statusCode). The '
          'refund may still have gone through - check the order before '
          'refunding again.';
    } else {
      message = 'Refund failed (HTTP $statusCode)';
    }

    return TransactionApiResult(
      success: success,
      message: message,
      refundAmount: refundAmount,
    );
  }

  static double _toMoney(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<TransactionApiResult> reprintReceipt({
    required TransactionRecord transaction,
    PrinterConfig? printer,
    String? printerHost,
    ReceiptStoreConfig? store,
  }) async {
    try {
      final receipt = buildReceiptData(
        transaction,
        store: store,
      );

      await PosReceiptService.printReceipt(
        receipt: receipt,
        printer: printer,
        printerHost: printerHost,
        // No money changes hands on a reprint, so the drawer stays shut.
        openDrawer: false,
      );

      return const TransactionApiResult(
        success: true,
        message: 'Receipt sent to printer',
      );
    } on ReceiptPrintException catch (error) {
      return TransactionApiResult(
        success: false,
        message: error.message,
      );
    } catch (error) {
      return TransactionApiResult(
        success: false,
        message: 'Reprint failed: $error',
      );
    }
  }

  ReceiptData buildReceiptData(
    TransactionRecord transaction, {
    ReceiptStoreConfig? store,
  }) {
    final totalDiscount = transaction.discountAmount +
        transaction.couponDiscount +
        transaction.loyaltyDiscount;
    // The orders API folds per-item discounts into discount_amount, but
    // ReceiptData.manualDiscount must be order-level only - the receipt
    // recovers item discounts from the line items itself, so passing the
    // combined amount through would count them twice.
    final itemDiscountSum = transaction.items
        .fold<double>(0, (sum, item) => sum + item.discount);
    final orderLevelDiscount = (transaction.discountAmount - itemDiscountSum)
        .clamp(0, double.infinity)
        .toDouble();
    // Each refunded line's own amount is its share of the line total, which
    // is still before order-level (manual/coupon/loyalty) discounts - the
    // server refunded less than that. Scale the lines so they add up to the
    // REFUNDED amount actually paid back.
    final refundedLines = transaction.refundedItems;
    final refundedLineSum =
        refundedLines.fold<double>(0, (sum, item) => sum + item.refundedAmount);
    final refundLineScale = refundedLineSum > 0.009
        ? transaction.refundedAmount / refundedLineSum
        : 1.0;
    final amountTendered =
        transaction.grandTotal + transaction.changeAmount;

    return ReceiptData(
      orderId: transaction.id,
      invoiceNumber: transaction.receiptNumber,
      customerName: transaction.customerName,
      paymentMethod: transaction.paymentMethod,
      items: transaction.items
          .map(
            (item) => ReceiptLineItem(
              name: (item.varietyName == null || item.varietyName!.isEmpty)
                  ? item.productName
                  : '${item.productName} - ${item.varietyName}',
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              total: item.subtotal,
            ),
          )
          .toList(),
      subtotal: transaction.subtotal,
      vat: transaction.vat,
      discount: totalDiscount,
      manualDiscount: orderLevelDiscount,
      couponDiscount: transaction.couponDiscount,
      loyaltyDiscount: transaction.loyaltyDiscount,
      total: transaction.grandTotal,
      amountTendered: amountTendered,
      change: transaction.changeAmount,
      currencySymbol: '\u20B1',
      cashierName: transaction.cashierName,
      itemCount: transaction.totalQuantity,
      orderType: transaction.customerType,
      reference: transaction.reference,
      // Split sales print each method's amount and reference, as at
      // checkout.
      splitPayments:
          transaction.isSplitPayment && transaction.splitPayments.isNotEmpty
              ? transaction.splitPayments
                  .map(
                    (payment) => ReceiptPaymentLine(
                      paymentMethod: payment.paymentMethod,
                      amount: payment.amount,
                      reference: payment.reference,
                    ),
                  )
                  .toList()
              : null,
      isVatRegistered: transaction.vat > 0,
      dateTime: transaction.createdAt,
      store: store ?? const ReceiptStoreConfig(),
      refundedAmount: transaction.refundedAmount,
      refundItems: refundedLines
          .map(
            (item) => ReceiptRefundLineItem(
              name: (item.varietyName == null || item.varietyName!.isEmpty)
                  ? item.productName
                  : '${item.productName} - ${item.varietyName}',
              quantity: item.refundedQuantity,
              amount: item.refundedAmount * refundLineScale,
            ),
          )
          .toList(),
    );
  }

  Future<Uint8List> buildReceiptPdf(TransactionRecord transaction) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'MyFinal POS',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text('Receipt: ${transaction.receiptNumber}'),
              pw.Text('Date: ${transaction.displayDate} ${transaction.displayTime}'),
              pw.Text('Cashier: ${transaction.cashierName}'),
              pw.Text('Payment: ${transaction.paymentMethod}'),
              if (transaction.reference.trim().isNotEmpty)
                pw.Text(
                  '${PosPaymentMethods.referenceLabel(transaction.paymentMethod)}: '
                  '${transaction.reference.trim()}',
                ),
              pw.Divider(),
              for (final item in transaction.items) ...[
                pw.Text('${item.productName} x${item.quantity}'),
                pw.Text('${item.sku} - PHP ${item.subtotal.toStringAsFixed(2)}'),
                pw.SizedBox(height: 6),
              ],
              pw.Divider(),
              pw.Text('Subtotal: PHP ${transaction.subtotal.toStringAsFixed(2)}'),
              pw.Text(
                'Total: PHP ${transaction.grandTotal.toStringAsFixed(2)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<String?> exportTransactionsExcel(
    List<TransactionRecord> transactions,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Transactions'];
    sheet.appendRow(const [
      'Receipt',
      'Date',
      'Customer',
      'Payment',
      'Total',
    ]);

    for (final transaction in transactions) {
      sheet.appendRow([
        transaction.receiptNumber,
        transaction.displayDate,
        transaction.customerName,
        transaction.paymentMethod,
        transaction.grandTotal.toStringAsFixed(2),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/transactions_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes);
    return path;
  }

  Future<void> shareReceiptPdf(TransactionRecord transaction) async {
    await Printing.sharePdf(
      bytes: await buildReceiptPdf(transaction),
      filename: 'receipt_${transaction.receiptNumber}.pdf',
    );
  }
}
