import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myfinalpos/config/api_config.dart';
import 'package:myfinalpos/models/cart_item.dart';
import 'package:myfinalpos/models/product.dart';
import 'package:myfinalpos/services/api_session.dart';
import 'package:myfinalpos/services/offline/offline_order_queue.dart';
import 'package:myfinalpos/services/pos_api.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

Product _product(double price) => Product.fromJson({
      'id': 1,
      'name': 'FEEDS',
      'category': 'Feeds',
      'price': price,
      'stock': 100,
    });

void main() {
  group('money rounding matches the server', () {
    test('roundMoney rounds half up despite binary error', () {
      expect(roundMoney(1.005), 1.01);
      expect(roundMoney(49.995), 50.0);
      expect(roundMoney(50.512), 50.51);
      expect(roundMoney(-1.005), -1.01);
    });

    test('cart line totals are whole centavos', () {
      final item = CartItem(product: _product(33.33), quantity: 1.5);
      expect(item.grossTotal, 50.0); // 49.995 -> 50.00 like PHP round()
      item.discountPerUnit = 1.11;
      expect(item.discount, 1.67); // 1.665 -> 1.67
      expect(item.total, 48.33);
    });
  });

  group('order payload', () {
    test('every sale gets its own client_order_uuid, sale time and charged total', () {
      final api = PosApi();
      final soldAt = DateTime(2026, 10, 22, 16, 30);
      Map<String, dynamic> build() => api.buildOrderPayload(
            cartItems: [CartItem(product: _product(100), quantity: 2)],
            subtotal: 200,
            vat: 0,
            totalAmount: 200.004,
            clientChange: 0,
            paymentMethod: 'Cash',
            reference: '',
            discountAmount: 0,
            couponDiscount: 0,
            loyaltyDiscount: 0,
            loyaltyPointsRedeemed: 0,
            soldAt: soldAt,
          );

      final a = build();
      final b = build();
      expect(a['client_order_uuid'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(a['client_order_uuid'], isNot(b['client_order_uuid']));
      expect(a['sold_at_ms'], soldAt.millisecondsSinceEpoch);
      expect(a['client_total'], 200.0);
    });
  });

  group('offline order queue', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('offline_queue_test');
      PathProviderPlatform.instance = _FakePathProvider(dir.path);
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('sales queued at the same time are all kept', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++) OfflineOrderQueue.enqueue({'n': i}),
      ]);
      final all = await OfflineOrderQueue.loadAll();
      expect(all, hasLength(20));
      expect(all.map((o) => o.localId).toSet(), hasLength(20));
    });

    test('removing one sale while another is queued loses neither', () async {
      final first = await OfflineOrderQueue.enqueue({'n': 1});
      await Future.wait([
        OfflineOrderQueue.remove(first.localId),
        OfflineOrderQueue.enqueue({'n': 2}),
      ]);
      final all = await OfflineOrderQueue.loadAll();
      expect(all.map((o) => o.payload['n']), [2]);
    });

    test('an unreadable queue file is kept as a backup, never overwritten', () async {
      final file = File('${dir.path}/offline_pos_orders.json');
      await file.writeAsString('[{"local_id": "off-1", "payl'); // truncated
      await OfflineOrderQueue.enqueue({'n': 'new'});

      expect(await OfflineOrderQueue.unreadableBackupCount(), 1);
      final backup = dir
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.contains('.unreadable-'));
      expect(await backup.readAsString(), '[{"local_id": "off-1", "payl');
      expect(await OfflineOrderQueue.pendingCount(), 1);
    });

    test('a refused sale is set aside and can be retried', () async {
      final bad = await OfflineOrderQueue.enqueue({'n': 'bad'});
      await OfflineOrderQueue.enqueue({'n': 'good'});

      await OfflineOrderQueue.park(bad.localId, 'Product #9 not found');
      expect((await OfflineOrderQueue.loadAll()).map((o) => o.payload['n']), ['good']);
      final attention = await OfflineOrderQueue.needsAttention();
      expect(attention.single.lastError, 'Product #9 not found');

      await OfflineOrderQueue.retryParked(bad.localId);
      expect(await OfflineOrderQueue.needsAttention(), isEmpty);
      expect(await OfflineOrderQueue.pendingCount(), 2);
    });
  });

  group('API session token', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('the token is sent to the POS API only', () async {
      await ApiSession.save('tok-123', persist: false);
      final seen = <String, String?>{};
      final client = PosHttpClient(MockClient((request) async {
        seen[request.url.host] = request.headers['Authorization'];
        return http.Response('{"success":true}', 200);
      }));

      await client.get(Uri.parse('$apiBaseUrl/categories.php'));
      await client.get(Uri.parse('https://example.com/other'));

      expect(seen[Uri.parse(apiBaseUrl).host], 'Bearer tok-123');
      expect(seen['example.com'], isNull);
      await ApiSession.clear();
    });

    test('only a token rejection ends the session (not a wrong PIN)', () async {
      var expired = 0;
      ApiSession.onSessionExpired = () async => expired++;
      await ApiSession.save('tok-123', persist: false);

      final wrongPin = PosHttpClient(MockClient((_) async => http.Response(
            jsonEncode({'success': false, 'message': 'Invalid PIN'}),
            401,
          )));
      final res = await wrongPin.post(Uri.parse('$apiBaseUrl/process_refund.php'));
      expect(res.statusCode, 401);
      expect(jsonDecode(res.body)['message'], 'Invalid PIN'); // body still readable
      await Future<void>.delayed(Duration.zero);
      expect(expired, 0);
      expect(ApiSession.hasToken, isTrue);

      final revoked = PosHttpClient(MockClient((_) async => http.Response(
            jsonEncode({'success': false, 'code': 'token_invalid'}),
            401,
          )));
      await revoked.get(Uri.parse('$apiBaseUrl/categories.php'));
      await Future<void>.delayed(Duration.zero);
      expect(expired, 1);
      expect(ApiSession.hasToken, isFalse);
      ApiSession.onSessionExpired = null;
    });
  });
}
