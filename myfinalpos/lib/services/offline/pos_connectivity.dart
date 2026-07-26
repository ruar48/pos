import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

/// Tracks whether the POS API is reachable (not just Wi‑Fi/cellular link).
class PosConnectivity extends ChangeNotifier {
  PosConnectivity._();

  static final PosConnectivity instance = PosConnectivity._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = false;
  bool _initialCheckComplete = false;
  bool _checking = false;
  DateTime? _lastChecked;

  bool get isOnline => _isOnline;
  bool get isOffline => _initialCheckComplete && !_isOnline;

  /// Call after a successful API round-trip (e.g. login) so the register does
  /// not briefly show offline before the first connectivity ping finishes.
  void noteApiReachable() {
    _initialCheckComplete = true;
    _setOnline(true);
  }

  Future<void> start() async {
    await refresh(force: true);
    await _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((_) {
      unawaited(refresh(force: true));
    });
  }

  Future<void> disposeListener() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> refresh({bool force = false}) async {
    if (_checking) return;
    if (!force &&
        _lastChecked != null &&
        DateTime.now().difference(_lastChecked!) <
            const Duration(seconds: 8)) {
      return;
    }

    _checking = true;
    try {
      // POS "online" means the API responds — not merely Wi‑Fi/cellular link.
      // Some tablets/emulators report no link incorrectly while the API works.
      final reachable = await _pingApi();
      _setOnline(reachable);
    } finally {
      _checking = false;
      _lastChecked = DateTime.now();
      final wasUnknown = !_initialCheckComplete;
      _initialCheckComplete = true;
      if (wasUnknown) {
        notifyListeners();
      }
    }
  }

  Future<bool> _pingApi() async {
    const timeout = Duration(seconds: 8);
    final endpoints = <String>[
      '$apiBaseUrl/health',
      '$apiBaseUrl/settings.php',
      '$apiBaseUrl/items.php',
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await http.get(Uri.parse(endpoint)).timeout(timeout);
        final status = response.statusCode;
        if (status >= 200 && status < 500) {
          return true;
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('PosConnectivity ping failed ($endpoint): $error');
        }
      }
    }

    return false;
  }

  void _setOnline(bool value) {
    if (_isOnline == value) return;
    _isOnline = value;
    notifyListeners();
  }
}
