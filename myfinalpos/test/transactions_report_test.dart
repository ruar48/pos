import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/features/transactions_report/transactions_report_csv.dart';
import 'package:myfinalpos/features/transactions_report/transactions_report_models.dart';

/// Minimal RFC 4180 reader, to check the copied text splits into the right
/// cells.
List<List<String>> _parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else if (c != '\r') {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

Map<String, dynamic> _rowJson({
  Object? itemsCount = 3,
  bool canRefund = true,
  List<Map<String, dynamic>>? items,
}) =>
    {
      'id': 77,
      'receipt_number': 'INV-000077',
      'date': '23 Oct 2026',
      'time': '9:21am',
      'cashier_name': 'HASMIN',
      'customer_name': 'Juan Farmer',
      'payment_method': 'Cash',
      'total': 1080.5,
      'discount': 20,
      'costs': 1093,
      'profits': -12.5,
      'items_count': itemsCount,
      'status': 'completed',
      'refunded_amount': 0,
      'can_refund': canRefund,
      'items': items ??
          [
            {
              'order_item_id': 1,
              'product_id': 3,
              'product_name': 'RICE',
              'quantity': 2.5,
              'refunded_quantity': 0,
              'price': 50,
              'total': 125,
            },
          ],
    };

void main() {
  group('items_count', () {
    test('fractional quantities are kept (used to parse as 0)', () {
      expect(TransactionReportOrderRow.fromJson(_rowJson(itemsCount: '2.5'))
          .itemsCount, 2.5);
      expect(TransactionReportOrderRow.fromJson(_rowJson(itemsCount: 2.5))
          .itemsCount, 2.5);
      expect(
          TransactionReportOrderRow.fromJson(_rowJson(itemsCount: 3)).itemsCount,
          3);
    });
  });

  group('canRefund goes by units left', () {
    test('money all refunded but a free unit left is still refundable', () {
      final row = TransactionReportOrderRow.fromJson(
        _rowJson(
          canRefund: false,
          items: [
            {
              'order_item_id': 1,
              'quantity': 1,
              'refunded_quantity': 1,
              'price': 100,
              'total': 100,
            },
            {
              'order_item_id': 2,
              'quantity': 1,
              'refunded_quantity': 0,
              'price': 0,
              'total': 0,
            },
          ],
        ),
      );
      expect(row.canRefund, isTrue);
    });

    test('every unit back is not refundable', () {
      final row = TransactionReportOrderRow.fromJson(
        _rowJson(
          items: [
            {
              'order_item_id': 1,
              'quantity': 2.5,
              'refunded_quantity': 2.5,
              'price': 100,
              'total': 250,
            },
          ],
        ),
      );
      expect(row.canRefund, isFalse);
    });

    test('falls back to the server flag when no items are sent', () {
      expect(
        TransactionReportOrderRow.fromJson(_rowJson(items: const []))
            .canRefund,
        isTrue,
      );
    });
  });

  group('CSV copy', () {
    test('text is quoted and escaped, formulas neutralised', () {
      expect(csvText('Juan "JR" Cruz'), '"Juan ""JR"" Cruz"');
      expect(csvText('=HYPERLINK("http://x")'),
          '"\'=HYPERLINK(""http://x"")"');
      expect(csvText('+63 917'), '"\'+63 917"');
      expect(csvText('-cash'), '"\'-cash"');
      expect(csvText('@SUM(A1)'), '"\'@SUM(A1)"');
      expect(csvText('Rice, 25kg'), '"Rice, 25kg"');
      expect(csvText(null), '""');
    });

    test('order rows: money is a plain number, cells line up', () {
      final row = TransactionReportOrderRow.fromJson({
        ..._rowJson(itemsCount: '2.5'),
        'customer_name': 'Cruz, "JR" =1+1',
        'cashier_name': '@admin',
      });
      final csv = buildOrderRowsCsv([row]);
      final parsed = _parseCsv(csv);

      expect(parsed.length, 2);
      expect(parsed[0].length, 13);
      expect(parsed[1].length, 13);
      expect(csv.contains('₱'), isFalse);

      final cells = parsed[1];
      expect(cells[3], "'@admin");
      expect(cells[4], 'Cruz, "JR" =1+1');
      expect(cells[6], '1080.50'); // Total
      expect(cells[7], '0.00'); // Refunded
      expect(cells[10], '-12.50'); // Profits stay numeric
      expect(cells[11], '2.5'); // Items
    });

    test('period rows: money is a plain number, cells line up', () {
      final row = TransactionReportPeriodRow.fromJson({
        'label': 'Oct 23, 2026',
        'gross_total': 1500,
        'refunded_amount': 200,
        'total': 1300,
        'transactions': 4,
        'refunded_transactions': 1,
        'items': 6.25,
        'discount': 0,
        'costs': 900,
        'expenses': 50,
        'profits': 350,
        'bank_transfer': 0,
        'best_seller': '=cmd',
      });
      final parsed = _parseCsv(buildPeriodRowsCsv([row]));

      expect(parsed[1].length, 13);
      expect(parsed[1][0], 'Oct 23, 2026');
      expect(parsed[1][1], '1500.00');
      expect(parsed[1][6], '6.25');
      expect(parsed[1][12], "'=cmd");
    });
  });
}
