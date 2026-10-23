import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/core/utils/sales_history_window.dart';

void main() {
  test('default window starts on the 1st of last month', () {
    expect(defaultSalesHistoryStart(DateTime(2026, 10, 23, 9, 21)),
        DateTime(2026, 9, 1));
    // January rolls back into December of the previous year.
    expect(defaultSalesHistoryStart(DateTime(2027, 1, 5)), DateTime(2026, 12, 1));
    // Covers "last week" even on the 1st of the month.
    expect(defaultSalesHistoryStart(DateTime(2026, 3, 1)), DateTime(2026, 2, 1));
  });

  test('get_orders query only carries the filters that are set', () {
    expect(ordersDateQuery(), isNull);
    expect(ordersDateQuery(from: DateTime(2026, 9, 1)), {'from': '2026-09-01'});
    expect(
      ordersDateQuery(from: DateTime(2026, 1, 5), to: DateTime(2026, 2, 28)),
      {'from': '2026-01-05', 'to': '2026-02-28'},
    );
    expect(ordersDateQuery(orderId: 13507), {'order_id': '13507'});
    expect(ordersDateQuery(orderId: 0), isNull);
  });
}
