import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingOfflineOrder {
  const PendingOfflineOrder({
    required this.localId,
    required this.displayNumber,
    required this.payload,
    required this.createdAt,
    this.lastError,
  });

  final String localId;
  final int displayNumber;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// Why the server refused this sale (only set on "needs attention" ones).
  final String? lastError;

  factory PendingOfflineOrder.fromJson(Map<String, dynamic> json) {
    return PendingOfflineOrder(
      localId: (json['local_id'] ?? '').toString(),
      displayNumber: int.tryParse('${json['display_number']}') ?? 0,
      payload: Map<String, dynamic>.from(
        (json['payload'] as Map?) ?? const {},
      ),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      lastError: json['last_error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'local_id': localId,
        'display_number': displayNumber,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        if (lastError != null) 'last_error': lastError,
      };

  PendingOfflineOrder withError(String? error) => PendingOfflineOrder(
        localId: localId,
        displayNumber: displayNumber,
        payload: payload,
        createdAt: createdAt,
        lastError: error,
      );
}

/// Sales rung up while offline, waiting to be sent to the server.
///
/// These are paid sales that exist nowhere else, so the file handling is
/// defensive:
/// - every read-modify-write runs one at a time (a sync removing a sale and
///   a new offline sale being queued used to overwrite each other);
/// - writes go to a temp file that is then renamed over the queue, so a
///   crash mid-write can't leave a truncated file;
/// - a file that can't be read is set aside as a backup and never
///   overwritten (it used to be treated as empty and replaced by the next
///   sale, losing everything in it);
/// - a sale the server refuses for good is moved to a "needs attention"
///   list instead of blocking every sale queued after it.
class OfflineOrderQueue {
  static const _counterKey = 'offline_order_counter';
  static const _queueName = 'offline_pos_orders.json';
  static const _attentionName = 'offline_pos_orders_attention.json';

  static Future<void> _tail = Future<void>.value();

  /// Runs [action] after every queue operation started before it.
  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  static Future<List<PendingOfflineOrder>> _read(String name) async {
    final file = await _file(name);
    if (!await file.exists()) return <PendingOfflineOrder>[];

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return <PendingOfflineOrder>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('not a list');
      return decoded
          .whereType<Map>()
          .map(
            (item) => PendingOfflineOrder.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } on FormatException {
      // Keep the unreadable file for recovery and start a fresh one -
      // never write over it.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.rename('${file.path}.unreadable-$stamp');
      return <PendingOfflineOrder>[];
    }
  }

  static Future<void> _write(
    String name,
    List<PendingOfflineOrder> orders,
  ) async {
    final file = await _file(name);
    final temp = File('${file.path}.tmp');
    final encoded = orders.map((order) => order.toJson()).toList();
    await temp.writeAsString(jsonEncode(encoded), flush: true);
    await temp.rename(file.path);
  }

  static Future<List<PendingOfflineOrder>> loadAll() =>
      _serialized(() => _read(_queueName));

  static Future<int> pendingCount() async => (await loadAll()).length;

  /// Sales the server refused (e.g. a product was deleted since). They stay
  /// here, with the reason, until someone retries or resolves them.
  static Future<List<PendingOfflineOrder>> needsAttention() =>
      _serialized(() => _read(_attentionName));

  /// Number of queue files that could not be read and were set aside.
  static Future<int> unreadableBackupCount() async {
    final dir = await getApplicationDocumentsDirectory();
    if (!await dir.exists()) return 0;
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('$_queueName.unreadable-'))
        .length;
  }

  static Future<PendingOfflineOrder> enqueue(
    Map<String, dynamic> payload,
  ) {
    return _serialized(() async {
      final orders = await _read(_queueName);
      final displayNumber = await _nextDisplayNumber();
      final order = PendingOfflineOrder(
        localId: 'off-${DateTime.now().millisecondsSinceEpoch}-'
            '${Random().nextInt(1 << 32).toRadixString(36)}',
        displayNumber: displayNumber,
        payload: payload,
        createdAt: DateTime.now(),
      );
      orders.add(order);
      await _write(_queueName, orders);
      return order;
    });
  }

  static Future<void> remove(String localId) {
    return _serialized(() async {
      final orders = await _read(_queueName);
      orders.removeWhere((order) => order.localId == localId);
      await _write(_queueName, orders);
    });
  }

  /// Moves a sale the server refused out of the way of the others.
  static Future<void> park(String localId, String reason) {
    return _serialized(() async {
      final orders = await _read(_queueName);
      final index = orders.indexWhere((order) => order.localId == localId);
      if (index == -1) return;
      final parked = orders.removeAt(index).withError(reason);
      final attention = await _read(_attentionName)..add(parked);
      await _write(_attentionName, attention);
      await _write(_queueName, orders);
    });
  }

  /// Puts a "needs attention" sale back in the queue to try again.
  static Future<void> retryParked(String localId) {
    return _serialized(() async {
      final attention = await _read(_attentionName);
      final index = attention.indexWhere((order) => order.localId == localId);
      if (index == -1) return;
      final order = attention.removeAt(index).withError(null);
      final orders = await _read(_queueName)..add(order);
      await _write(_queueName, orders);
      await _write(_attentionName, attention);
    });
  }

  static Future<int> _nextDisplayNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_counterKey) ?? 0) + 1;
    await prefs.setInt(_counterKey, next);
    return next;
  }
}
