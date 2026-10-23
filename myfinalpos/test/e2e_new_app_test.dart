@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myfinalpos/config/api_config.dart';
import 'package:myfinalpos/features/transactions/transaction_service.dart';
import 'package:myfinalpos/models/cart_item.dart';
import 'package:myfinalpos/models/product.dart';
import 'package:myfinalpos/models/refund_item_request.dart';
import 'package:myfinalpos/services/api_session.dart';
import 'package:myfinalpos/services/pos_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// New-app-only flows against a LOCAL backend with POS_REQUIRE_TOKEN off:
/// sign-in tokens, price-change refusal, offline sync, duplicate-safe
/// retries, refund amount, stock-safe product edits.
///
///   flutter test test/e2e_new_app_test.dart \
///     --dart-define=API_BASE_URL=http://127.0.0.1:8010/pos_app \
///     --dart-define=E2E_FIXTURE=path/to/fixture.json
const _fixturePath = String.fromEnvironment('E2E_FIXTURE');

void _log(String message) =>
    // ignore: avoid_print
    print('[new] $message');

void main() {
  const api = PosApi();
  final service = TransactionService(apiBaseUrl);
  late Map<String, dynamic> fx;
  late int adminId;
  late int cashierId;

  Future<String> login(String who) async {
    final res = await http.post(
      Uri.parse('$apiBaseUrl/login.php'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': fx[who]['email'], 'password': fx['password']}),
    );
    expect(res.statusCode, 200, reason: res.body);
    return (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String;
  }

  Future<Product> live(String key) async {
    final id = fx['products'][key] as int;
    return (await api.fetchItems()).firstWhere((p) => p.id == id);
  }

  Map<String, dynamic> payloadFor(List<CartItem> cart, {DateTime? soldAt}) {
    final total = cart.fold<double>(0, (s, i) => s + i.total);
    return api.buildOrderPayload(
      cartItems: cart,
      subtotal: total,
      vat: 0,
      totalAmount: total,
      clientChange: 0,
      paymentMethod: 'Cash',
      reference: '',
      discountAmount: 0,
      couponDiscount: 0,
      loyaltyDiscount: 0,
      loyaltyPointsRedeemed: 0,
      actorUserId: cashierId,
      soldAt: soldAt,
    );
  }

  setUpAll(() async {
    if (!isLocalApi || isProductionApi) {
      fail('E2E aborted: API_BASE_URL "$apiBaseUrl" is not a local server.');
    }
    SharedPreferences.setMockInitialValues({});
    fx = jsonDecode(await File(_fixturePath).readAsString()) as Map<String, dynamic>;
    adminId = fx['admin']['id'] as int;
    cashierId = fx['cashier']['id'] as int;
  });

  tearDownAll(() async {
    await ApiSession.clear();
    ApiSession.onSessionExpired = null;
  });

  test('N1. login returns a token and every API call carries it', () async {
    final token = await login('cashier');
    expect(token, hasLength(64));
    await ApiSession.save(token, persist: false);

    final res = await apiHttp.get(Uri.parse('$apiBaseUrl/categories.php'));
    expect(res.statusCode, 200);
    _log('cashier signed in with a token; categories loaded with it');
  });

  test('N2. a cashier token cannot act as the admin', () async {
    final settings = await api.fetchSettings();
    // The request body claims the admin, but the token says cashier.
    await expectLater(
      api.saveSettings(settings: settings, actorUserId: adminId),
      throwsA(anything),
    );
    _log('settings save with cashier token + admin id in body: refused');
  });

  test('N3. a sale is refused if the price changed since the tablet loaded it', () async {
    final stale = await live('lauda');
    final adminToken = await login('admin');
    await ApiSession.save(adminToken, persist: false);
    await api.updateProduct(
      id: stale.id,
      name: stale.name,
      category: stale.category,
      price: stale.price + 50,
      actorUserId: adminId,
    );

    final cart = [CartItem(product: stale, quantity: 2)]; // old price
    await expectLater(
      api.saveOrderPayload(payloadFor(cart)),
      throwsA(isA<OrderTotalChangedException>()),
    );
    expect((await live('lauda')).stock, stale.stock, reason: 'nothing sold');
    _log('stale price ${stale.price} vs server ${stale.price + 50}: sale refused, stock untouched');
  });

  late int offlineOrderId;

  test('N4. a paid offline sale syncs with its own date even though stock ran out', () async {
    final scarce = await live('scarce'); // 1 left
    final soldAt = DateTime.now().subtract(const Duration(days: 2));
    final payload = payloadFor([CartItem(product: scarce, quantity: 2)], soldAt: soldAt);

    // Sent as a normal online sale it is refused (not enough stock)...
    await expectLater(
      api.saveOrderPayload(payload),
      throwsA(isA<OrderRejectedException>()),
    );
    // ...but replayed from the offline queue it is recorded as it happened.
    offlineOrderId = await api.saveOrderPayload({...payload, 'queued_offline': true});
    final saved = (await service.fetchTransactions(orderId: offlineOrderId)).single;
    expect(saved.createdAt.day, soldAt.day);
    expect(saved.totalAmount, closeTo(3000, 0.001));

    // Retrying the same queued sale returns the same order.
    final again = await api.saveOrderPayload({...payload, 'queued_offline': true});
    expect(again, offlineOrderId);
    _log('offline sale #$offlineOrderId dated ${saved.createdAt} (2 days ago), '
        'retry returned the same order, stock now ${(await live('scarce')).stock}');
  });

  test('N5. a refund reports exactly how much to give back', () async {
    final order = (await service.fetchTransactions(orderId: offlineOrderId)).single;
    final result = await service.processRefund(
      orderId: offlineOrderId,
      reason: 'E2E new app',
      refundType: 'items',
      items: [RefundItemRequest(orderItemId: order.items.single.orderItemId, quantity: 1)],
      actorUserId: cashierId,
      refundPin: fx['refund_pin'] as String,
    );
    expect(result.success, isTrue, reason: result.message);
    expect(result.refundAmount, closeTo(1500, 0.001));
    _log('refund amount parsed: ${result.refundAmount}; message "${result.message}"');
  });

  test('N6. order history by date window and single order by id', () async {
    final today = DateTime.now();
    final recent = await api.fetchSalesHistory(from: DateTime(today.year, today.month, today.day - 3));
    expect(recent.any((r) => r.orderId == offlineOrderId), isTrue);
    final single = await service.fetchTransactions(orderId: offlineOrderId);
    expect(single, hasLength(1));
    _log('window from 3 days ago: ${recent.length} orders; lookup by id: 1');
  });

  test('N7. editing a product keeps a sale made while the form was open', () async {
    final feeds = await live('feeds');
    final formStock = feeds.stock!;
    // Another register sells 1 while the edit form is open.
    await api.saveOrderPayload(payloadFor([CartItem(product: feeds, quantity: 1)]));

    final edited = await api.updateProduct(
      id: feeds.id,
      name: feeds.name,
      category: feeds.category,
      price: feeds.price + 1,
      stock: formStock, // what the form showed
      stockBase: formStock,
      actorUserId: adminId,
    );
    expect(edited.stock, closeTo(formStock - 1, 0.0001));
    _log('form showed $formStock, a sale happened, saved price edit -> stock ${edited.stock}');
  });

  test('N8. signing out kills the token; the app is sent back to sign in', () async {
    var expired = 0;
    ApiSession.onSessionExpired = () async => expired++;
    final token = await login('cashier');
    await ApiSession.save(token, persist: false);

    // Sign out from "another tablet": revoke this token on the server.
    final out = await http.post(
      Uri.parse('$apiBaseUrl/logout.php'),
      headers: {'Authorization': 'Bearer $token'},
    );
    expect(out.statusCode, 200);

    await ApiSession.save(token, persist: false);
    final res = await apiHttp.get(Uri.parse('$apiBaseUrl/categories.php'));
    expect(res.statusCode, 401);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(expired, 1);
    expect(ApiSession.hasToken, isFalse);
    _log('revoked token -> 401 token_invalid -> session ended, back to sign-in');
  });
}
