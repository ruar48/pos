import 'package:shared_preferences/shared_preferences.dart';

/// Persists attendance selfie URLs and punch times on-device so rows survive
/// app restarts when the board reloads from the server.
class AttendancePhotoCache {
  static String _photoKey(String date, int userId, String type) =>
      'attendance_photo_${date}_${userId}_$type';

  static String _timeKey(String date, int userId, String type) =>
      'attendance_time_${date}_${userId}_$type';

  static Future<void> save({
    required String date,
    required int userId,
    required String type,
    required String photoUrl,
  }) async {
    if (photoUrl.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_photoKey(date, userId, type), photoUrl.trim());
  }

  static Future<String?> load({
    required String date,
    required int userId,
    required String type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_photoKey(date, userId, type));
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  static Future<void> saveTime({
    required String date,
    required int userId,
    required String type,
    required DateTime at,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_timeKey(date, userId, type), at.toUtc().toIso8601String());
  }

  static Future<DateTime?> loadTime({
    required String date,
    required int userId,
    required String type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_timeKey(date, userId, type));
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim())?.toLocal();
  }

  static String _durationKey(String date, int userId) =>
      'attendance_duration_${date}_$userId';

  static Future<void> saveDuration({
    required String date,
    required int userId,
    required int minutes,
  }) async {
    if (minutes <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_durationKey(date, userId), minutes);
  }

  static Future<int?> loadDuration({
    required String date,
    required int userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_durationKey(date, userId));
    if (value == null || value <= 0) return null;
    return value;
  }

  static Future<void> clearDay(String date) async {
    final prefs = await SharedPreferences.getInstance();
    final photoPrefix = 'attendance_photo_${date}_';
    final timePrefix = 'attendance_time_${date}_';
    final durationPrefix = 'attendance_duration_${date}_';
    final keys = prefs
        .getKeys()
        .where(
          (key) =>
              key.startsWith(photoPrefix) ||
              key.startsWith(timePrefix) ||
              key.startsWith(durationPrefix),
        )
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
