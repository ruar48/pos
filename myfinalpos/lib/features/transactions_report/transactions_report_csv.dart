import '../../core/utils/format_utils.dart';
import 'transactions_report_models.dart';

/// A text cell: always quoted, inner quotes doubled, and text that a
/// spreadsheet would run as a formula (=, +, -, @, tab, CR) prefixed with an
/// apostrophe. Customer names and notes are typed by staff, so a name like
/// `=HYPERLINK(...)` must stay plain text.
String csvText(Object? value) {
  var text = value?.toString() ?? '';
  if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}

/// Money as a bare number (no ₱, no grouping) so spreadsheets can sum it.
String csvMoney(double value) => value.toStringAsFixed(2);

String csvQuantity(double value) => formatQuantity(value);

String _row(List<String> cells) => cells.join(',');

String buildOrderRowsCsv(List<TransactionReportOrderRow> rows) {
  final buffer = StringBuffer()
    ..writeln(
      _row(const [
        'Receipt',
        'Date',
        'Time',
        'Cashier',
        'Customer',
        'Payment',
        'Total',
        'Refunded',
        'Discount',
        'Costs',
        'Profits',
        'Items',
        'Status',
      ].map(csvText).toList()),
    );
  for (final row in rows) {
    buffer.writeln(
      _row([
        csvText(row.receiptNumber),
        csvText(row.date),
        csvText(row.time),
        csvText(row.cashierName),
        csvText(row.customerName),
        csvText(row.paymentMethod),
        csvMoney(row.total),
        csvMoney(row.refundedAmount),
        csvMoney(row.discount),
        csvMoney(row.costs),
        csvMoney(row.profits),
        csvQuantity(row.itemsCount),
        csvText(row.status),
      ]),
    );
  }
  return buffer.toString();
}

String buildPeriodRowsCsv(List<TransactionReportPeriodRow> rows) {
  final buffer = StringBuffer()
    ..writeln(
      _row(const [
        'Period',
        'Gross Sales',
        'Refunded',
        'Net Total',
        'Transactions',
        'Refunded Txns',
        'Items',
        'Discount',
        'Costs',
        'Expenses',
        'Profits',
        'Bank Transfer',
        'Best Seller',
      ].map(csvText).toList()),
    );
  for (final row in rows) {
    buffer.writeln(
      _row([
        csvText(row.label),
        csvMoney(row.grossTotal),
        csvMoney(row.refundedAmount),
        csvMoney(row.total),
        '${row.transactions}',
        '${row.refundedTransactions}',
        csvQuantity(row.items),
        csvMoney(row.discount),
        csvMoney(row.costs),
        csvMoney(row.expenses),
        csvMoney(row.profits),
        csvMoney(row.bankTransfer),
        csvText(row.bestSeller),
      ]),
    );
  }
  return buffer.toString();
}
