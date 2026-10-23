import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/models/sales_history_record.dart';

/// An order row shaped like get_orders.php (DECIMAL columns as strings).
Map<String, dynamic> orderJson({
  int id = 1,
  String subtotal = '1000.00',
  String vat = '120.00',
  String total = '1120.00',
  String refunded = '0.00',
  String status = 'completed',
  String discount = '0.00',
  String coupon = '0.00',
  String loyalty = '0.00',
  List<Map<String, dynamic>>? items,
}) {
  return {
    'id': id,
    'customer_id': null,
    'branch_id': 1,
    'subtotal': subtotal,
    'vat': vat,
    'total_amount': total,
    'discount_amount': discount,
    'coupon_discount': coupon,
    'loyalty_discount': loyalty,
    'loyalty_points_redeemed': 0,
    'client_change': '0.00',
    'payment_method': 'Cash',
    'reference': '',
    'created_at': '2026-10-15 10:30:00',
    'status': status,
    'refunded_amount': refunded,
    'customer_name': 'Walk In Farmer',
    'items': items ??
        [
          lineJson(productId: 1, name: 'Urea 50kg', qty: '2.000', price: '400.00'),
          lineJson(productId: 2, name: 'Seeds', qty: '0.500', price: '400.00'),
        ],
  };
}

Map<String, dynamic> lineJson({
  required int productId,
  required String name,
  required String qty,
  required String price,
  String refundedQty = '0.000',
  String discount = '0.00',
  String? total,
}) {
  final lineTotal = total ??
      (double.parse(qty) * double.parse(price) - double.parse(discount))
          .toStringAsFixed(2);
  return {
    'product_id': productId,
    'product_name': name,
    'quantity': qty,
    'refunded_quantity': refundedQty,
    'price': price,
    'discount_amount': discount,
    'total': lineTotal,
  };
}

void main() {
  group('SalesHistoryRecord.fromOrderJson', () {
    test('sums DECIMAL-string quantities as doubles (was always 0)', () {
      final record = SalesHistoryRecord.fromOrderJson(orderJson());
      expect(record.itemCount, closeTo(2.5, 1e-9));
      expect(record.items.first.quantity, 2);
    });

    test('reads refunded_amount and per-line refunded_quantity', () {
      final record = SalesHistoryRecord.fromOrderJson(
        orderJson(
          refunded: '448.00',
          status: 'partial_refund',
          items: [
            lineJson(
              productId: 1,
              name: 'Urea 50kg',
              qty: '2.000',
              price: '400.00',
              refundedQty: '1.000',
            ),
            lineJson(productId: 2, name: 'Seeds', qty: '0.500', price: '400.00'),
          ],
        ),
      );
      expect(record.refundedAmount, 448);
      expect(record.refundedQuantityAt(0), 1);
      expect(record.refundedQuantityAt(1), 0);
      expect(record.refundedQuantityAt(5), 0);
      expect(record.hasRefund, isTrue);
      expect(record.isFullyRefunded, isFalse);
      expect(record.netTotal, closeTo(672, 1e-9));
      expect(record.netFactor, closeTo(0.6, 1e-9));
      expect(record.netVat, closeTo(72, 1e-9));
    });

    test('missing refund fields mean no refund', () {
      final json = orderJson()
        ..remove('refunded_amount')
        ..remove('status');
      final record = SalesHistoryRecord.fromOrderJson(json);
      expect(record.refundedAmount, 0);
      expect(record.hasRefund, isFalse);
      expect(record.netTotal, record.total);
      expect(identical(record.netItems, record.items), isTrue);
    });
  });

  group('net of refunds', () {
    test('netItems scale each line by its remaining quantity', () {
      final record = SalesHistoryRecord.fromOrderJson(
        orderJson(
          refunded: '448.00',
          status: 'partial_refund',
          items: [
            lineJson(
              productId: 1,
              name: 'Urea 50kg',
              qty: '2.000',
              price: '400.00',
              refundedQty: '1.000',
              discount: '20.00',
            ),
            lineJson(
              productId: 2,
              name: 'Seeds',
              qty: '0.500',
              price: '400.00',
              refundedQty: '0.500',
            ),
          ],
        ),
      );
      final net = record.netItems;
      // The fully returned Seeds line drops out.
      expect(net, hasLength(1));
      expect(net.single.productName, 'Urea 50kg');
      expect(net.single.quantity, 1);
      expect(net.single.total, closeTo(390, 1e-9)); // (800 - 20) / 2
      expect(net.single.discount, closeTo(10, 1e-9));
      expect(record.netItemCount, 1);
    });

    test('an amount-only refund scales every line by the money kept', () {
      final record = SalesHistoryRecord.fromOrderJson(
        orderJson(refunded: '280.00', status: 'partial_refund'),
      );
      // 280 of 1120 refunded -> 75% kept.
      final net = record.netItems;
      expect(net, hasLength(2));
      expect(net[0].quantity, closeTo(1.5, 1e-9));
      expect(net[0].total, closeTo(600, 1e-9));
      expect(net[1].quantity, closeTo(0.375, 1e-9));
      expect(record.netItemCount, closeTo(1.875, 1e-9));
    });

    test('a fully refunded order is not revenue', () {
      final record = SalesHistoryRecord.fromOrderJson(
        orderJson(refunded: '1120.00', status: 'refunded'),
      );
      expect(record.isFullyRefunded, isTrue);
      expect(record.netTotal, 0);
      expect(record.netVat, 0);
      expect(record.netItems, isEmpty);
      expect(record.netItemCount, 0);
    });

    test('refunded_amount reaching the total counts as fully refunded', () {
      final record = SalesHistoryRecord.fromOrderJson(
        orderJson(refunded: '1120.00', status: 'completed'),
      );
      expect(record.isFullyRefunded, isTrue);
      expect(record.netTotal, 0);
    });

    test('a ₱0 order is refunded once every unit is back', () {
      final kept = SalesHistoryRecord.fromOrderJson(
        orderJson(subtotal: '0', vat: '0', total: '0'),
      );
      expect(kept.isFullyRefunded, isFalse);

      final returned = SalesHistoryRecord.fromOrderJson(
        orderJson(
          subtotal: '0',
          vat: '0',
          total: '0',
          items: [
            lineJson(
              productId: 1,
              name: 'Free sample',
              qty: '1.000',
              price: '0.00',
              refundedQty: '1.000',
            ),
          ],
        ),
      );
      expect(returned.isFullyRefunded, isTrue);
    });
  });

  test('grossSubtotal adds the discounts back to the stored subtotal', () {
    // Stored subtotal is net of every discount: 1000 - 50 - 30 - 20 = 900.
    final record = SalesHistoryRecord.fromOrderJson(
      orderJson(
        subtotal: '900.00',
        vat: '108.00',
        total: '1008.00',
        discount: '50.00',
        coupon: '30.00',
        loyalty: '20.00',
      ),
    );
    expect(record.totalDiscount, 100);
    expect(record.grossSubtotal, 1000);
    // Subtotal - Discount + VAT == Total, as the details dialog shows it.
    expect(
      record.grossSubtotal - record.totalDiscount + record.vat,
      closeTo(record.total, 1e-9),
    );
  });
}
