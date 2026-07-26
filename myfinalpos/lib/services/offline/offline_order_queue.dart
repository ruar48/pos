import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingOfflineOrder {
  const PendingOfflineOrder({
    required this.localId,
    required this.displayNumber,
    required this.payload,
    required this.createdAt,
  });

  final String localId;
  final int displayNumber;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  factory PendingOfflineOrder.fromJson(Map<String, dynamic> json) {
    return PendingOfflineOrder(
      localId: (json['local_id'] ?? '').toString(),
      displayNumber: int.tryParse('${json['display_number']}') ?? 0,
      payload: Map<String, dynamic>.from(
        (json['payload'] as Map?) ?? const {},
      ),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'local_id': localId,
        'display_number': displayNumber,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
      };
}

class OfflineOrderQueue {
  static const _counterKey = 'offline_order_counter';

  static Future<File> _queueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/offline_pos_orders.json');
  }

  static Future<List<PendingOfflineOrder>> loadAll() async {
    final file = await _queueFile();
    if (!await file.exists()) return <PendingOfflineOrder>[];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <PendingOfflineOrder>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => PendingOfflineOrder.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (_) {
      return <PendingOfflineOrder>[];
    }
  }

  static Future<int> pendingCount() async {
    return (await loadAll()).length;
  }

  static Future<PendingOfflineOrder> enqueue(
    Map<String, dynamic> payload,
  ) async {
    final orders = await loadAll();
    final displayNumber = await _nextDisplayNumber();
    final order = PendingOfflineOrder(
      localId: 'off-${DateTime.now().millisecondsSinceEpoch}',
      displayNumber: displayNumber,
      payload: payload,
      createdAt: DateTime.now(),
    );
    orders.add(order);
    await _writeAll(orders);
    return order;
  }

  static Future<void> remove(String localId) async {
    final orders = await loadAll();
    orders.removeWhere((order) => order.localId == localId);
    await _writeAll(orders);
  }

  static Future<void> _writeAll(List<PendingOfflineOrder> orders) async {
    final file = await _queueFile();
    final encoded = orders.map((order) => order.toJson()).toList();
    await file.writeAsString(jsonEncode(encoded));
  }

  static Future<int> _nextDisplayNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_counterKey) ?? 0) + 1;
    await prefs.setInt(_counterKey, next);
    return next;
  }
}
