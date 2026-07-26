import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

const _genericApiError =
    'Something went wrong. Please try again or contact support.';

bool _isTechnicalApiError(String message) {
  final patterns = [
    RegExp(r'SQLSTATE', caseSensitive: false),
    RegExp(r'General error:\s*\d+', caseSensitive: false),
    RegExp(r'Connection:\s*mysql', caseSensitive: false),
    RegExp(r'Host:\s*[\d.]+', caseSensitive: false),
    RegExp(r'Port:\s*\d+', caseSensitive: false),
    RegExp(r'Database:\s*\w+', caseSensitive: false),
    RegExp(r'\bSQL:\s', caseSensitive: false),
    RegExp(r"doesn't have a default value", caseSensitive: false),
    RegExp(r'INSERT INTO', caseSensitive: false),
    RegExp(r'UPDATE\s+`', caseSensitive: false),
    RegExp(r'SELECT\s+', caseSensitive: false),
    RegExp(r'PDOException', caseSensitive: false),
    RegExp(r'QueryException', caseSensitive: false),
    RegExp(r'Duplicate entry', caseSensitive: false),
    RegExp(r'foreign key constraint', caseSensitive: false),
    RegExp(r'\.php on line \d+', caseSensitive: false),
  ];

  return patterns.any((pattern) => pattern.hasMatch(message));
}

String _friendlyApiErrorMessage(String message) {
  if (RegExp(r"doesn't have a default value|1364", caseSensitive: false)
      .hasMatch(message)) {
    return 'We could not complete this action. Please ask your administrator to check the server database setup.';
  }
  if (RegExp(r'Duplicate entry', caseSensitive: false).hasMatch(message)) {
    return 'This record already exists. Please refresh and try again.';
  }
  if (RegExp(r'foreign key constraint', caseSensitive: false)
      .hasMatch(message)) {
    return 'Related data is missing or was removed. Please refresh and try again.';
  }
  if (RegExp(r'SQLSTATE|Connection:\s*mysql|INSERT INTO|UPDATE `',
          caseSensitive: false)
      .hasMatch(message)) {
    return 'We could not save your changes. Please try again or contact support.';
  }
  return _genericApiError;
}

String cleanApiErrorMessage(String raw) {
  var message = raw.trim();
  if (message.startsWith('Exception:')) {
    message = message.substring('Exception:'.length).trim();
  }
  for (final prefix in [
    'Server error: ',
    'Failed to load transaction report: ',
    'Could not save image: ',
  ]) {
    if (message.startsWith(prefix)) {
      message = message.substring(prefix.length).trim();
    }
  }
  message = message
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (_isTechnicalApiError(message)) {
    return _friendlyApiErrorMessage(message);
  }
  if (message.contains('Unable to create temporary file') ||
      message.contains('PHP Request Startup') ||
      message.contains('headers already sent')) {
    return 'Server returned a PHP warning. Stop the server and run: php artisan serve --host=0.0.0.0 --port=8000';
  }
  if (message.contains('Could not write image to:') ||
      message.contains('Could not create an upload directory')) {
    return message;
  }
  if (message.length > 160) {
    message = '${message.substring(0, 160)}...';
  }
  return message.isEmpty ? _genericApiError : message;
}

Map<String, dynamic>? parseApiJsonBody(String raw) {
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    try {
      return jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

String uploadHttpErrorMessage(int statusCode, String rawBody) {
  if (statusCode == 404) {
    return 'Save endpoint not found. Start the API with php artisan serve.';
  }
  final parsed = parseApiJsonBody(rawBody);
  if (parsed != null && parsed['message'] != null) {
    return cleanApiErrorMessage(parsed['message'].toString());
  }
  if (rawBody.contains('unable to create a temporary file')) {
    return 'Could not save product image. Check that the API server is running.';
  }
  return cleanApiErrorMessage(rawBody);
}

OverlayEntry? _activeTopToast;

/// Root navigator key — attach to [MaterialApp.navigatorKey] for app-wide toasts.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

BuildContext? get appToastContext => appNavigatorKey.currentContext;

OverlayState? _resolveOverlay([BuildContext? context]) {
  final navigatorOverlay = appNavigatorKey.currentState?.overlay;
  if (navigatorOverlay != null) {
    return navigatorOverlay;
  }

  if (context != null && context.mounted) {
    try {
      return Overlay.of(context, rootOverlay: true);
    } catch (_) {
      try {
        return Overlay.of(context);
      } catch (_) {}
    }
  }

  return null;
}

MediaQueryData? _resolveMediaQuery([BuildContext? context]) {
  if (context != null && context.mounted) {
    final media = MediaQuery.maybeOf(context);
    if (media != null) return media;
  }

  final rootContext = appToastContext;
  if (rootContext != null && rootContext.mounted) {
    return MediaQuery.maybeOf(rootContext);
  }

  return null;
}

void showTopToast(
  BuildContext context, {
  required Widget content,
  Color backgroundColor = AppColors.green,
  Duration duration = const Duration(seconds: 3),
  double maxWidth = 460,
  VoidCallback? onDismiss,
}) {
  _activeTopToast?.remove();
  _activeTopToast = null;

  final overlay = _resolveOverlay(context);
  if (overlay == null) return;

  final media = _resolveMediaQuery(context);
  if (media == null) return;
  final top = media.padding.top + 16;
  final width = maxWidth.clamp(280, media.size.width - 32).toDouble();

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: top,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Material(
            elevation: 6,
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: content,
            ),
          ),
        ),
      ),
    ),
  );

  _activeTopToast = entry;
  overlay.insert(entry);

  void dismiss() {
    if (entry.mounted) {
      entry.remove();
    }
    if (identical(_activeTopToast, entry)) {
      _activeTopToast = null;
    }
    onDismiss?.call();
  }

  Future.delayed(duration, dismiss);
}

void showTopMessage(
  BuildContext context,
  String message, {
  Color backgroundColor = AppColors.green,
  IconData? icon,
  Duration duration = const Duration(seconds: 3),
}) {
  _showTopMessageImpl(
    message,
    backgroundColor: backgroundColor,
    icon: icon,
    context: context,
    duration: duration,
  );
}

void showTopSuccess(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_outline,
}) {
  showTopMessage(context, message, icon: icon);
}

void showTopError(
  BuildContext context,
  String message, {
  IconData icon = Icons.error_outline,
  Duration duration = const Duration(seconds: 5),
}) {
  showTopMessage(
    context,
    message,
    backgroundColor: AppColors.danger,
    icon: icon,
    duration: duration,
  );
}

void showTopWarning(
  BuildContext context,
  String message, {
  IconData icon = Icons.warning_amber_rounded,
}) {
  showTopMessage(
    context,
    message,
    backgroundColor: AppColors.orange,
    icon: icon,
  );
}

/// App-wide toast — safe after closing dialogs (uses root navigator).
void showAppTopSuccess(String message, {IconData icon = Icons.check_circle_outline}) {
  _showTopMessageImpl(message, icon: icon);
}

void showAppTopError(
  String message, {
  IconData icon = Icons.error_outline,
  Duration duration = const Duration(seconds: 5),
}) {
  _showTopMessageImpl(
    message,
    backgroundColor: AppColors.danger,
    icon: icon,
    duration: duration,
  );
}

void showAppTopWarning(String message, {IconData icon = Icons.warning_amber_rounded}) {
  _showTopMessageImpl(
    message,
    backgroundColor: AppColors.orange,
    icon: icon,
  );
}

void _showTopMessageImpl(
  String message, {
  Color backgroundColor = AppColors.green,
  IconData? icon,
  BuildContext? context,
  Duration duration = const Duration(seconds: 3),
}) {
  final resolvedContext = (context != null && context.mounted)
      ? context
      : appToastContext;
  if (_resolveOverlay(resolvedContext) == null) return;

  final toastContext = resolvedContext ?? appToastContext;
  if (toastContext == null) return;

  showTopToast(
    toastContext,
    backgroundColor: backgroundColor,
    duration: duration,
    content: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: Text(
            cleanApiErrorMessage(message),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}
