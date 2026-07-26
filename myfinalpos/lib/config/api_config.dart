import 'package:flutter/foundation.dart';

/// Hosted Agriculture POS API (production / release builds).
///
/// Site: https://posmunoz.store/
/// API:  https://posmunoz.store/pos_app
const String kProductionApiBaseUrl = 'https://posmunoz.store/pos_app';

/// Local Laravel (`php artisan serve --host=0.0.0.0 --port=8000`).
/// Android emulator uses 10.0.2.2 to reach the host PC.
const String kLocalApiBaseUrl = 'http://10.0.2.2:8000/pos_app';

/// Override any build: `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000/pos_app`
String get apiBaseUrl {
  const fromEnv = String.fromEnvironment('API_BASE_URL');
  if (fromEnv.isNotEmpty) {
    return fromEnv.endsWith('/')
        ? fromEnv.substring(0, fromEnv.length - 1)
        : fromEnv;
  }

  // Debug/profile → local backend. Release → production.
  if (kDebugMode) {
    return kLocalApiBaseUrl;
  }

  return kProductionApiBaseUrl;
}

/// Server origin for public assets (uploads live outside `/pos_app`).
String get serverOrigin {
  final base = Uri.parse(apiBaseUrl);
  final port = base.hasPort ? ':${base.port}' : '';
  return '${base.scheme}://${base.host}$port';
}

bool get isProductionApi => apiBaseUrl == kProductionApiBaseUrl;
bool get isLocalApi => apiBaseUrl.contains('10.0.2.2') ||
    apiBaseUrl.contains('127.0.0.1') ||
    apiBaseUrl.contains('localhost') ||
    apiBaseUrl.contains(':8000');
