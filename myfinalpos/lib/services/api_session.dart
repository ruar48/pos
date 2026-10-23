import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// The tablet's sign-in token for the POS API.
///
/// The server used to take "who is calling" from a user id inside each
/// request, so anyone could act as any user. It now issues a token at login;
/// [apiHttp] sends it on every API request and the server trusts only the
/// token's user.
class ApiSession {
  ApiSession._();

  static const _tokenKey = 'pos_api_token';

  static String? _token;
  static bool _expiredHandled = false;

  /// Called once when the server says the session is no longer valid
  /// (signed out elsewhere, user deactivated, password reset). The app
  /// clears the saved user and returns to the login screen.
  static Future<void> Function()? onSessionExpired;

  static String? get token => _token;

  static bool get hasToken => _token != null && _token!.isNotEmpty;

  /// Restores the token saved by a previous "remember me" sign-in.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
    } catch (_) {
      _token = null;
    }
  }

  /// Keeps [token] for this session; [persist] also saves it for the next
  /// app start (only when the user chose "remember me").
  static Future<void> save(String? token, {required bool persist}) async {
    _token = (token == null || token.isEmpty) ? null : token;
    _expiredHandled = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (persist && _token != null) {
        await prefs.setString(_tokenKey, _token!);
      } else {
        await prefs.remove(_tokenKey);
      }
    } catch (_) {}
  }

  /// Signs out on the server (best effort) and forgets the token.
  static Future<void> signOut() async {
    final current = _token;
    await clear();
    if (current == null) return;
    try {
      await http
          .post(
            Uri.parse('$apiBaseUrl/logout.php'),
            headers: {'Authorization': 'Bearer $current'},
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline: the token simply expires on the server after idle days.
    }
  }

  static Future<void> clear() async {
    _token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } catch (_) {}
  }

  static Future<void> _handleExpired() async {
    if (_expiredHandled) return;
    _expiredHandled = true;
    await clear();
    final callback = onSessionExpired;
    if (callback != null) await callback();
  }
}

bool _isApiRequest(Uri url) {
  final api = Uri.parse(apiBaseUrl);
  return url.host == api.host &&
      url.port == api.port &&
      url.path.startsWith(api.path);
}

/// HTTP client for the POS API: adds the sign-in token and notices when the
/// server rejects it.
class PosHttpClient extends http.BaseClient {
  PosHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = ApiSession.token;
    final isApi = _isApiRequest(request.url);
    if (isApi && token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final response = await _inner.send(request);
    if (!isApi || response.statusCode != 401) return response;

    // Only a 401 that is about the token ends the session - wrong passwords
    // or PINs also answer 401.
    final bytes = await response.stream.toBytes();
    final body = utf8.decode(bytes, allowMalformed: true);
    if (body.contains('"token_invalid"') || body.contains('"token_required"')) {
      unawaited(ApiSession._handleExpired());
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

/// Use instead of `http.get`/`http.post` for every POS API call.
final PosHttpClient apiHttp = PosHttpClient();
