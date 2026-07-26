import '../../config/api_config.dart';

String? resolveProductImageUrl(
  String? imageUrl, {
  Object? cacheKey,
}) {
  if (imageUrl == null || imageUrl.trim().isEmpty) return null;

  final trimmed = imageUrl.trim();
  String resolved;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    resolved = trimmed;
  } else {
    final normalized =
        trimmed.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');

    // Serve uploads through pos_app so CORS headers apply (Flutter web).
    // Static /uploads/* on php artisan serve / Apache skips Laravel routes.
    if (normalized.startsWith('uploads/products/')) {
      final filename = normalized.substring('uploads/products/'.length);
      if (filename.isNotEmpty) {
        resolved =
            '$apiBaseUrl/product_image.php?file=${Uri.encodeQueryComponent(filename)}';
      } else {
        resolved = '$serverOrigin/$normalized';
      }
    } else {
      resolved = '$serverOrigin/$normalized';
    }
  }

  if (cacheKey == null) {
    return resolved;
  }

  final separator = resolved.contains('?') ? '&' : '?';
  return '$resolved${separator}v=$cacheKey';
}

bool isExternalImageUrl(String? imageUrl) {
  if (imageUrl == null || imageUrl.trim().isEmpty) return false;
  final trimmed = imageUrl.trim();
  return trimmed.startsWith('http://') || trimmed.startsWith('https://');
}

bool isUploadedImagePath(String? imageUrl) {
  if (imageUrl == null || imageUrl.trim().isEmpty) return false;
  return !isExternalImageUrl(imageUrl);
}
