import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Keeps the order lists working against a backend from before the update.
///
/// The updated get_orders.php filters by `from` / `to` / `order_id` and
/// answers in about a second. An older backend ignores those filters and
/// sends every order ever made - 14 MB in ~13 s for this store - which ran
/// past the app's 10-12 s limits ("Could not load orders"). When a reply
/// shows the filters were ignored, the app waits longer, trims the list
/// itself and reuses the full list instead of downloading it again.
class OrdersApiCompat {
  OrdersApiCompat._();

  /// True once a get_orders.php reply contained orders outside the filter.
  static bool serverIgnoresFilters = false;

  /// How long to wait for an order list. Generous on an older backend,
  /// whose full history keeps growing.
  static Duration get timeout => serverIgnoresFilters
      ? const Duration(seconds: 120)
      : const Duration(seconds: 60);
}

/// Decodes JSON, moving large replies (the full order history) off the UI
/// thread so the register doesn't freeze while 14 MB are parsed.
Future<Object?> decodeJsonOffUiThread(String body) {
  if (body.length < 256 * 1024) return Future.value(jsonDecode(body));
  return compute(_decodeJson, body);
}

Object? _decodeJson(String body) => jsonDecode(body);

/// Applies the order filters on the tablet when the server didn't.
///
/// Dates get a one-day margin: the server filters by store (Manila) date
/// and a tablet set to another time zone sees times shifted by some hours,
/// so only orders clearly outside the range count as "not filtered" -
/// otherwise a correctly filtered reply could be trimmed or mistaken for an
/// old backend.
List<T> applyOrderFilters<T>(
  List<T> orders, {
  required int Function(T) idOf,
  required DateTime Function(T) createdAtOf,
  DateTime? from,
  DateTime? to,
  int? orderId,
}) {
  if (orderId != null) {
    final kept = orders.where((order) => idOf(order) == orderId).toList();
    if (kept.length != orders.length) OrdersApiCompat.serverIgnoresFilters = true;
    return kept;
  }

  final earliest = from == null ? null : DateTime(from.year, from.month, from.day - 1);
  final latest = to == null ? null : DateTime(to.year, to.month, to.day + 2);
  if (earliest == null && latest == null) return orders;

  final kept = orders.where((order) {
    final at = createdAtOf(order);
    if (earliest != null && at.isBefore(earliest)) return false;
    if (latest != null && !at.isBefore(latest)) return false;
    return true;
  }).toList();
  if (kept.length != orders.length) OrdersApiCompat.serverIgnoresFilters = true;
  return kept;
}
