import 'dart:convert';
import 'dart:html' as html;

void sendMonitorDisconnectBeacon(String url, Map<String, dynamic> payload) {
  final body = jsonEncode({
    'action': 'disconnect',
    ...payload,
  });
  html.window.navigator.sendBeacon(
    url,
    html.Blob([body], 'application/json'),
  );
}
