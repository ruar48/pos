import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/models/sales_history_record.dart';
import 'package:myfinalpos/services/analytics_engine.dart';

SalesHistoryRecord sale({
  required int id,
  required String createdAt,
  double total = 1120,
  double refunded = 0,
  String status = 'completed',
  String payment = 'Cash',
  String? cashier,
  int? customerId,
  double discount = 0,
  List<Map<String, dynamic>>? items,
}) {
  return SalesHistoryRecord.fromOrderJson({
    'id': id,
    'customer_id': customerId,
    'customer_name': customerId == null ? 'Walk In Farmer' : 'Juan Dela Cruz',
    'branch_id': 1,
    'cashier_name': cashier,
    'subtotal': (total / 1.12).toStringAsFixed(2),
    'vat': (total - total / 1.12).toStringAsFixed(2),
    'total_amount': total.toStringAsFixed(2),
    'discount_amount': discount.toStringAsFixed(2),
    'coupon_discount': '0.00',
    'loyalty_discount': '0.00',
    'payment_method': payment,
    'created_at': createdAt,
    'status': status,
    'refunded_amount': refunded.toStringAsFixed(2),
    'items': items ??
        [
          item(1, 'Urea 50kg', '1.000', '1000.00'),
        ],
  });
}

Map<String, dynamic> item(
  int productId,
  String name,
  String qty,
  String price, {
  String refundedQty = '0.000',
}) {
  return {
    'product_id': productId,
    'product_name': name,
    'quantity': qty,
    'refunded_quantity': refundedQty,
    'price': price,
    'discount_amount': '0.00',
    'total': (double.parse(qty) * double.parse(price)).toStringAsFixed(2),
  };
}

void main() {
  group('summarize is net of refunds', () {
    final records = [
      sale(id: 1, createdAt: '2026-10-01 09:00:00', discount: 10),
      // Half of order 2 came back.
      sale(
        id: 2,
        createdAt: '2026-10-02 09:00:00',
        refunded: 560,
        status: 'partial_refund',
        customerId: 7,
        items: [
          item(1, 'Urea 50kg', '2.000', '500.00', refundedQty: '1.000'),
        ],
      ),
      // Order 3 was refunded in full.
      sale(
        id: 3,
        createdAt: '2026-10-03 09:00:00',
        refunded: 1120,
        status: 'refunded',
        discount: 25,
        items: [
          item(1, 'Urea 50kg', '1.000', '1000.00', refundedQty: '1.000'),
        ],
      ),
    ];

    test('totals, counts and average ticket', () {
      final summary = AnalyticsEngine.summarize(records);
      expect(summary.totalSales, closeTo(1120 + 560, 1e-6));
      expect(summary.refundedAmount, closeTo(560 + 1120, 1e-6));
      // The fully refunded order is no longer a sale.
      expect(summary.orderCount, 2);
      expect(summary.refundedOrders, 1);
      expect(summary.averageTicket, closeTo(840, 1e-6));
      // 1 unit + (2 - 1 refunded) units; the refunded order's unit is out.
      expect(summary.itemCount, closeTo(2, 1e-9));
      // Discount of the fully refunded order is not counted.
      expect(summary.totalDiscount, closeTo(10, 1e-9));
      expect(summary.walkInOrders, 1);
      expect(summary.registeredOrders, 1);
    });

    test('empty input', () {
      final summary = AnalyticsEngine.summarize(const []);
      expect(summary.totalSales, 0);
      expect(summary.orderCount, 0);
      expect(summary.averageTicket, 0);
      expect(summary.itemCount, 0);
    });

    test('payment, cashier, branch and customer splits', () {
      final mixed = [
        sale(id: 1, createdAt: '2026-10-01 09:00:00', cashier: 'Ana'),
        sale(
          id: 2,
          createdAt: '2026-10-01 10:00:00',
          payment: 'GCash',
          cashier: 'Ben',
          refunded: 120,
          status: 'partial_refund',
        ),
        sale(
          id: 3,
          createdAt: '2026-10-01 11:00:00',
          payment: 'Card',
          cashier: 'Ana',
          refunded: 1120,
          status: 'refunded',
        ),
      ];
      final payments = {
        for (final row in AnalyticsEngine.paymentBreakdown(mixed))
          row.label: row.value,
      };
      expect(payments, {'Cash': 1120.0, 'GCash': 1000.0});

      final cashiers = {
        for (final row in AnalyticsEngine.salesByCashier(mixed))
          row.label: row.value,
      };
      expect(cashiers, {'Ana': 1120.0, 'Ben': 1000.0});

      final branches = AnalyticsEngine.salesByBranch(
        records: mixed,
        branchNames: const {1: 'Main'},
      );
      expect(branches.single.value, closeTo(2120, 1e-9));

      final customers = AnalyticsEngine.customerTypeBreakdown(mixed);
      expect(customers.first.value, closeTo(2120, 1e-9));
    });
  });

  group('bestSellers', () {
    final records = [
      sale(
        id: 1,
        createdAt: '2026-10-01 09:00:00',
        items: [
          item(1, 'Cheap twine', '50.000', '2.00'),
          item(2, 'Tractor part', '1.000', '5000.00'),
          item(3, 'Seeds', '4.000', '100.00', refundedQty: '2.000'),
        ],
      ),
    ];

    test('a quantity ranking still carries each product\'s own revenue', () {
      final byQty = AnalyticsEngine.bestSellers(records: records, limit: 10);
      expect(byQty.first.label, 'Cheap twine');
      expect(byQty.first.quantity, 50);
      expect(byQty.first.revenue, closeTo(100, 1e-9));
    });

    test('revenue is looked up per item, not in a top-N revenue list', () {
      // limit 1 by revenue would only hold the tractor part; the quantity
      // list must not depend on it.
      final byQty = AnalyticsEngine.bestSellers(records: records, limit: 3);
      final seeds = byQty.firstWhere((row) => row.label == 'Seeds');
      // Net of the 2 refunded bags.
      expect(seeds.quantity, 2);
      expect(seeds.revenue, closeTo(200, 1e-9));
    });

    test('ranking by revenue', () {
      final byRevenue = AnalyticsEngine.bestSellers(
        records: records,
        byRevenue: true,
        limit: 1,
      );
      expect(byRevenue.single.label, 'Tractor part');
      expect(byRevenue.single.value, closeTo(5000, 1e-9));
      expect(byRevenue.single.quantity, 1);
    });
  });

  group('salesTrend', () {
    test('uses the requested granularity', () {
      final range = AnalyticsDateRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31, 23, 59, 59),
      );
      final records = [
        sale(id: 1, createdAt: '2026-10-05 09:00:00'),
        sale(id: 2, createdAt: '2026-10-06 09:00:00', refunded: 120),
      ];
      final daily = AnalyticsEngine.salesTrend(
        records: records,
        granularity: AnalyticsTrendGranularity.day,
        range: range,
      );
      expect(daily, hasLength(31));
      expect(daily[4].label, '10/05');
      expect(daily[4].value, closeTo(1120, 1e-9));
      expect(daily[5].value, closeTo(1000, 1e-9));

      final weekly = AnalyticsEngine.salesTrend(
        records: records,
        granularity: AnalyticsTrendGranularity.week,
        range: range,
      );
      // Mondays Sep 28 .. Oct 26.
      expect(weekly.map((row) => row.label).toList(), [
        'Wk 9/28',
        'Wk 10/5',
        'Wk 10/12',
        'Wk 10/19',
        'Wk 10/26',
      ]);
      expect(weekly[1].value, closeTo(2120, 1e-9));

      final monthly = AnalyticsEngine.salesTrend(
        records: records,
        granularity: AnalyticsTrendGranularity.month,
        range: range,
      );
      expect(monthly.single.label, 'Oct 2026');
      expect(monthly.single.value, closeTo(2120, 1e-9));
    });

    test('the same date in different years does not merge', () {
      final range = AnalyticsDateRange(
        start: DateTime(2025, 10, 5),
        end: DateTime(2026, 10, 5, 23, 59, 59),
      );
      final daily = AnalyticsEngine.salesTrend(
        records: [
          sale(id: 1, createdAt: '2025-10-05 09:00:00', total: 100),
          sale(id: 2, createdAt: '2026-10-05 09:00:00', total: 300),
        ],
        granularity: AnalyticsTrendGranularity.day,
        range: range,
      );
      expect(daily.first.value, closeTo(100, 1e-9));
      expect(daily.last.value, closeTo(300, 1e-9));
      expect(daily.first.label, isNot(daily.last.label));
    });
  });

  group('alignComparisonSeries', () {
    List<AnalyticsNamedValue> series(int days, String prefix) => [
          for (var i = 0; i < days; i++)
            AnalyticsNamedValue(label: '$prefix${i + 1}', value: i + 1.0),
        ];

    test('A longer than B (Oct 31 vs Sep 30) pads B with zeros', () {
      final aligned =
          AnalyticsEngine.alignComparisonSeries(series(31, 'A'), series(30, 'B'));
      expect(aligned.labels, hasLength(31));
      expect(aligned.valuesA, hasLength(31));
      expect(aligned.valuesB, hasLength(31));
      expect(aligned.valuesB.last, 0);
      expect(aligned.valuesA.last, 31);
      expect(aligned.labels.last, 'A31');
    });

    test('B longer than A pads A and borrows B\'s labels', () {
      final aligned =
          AnalyticsEngine.alignComparisonSeries(series(28, 'A'), series(31, 'B'));
      expect(aligned.labels, hasLength(31));
      expect(aligned.valuesA.sublist(28), [0, 0, 0]);
      expect(aligned.valuesB.last, 31);
      expect(aligned.labels.last, 'B31');
    });

    test('empty series', () {
      final aligned = AnalyticsEngine.alignComparisonSeries(const [], const []);
      expect(aligned.labels, isEmpty);
    });
  });

  test('custom range with From after To is swapped, not empty', () {
    final range = AnalyticsEngine.rangeForPreset(
      AnalyticsPeriodPreset.custom,
      customStart: DateTime(2026, 10, 20),
      customEnd: DateTime(2026, 10, 10),
    );
    expect(range.start, DateTime(2026, 10, 10));
    expect(range.end, DateTime(2026, 10, 20, 23, 59, 59, 999));
    expect(range.contains(DateTime(2026, 10, 15, 12)), isTrue);
  });
}
