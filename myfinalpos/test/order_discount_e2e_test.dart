@Tags(['e2e'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myfinalpos/config/api_config.dart';
import 'package:myfinalpos/models/cart_item.dart';
import 'package:myfinalpos/models/product.dart';
import 'package:myfinalpos/services/pos_api.dart';

/// End-to-end check that a per-piece item discount survives the trip through
/// CartItem.toJson() -> POST /pos_app/orders.php -> MySQL -> get_orders.php.
///
/// Run against a LOCAL Laravel only:
///   flutter test test/order_discount_e2e_test.dart \
///     --dart-define=API_BASE_URL=http://127.0.0.1:8010/pos_app
void main() {
  const api = PosApi();

  setUpAll(() {
    // Hard stop: the app defaults to the hosted API, so refuse to run unless
    // the base URL was explicitly pointed at a local server.
    if (!isLocalApi || isProductionApi) {
      fail(
        'E2E aborted: API_BASE_URL is "$apiBaseUrl". This test only runs '
        'against a local Laravel. Pass '
        '--dart-define=API_BASE_URL=http://127.0.0.1:8010/pos_app',
      );
    }
  });

  test('per-piece discount reaches the backend as the line total', () async {
    final items = await api.fetchItems();
    expect(items, isNotEmpty, reason: 'local catalog should have products');

    final product = items.firstWhere(
      (p) => (p.stock ?? 0) > 5 && p.price > 0 && !p.hasVarieties,
      orElse: () => items.first,
    );

    // The reported scenario: a per-piece discount on a 2-qty line.
    const perUnitDiscount = 50.0;
    final item = CartItem(
      product: product,
      quantity: 2,
      discountPerUnit: perUnitDiscount,
    );

    final expectedGross = product.price * 2;
    final expectedDiscount = perUnitDiscount * 2;
    final expectedSubtotal = expectedGross - expectedDiscount;

    // Client-side maths first.
    expect(item.discount, expectedDiscount);
    expect(item.total, expectedSubtotal);
    expect(item.toJson()['discount'], expectedDiscount);
    expect(item.toJson()['discount_per_unit'], perUnitDiscount);

    final payload = api.buildOrderPayload(
      cartItems: [item],
      subtotal: expectedSubtotal,
      vat: 0,
      totalAmount: expectedSubtotal,
      clientChange: 0,
      paymentMethod: 'cash',
      reference: 'E2E-DISCOUNT-TEST',
      discountAmount: 0,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      loyaltyPointsRedeemed: 0,
      receiptNote: 'automated per-piece discount e2e',
    );

    final orderId = await api.saveOrderPayload(payload);
    expect(orderId, greaterThan(0));
    // Surface the id so the row can be cleaned up.
    // ignore: avoid_print
    print('E2E_ORDER_ID=$orderId');

    // Read it back through the API the app actually uses.
    final res = await http
        .get(Uri.parse('$apiBaseUrl/get_orders.php?order_id=$orderId'))
        .timeout(const Duration(seconds: 20));
    expect(res.statusCode, 200);

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['success'], true);

    final raw = body['data'];
    final order = (raw is List ? raw.first : raw) as Map<String, dynamic>;
    final orderItems = (order['items'] as List).cast<Map<String, dynamic>>();
    expect(orderItems, hasLength(1));

    final saved = orderItems.first;
    double num0(Object? v) => double.parse('${v ?? 0}');

    expect(num0(saved['quantity']), 2);
    expect(
      num0(saved['discount_amount'] ?? saved['discount']),
      expectedDiscount,
      reason: 'backend must store P${expectedDiscount.toStringAsFixed(0)} '
          '(P$perUnitDiscount x 2), not the per-piece figure',
    );
    expect(num0(order['subtotal']), expectedSubtotal);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
