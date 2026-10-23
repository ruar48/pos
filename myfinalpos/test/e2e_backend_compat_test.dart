@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myfinalpos/config/api_config.dart';
import 'package:myfinalpos/features/receipt/receipt_printer.dart';
import 'package:myfinalpos/features/transactions/transaction_model.dart';
import 'package:myfinalpos/features/transactions/transaction_service.dart';
import 'package:myfinalpos/models/cart_item.dart';
import 'package:myfinalpos/models/order_payment.dart';
import 'package:myfinalpos/models/product.dart';
import 'package:myfinalpos/models/refund_item_request.dart';
import 'package:myfinalpos/services/pos_api.dart';

/// Same end-to-end flows for the OLD tablet app (commit e42179f) and the NEW
/// one, each through its own API code, against the NEW backend on a LOCAL
/// Laravel with POS_REQUIRE_TOKEN off.
///
///   flutter test test/e2e_backend_compat_test.dart \
///     --dart-define=API_BASE_URL=http://127.0.0.1:8010/pos_app \
///     --dart-define=E2E_FIXTURE=path/to/fixture.json --dart-define=APP_LABEL=old
const _label = String.fromEnvironment('APP_LABEL', defaultValue: 'app');
const _fixturePath = String.fromEnvironment('E2E_FIXTURE');

/// Running against the backend from before the bug-fix rework (e42179f):
/// the checks for server features it doesn't have only record what happened.
const _oldBackend = bool.fromEnvironment('OLD_BACKEND');

void _log(String message) =>
    // ignore: avoid_print
    print('[$_label] $message');

void main() {
  const api = PosApi();
  final service = TransactionService(apiBaseUrl);
  late Map<String, dynamic> fx;
  late int adminId;
  late int cashierId;
  late Map<int, Product> catalog;

  Product product(String key) => catalog[fx['products'][key] as int]!;

  Future<TransactionRecord> order(int id) async {
    final found = await service.fetchTransactionDetail(id);
    expect(found, isNotNull, reason: 'order $id should be readable back');
    return found!;
  }

  Future<int> checkout({
    required List<CartItem> cart,
    int? customerId,
    double manual = 0,
    String coupon = '',
    double couponAmount = 0,
    int points = 0,
    double loyaltyPeso = 0,
    List<OrderPayment>? split,
    String method = 'Cash',
  }) {
    final subtotal = cart.fold<double>(0, (s, i) => s + i.total);
    final total = subtotal - manual - couponAmount - loyaltyPeso;
    final payload = api.buildOrderPayload(
      customerId: customerId,
      cartItems: cart,
      subtotal: total,
      vat: 0,
      totalAmount: total,
      clientChange: 0,
      paymentMethod: split != null ? 'Split (Cash + GCash)' : method,
      reference: method == 'GCash' ? 'GC-REF-1' : '',
      discountAmount: manual,
      couponDiscount: couponAmount,
      couponCode: coupon,
      loyaltyDiscount: loyaltyPeso,
      loyaltyPointsRedeemed: points,
      actorUserId: cashierId,
      payments: split?.map((p) => p.toJson()).toList(),
    );
    return api.saveOrderPayload(payload);
  }

  setUpAll(() async {
    if (!isLocalApi || isProductionApi) {
      fail('E2E aborted: API_BASE_URL "$apiBaseUrl" is not a local server.');
    }
    fx = jsonDecode(await File(_fixturePath).readAsString()) as Map<String, dynamic>;
    adminId = fx['admin']['id'] as int;
    cashierId = fx['cashier']['id'] as int;
  });

  test('1. sign in (admin and cashier)', () async {
    for (final who in ['admin', 'cashier']) {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/login.php'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': fx[who]['email'], 'password': fx['password']}),
      );
      expect(res.statusCode, 200, reason: res.body);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['success'], isTrue);
      expect(body['user']['id'], fx[who]['id']);
      _log('$who login OK (server also returned a token: ${body['token'] != null})');
    }
  });

  test('2. load catalog, customers, loyalty cards, coupons, settings', () async {
    final items = await api.fetchItems();
    catalog = {for (final p in items) p.id: p};
    for (final key in ['cartap', 'lauda', 'feeds', 'scarce']) {
      expect(catalog.containsKey(fx['products'][key]), isTrue, reason: key);
    }
    final customers = await api.fetchCustomers();
    expect(customers.any((c) => c.id == fx['customer_id']), isTrue);
    final cards = await api.fetchLoyaltyCards();
    expect(cards.any((c) => c.customerId == fx['customer_id']), isTrue);
    final coupons = await api.fetchCoupons();
    expect(coupons.any((c) => c.code == fx['coupon']), isTrue);
    final settings = await api.fetchSettings();
    _log('catalog ${items.length} items, tax ${settings.taxRate}, '
        'loyalty ${settings.loyaltyPointsPerUnit} pt / ${settings.loyaltySpendUnit} spent');
  });

  late int discountOrderId;

  test('3. cash sale with item discounts AND a manual discount (the INV-013507 case)', () async {
    final cartap = product('cartap');
    final lauda = product('lauda');
    final stockBefore = cartap.stock!;
    final cart = [
      CartItem(product: cartap, quantity: 120, discountPerUnit: 31), // 14,400 - 3,720
      CartItem(product: lauda, quantity: 12, discountPerUnit: 140), // 7,800 - 1,680
    ];
    discountOrderId = await checkout(cart: cart, manual: 1000);

    final saved = await order(discountOrderId);
    // 10,680 + 6,120 - 1,000 manual = 15,800
    expect(saved.totalAmount, closeTo(15800, 0.001));
    expect(saved.items.map((i) => i.subtotal).toList(), [10680, 6120]);

    final after = {for (final p in await api.fetchItems()) p.id: p};
    expect(after[cartap.id]!.stock, closeTo(stockBefore - 120, 0.0001));
    _log('discount sale #$discountOrderId total ${saved.totalAmount}');
  });

  test('4. reprint of that sale reconciles: SUBTOTAL - DISCOUNT = TOTAL', () async {
    final receipt = service.buildReceiptData(await order(discountOrderId));
    final lines = ThermalReceiptLayout(receipt).buildLines();
    String amount(String label) => lines
        .firstWhere((l) => l.startsWith(label))
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.\-]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .last;
    final subtotal = double.parse(amount('SUBTOTAL'));
    final discount = double.parse(amount('DISCOUNT')).abs();
    final total = double.parse(amount('TOTAL '));
    _log('reprint SUBTOTAL $subtotal  DISCOUNT $discount  TOTAL $total');
    expect(total, closeTo(15800, 0.001));
    final reconciles = (subtotal - discount - total).abs() <= 0.01;
    if (!reconciles && _label == 'old') {
      // The old app's reprint hides the manual discount when item
      // discounts exist (the INV-013507 receipt bug, fixed in the new app).
      _log('KNOWN OLD-APP RECEIPT BUG: SUBTOTAL - DISCOUNT != TOTAL (TOTAL itself is right)');
      return;
    }
    expect(reconciles, isTrue);
  });

  late int loyaltyOrderId;
  late int pointsBefore;

  test('5. loyalty customer: item discount + coupon + points redeemed', () async {
    final settings = await api.fetchSettings();
    pointsBefore = (await api.fetchLoyaltyCards())
        .firstWhere((c) => c.customerId == fx['customer_id'])
        .points;
    final cart = [
      CartItem(product: product('cartap'), quantity: 10, discountPerUnit: 5), // 1,150
      CartItem(product: product('feeds'), quantity: 1.5), // 49.995 -> 50.00 on the server
    ];
    const points = 300;
    final peso = settings.pesoValueForPoints(points);
    loyaltyOrderId = await checkout(
      cart: cart,
      customerId: fx['customer_id'] as int,
      coupon: fx['coupon'] as String,
      couponAmount: 100,
      points: points,
      loyaltyPeso: peso,
    );

    final saved = await order(loyaltyOrderId);
    final expected = 1150 + 50.00 - 100 - peso;
    expect(saved.totalAmount, closeTo(expected, 0.011));
    final pointsAfter = (await api.fetchLoyaltyCards())
        .firstWhere((c) => c.customerId == fx['customer_id'])
        .points;
    final earned = settings.pointsEarnedForAmount(saved.totalAmount);
    expect(pointsAfter, pointsBefore - points + earned);
    _log('loyalty sale #$loyaltyOrderId total ${saved.totalAmount}, '
        'points $pointsBefore -> $pointsAfter (redeemed $points, earned $earned)');
  });

  test('6. split payment (Cash + GCash with reference)', () async {
    final id = await checkout(
      cart: [CartItem(product: product('lauda'), quantity: 2)],
      split: const [
        OrderPayment(paymentMethod: 'Cash', amount: 1000, reference: ''),
        OrderPayment(paymentMethod: 'GCash', amount: 300, reference: 'GC-778899'),
      ],
    );
    final saved = await order(id);
    expect(saved.totalAmount, closeTo(1300, 0.001));
    expect(saved.splitPayments.map((p) => p.amount).toList(), [1000, 300]);
    _log('split sale #$id payments ${saved.splitPayments.map((p) => '${p.paymentMethod} ${p.amount}').join(' + ')}');
  });

  test('7. sales history and order list include the new sales', () async {
    final history = await api.fetchSalesHistory();
    final ids = history.map((r) => r.orderId).toSet();
    expect(ids.containsAll([discountOrderId, loyaltyOrderId]), isTrue);
    final list = await service.fetchTransactions();
    expect(list.any((t) => t.id == loyaltyOrderId), isTrue);
    _log('history ${history.length} orders, order list ${list.length}');
  });

  test('8. partial refund pays a fair share, says how much, restocks', () async {
    final before = await order(loyaltyOrderId);
    final cartapLine = before.items.firstWhere((i) => i.productId == product('cartap').id);
    final stockBefore = {for (final p in await api.fetchItems()) p.id: p}[product('cartap').id]!.stock!;

    final result = await service.processRefund(
      orderId: loyaltyOrderId,
      reason: 'E2E partial',
      refundType: 'items',
      items: [RefundItemRequest(orderItemId: cartapLine.orderItemId, quantity: 5)],
      actorUserId: cashierId,
      refundPin: fx['refund_pin'] as String,
    );
    expect(result.success, isTrue, reason: result.message);
    if (_oldBackend) {
      _log('OLD BACKEND: no give-back amount in the message');
    } else {
      expect(result.message, contains('Give back'));
    }

    final after = await order(loyaltyOrderId);
    expect(after.refundedAmount, greaterThan(0));
    expect(after.refundedAmount, lessThan(before.totalAmount));
    final stockAfter = {for (final p in await api.fetchItems()) p.id: p}[product('cartap').id]!.stock!;
    expect(stockAfter, closeTo(stockBefore + 5, 0.0001));
    _log('partial refund: "${result.message}" (refunded ${after.refundedAmount} of ${before.totalAmount})');
  });

  test('9. refunding the rest returns exactly what was paid and all points', () async {
    final before = await order(loyaltyOrderId);
    final result = await service.processRefund(
      orderId: loyaltyOrderId,
      reason: 'E2E rest',
      refundType: 'all',
      items: const [],
      actorUserId: cashierId,
      refundPin: fx['refund_pin'] as String,
    );
    expect(result.success, isTrue, reason: result.message);
    final after = await order(loyaltyOrderId);
    expect(after.refundedAmount, closeTo(before.totalAmount, 0.001));
    final points = (await api.fetchLoyaltyCards())
        .firstWhere((c) => c.customerId == fx['customer_id'])
        .points;
    if (_oldBackend) {
      _log('OLD BACKEND: loyalty points not reversed by the refund ($points, was $pointsBefore)');
    } else {
      expect(points, pointsBefore, reason: 'redeemed points returned, earned points taken back');
    }
    _log('full refund: refunded ${after.refundedAmount} = total ${after.totalAmount}; points back to $points');
  });

  test('10. wrong refund PIN is refused', () async {
    final result = await service.processRefund(
      orderId: discountOrderId,
      reason: 'E2E wrong pin',
      refundType: 'all',
      items: const [],
      actorUserId: cashierId,
      refundPin: '0000',
    );
    expect(result.success, isFalse);
    _log('wrong PIN: "${result.message}"');
  });

  test('11. stock adjust (absolute and delta) and product edit', () async {
    final lauda = product('lauda');
    final set = await api.updateProductStock(productId: lauda.id, stock: 80, actorUserId: adminId);
    expect(set.stock, closeTo(80, 0.0001));
    final added = await api.updateProductStock(productId: lauda.id, delta: 5, actorUserId: adminId);
    expect(added.stock, closeTo(85, 0.0001));

    final feeds = product('feeds');
    final live = {for (final p in await api.fetchItems()) p.id: p}[feeds.id]!;
    final edited = await api.updateProduct(
      id: feeds.id,
      name: live.name,
      category: live.category,
      price: 34,
      stock: live.stock,
      actorUserId: adminId,
    );
    expect(edited.price, closeTo(34, 0.001));
    expect(edited.stock, closeTo(live.stock!, 0.0001));
    _log('stock set 80, +5 -> ${added.stock}; feeds price 33.33 -> ${edited.price}');
  });

  test('12. settings: admin can save, cashier cannot', () async {
    final settings = await api.fetchSettings();
    final saved = await api.saveSettings(settings: settings, actorUserId: adminId);
    expect(saved.taxRate, settings.taxRate);
    if (_oldBackend) {
      await api.saveSettings(settings: settings, actorUserId: cashierId);
      _log('OLD BACKEND: a cashier can save settings');
      return;
    }
    await expectLater(
      api.saveSettings(settings: settings, actorUserId: cashierId),
      throwsA(anything),
    );
    _log('settings saved as admin; cashier refused');
  });

  test('13. a sale sent twice (lost response then retry)', () async {
    final lauda = product('lauda');
    final payload = api.buildOrderPayload(
      cartItems: [CartItem(product: lauda, quantity: 1)],
      subtotal: 650,
      vat: 0,
      totalAmount: 650,
      clientChange: 0,
      paymentMethod: 'Cash',
      reference: '',
      discountAmount: 0,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      loyaltyPointsRedeemed: 0,
      actorUserId: cashierId,
    );
    final first = await api.saveOrderPayload(payload);
    final second = await api.saveOrderPayload(payload);
    if (payload.containsKey('client_order_uuid') && !_oldBackend) {
      expect(second, first);
      _log('retry returned the same order #$first (no duplicate)');
    } else {
      expect(second, isNot(first));
      _log('retry created a SECOND order (#$first and #$second) - '
          'no duplicate protection in the old app or old backend');
    }
  });
}
