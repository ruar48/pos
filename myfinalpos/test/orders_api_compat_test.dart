import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/services/orders_api_compat.dart';

typedef _Order = ({int id, DateTime at});

List<_Order> _trim(
  List<_Order> orders, {
  DateTime? from,
  DateTime? to,
  int? orderId,
}) =>
    applyOrderFilters<_Order>(
      orders,
      idOf: (o) => o.id,
      createdAtOf: (o) => o.at,
      from: from,
      to: to,
      orderId: orderId,
    );

void main() {
  setUp(() => OrdersApiCompat.serverIgnoresFilters = false);

  test('a reply the server already filtered is left alone', () {
    final orders = [
      (id: 1, at: DateTime(2026, 9, 1, 0, 30)),
      (id: 2, at: DateTime(2026, 10, 23, 12)),
    ];
    final kept = _trim(orders, from: DateTime(2026, 9, 1));
    expect(kept, hasLength(2));
    expect(OrdersApiCompat.serverIgnoresFilters, isFalse);
    expect(OrdersApiCompat.timeout, const Duration(seconds: 60));
  });

  test('a tablet in another time zone is not mistaken for an old backend', () {
    // Sep 1 00:30 Manila seen on a UTC emulator is Aug 31 16:30.
    final kept = _trim(
      [(id: 1, at: DateTime(2026, 8, 31, 16, 30))],
      from: DateTime(2026, 9, 1),
    );
    expect(kept, hasLength(1));
    expect(OrdersApiCompat.serverIgnoresFilters, isFalse);
  });

  test('an old backend sending every order is trimmed and remembered', () {
    final orders = [
      (id: 1, at: DateTime(2025, 1, 5)),
      (id: 2, at: DateTime(2026, 6, 1)),
      (id: 3, at: DateTime(2026, 10, 20)),
    ];
    final kept = _trim(orders, from: DateTime(2026, 9, 1));
    expect(kept.map((o) => o.id), [3]);
    expect(OrdersApiCompat.serverIgnoresFilters, isTrue);
    expect(OrdersApiCompat.timeout, const Duration(seconds: 120));
  });

  test('a lookup by id picks that order out of a full list', () {
    final orders = [
      (id: 7, at: DateTime(2026, 10, 1)),
      (id: 8, at: DateTime(2026, 10, 2)),
    ];
    expect(_trim(orders, orderId: 8).map((o) => o.id), [8]);
    expect(OrdersApiCompat.serverIgnoresFilters, isTrue);
  });

  test('to-date filter keeps the whole last day', () {
    final orders = [
      (id: 1, at: DateTime(2026, 8, 31, 23, 59)),
      (id: 2, at: DateTime(2026, 9, 5)),
    ];
    final kept = _trim(orders, from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31));
    expect(kept.map((o) => o.id), [1]);
  });

  test('large replies decode off the UI thread with the same result', () async {
    final big = jsonEncode({
      'success': true,
      'data': [for (var i = 0; i < 5000; i++) {'id': i, 'note': 'x' * 60}],
    });
    expect(big.length, greaterThan(256 * 1024));
    final decoded = await decodeJsonOffUiThread(big) as Map<String, dynamic>;
    expect((decoded['data'] as List).length, 5000);
    expect(await decodeJsonOffUiThread('{"a":1}'), {'a': 1});
  });
}
