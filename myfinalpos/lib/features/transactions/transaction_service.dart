import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  Future<List<TransactionRecord>> fetchTransactions() async {
    final uri = _buildUri('get_orders.php');
    final response = await http.get(uri).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to load transactions: ${response.statusCode}',
      );
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map || payload['success'] != true) {
      throw FormatException('Invalid response from transaction API');
    }

    final data = payload['data'] as List?;
    if (data == null) return [];

    return data
        .whereType<Map>()
        .map(
          (raw) => TransactionRecord.fromJson(Map<String, dynamic>.from(raw)),
        )
        .toList();
  }

  Future<List<RefundRecord>> fetchRefunds() async {
    final uri = _buildUri('get_refunds.php');
    final response = await http.get(uri).timeout(const Duration(seconds: 12));

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
    final transactions = await fetchTransactions();
    for (final transaction in transactions) {
      if (transaction.id == orderId) {
        return transaction;
      }
    }
    return null;
  }

  Future<TransactionApiResult> processRefund({
    required int orderId,
    required String reason,
    required String refundType,
    required List<RefundItemRequest> items,
    int? actorUserId,
  }) async {
    final uri = _buildUri('process_refund.php');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'order_id': orderId,
        'refund_type': refundType,
        'reason': reason,
        'items': items.map((item) => item.toJson()).toList(),
        'actor_user_id': actorUserId,
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final success = response.statusCode == 200 && body['success'] == true;
    final apiMessage = body['message']?.toString().trim();
    return TransactionApiResult(
      success: success,
      message: (apiMessage != null && apiMessage.isNotEmpty)
          ? apiMessage
          : (success ? 'Refund processed' : 'Refund failed'),
    );
  }

  Future<TransactionApiResult> reprintReceipt({
    required TransactionRecord transaction,
    PrinterConfig? printer,
    String? printerHost,
    ReceiptStoreConfig? store,
  }) async {
    try {
      final receipt = _buildReceiptData(
        transaction,
        store: store,
      );
      final isCash =
          transaction.paymentMethod.toLowerCase().contains('cash');

      await PosReceiptService.printReceipt(
        receipt: receipt,
        printer: printer,
        printerHost: printerHost,
        openDrawer: isCash,
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

  ReceiptData _buildReceiptData(
    TransactionRecord transaction, {
    ReceiptStoreConfig? store,
  }) {
    final totalDiscount = transaction.discountAmount +
        transaction.couponDiscount +
        transaction.loyaltyDiscount;
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
              name: item.productName,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              total: item.subtotal,
            ),
          )
          .toList(),
      subtotal: transaction.subtotal,
      vat: transaction.vat,
      discount: totalDiscount,
      manualDiscount: transaction.discountAmount,
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
      isVatRegistered: transaction.vat > 0,
      dateTime: transaction.createdAt,
      store: store ?? const ReceiptStoreConfig(),
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
