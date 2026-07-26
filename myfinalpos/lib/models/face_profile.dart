class FaceStaffDirectoryEntry {
  const FaceStaffDirectoryEntry({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.enrolled,
    required this.confidence,
  });

  final int userId;
  final String fullName;
  final String role;
  final bool enrolled;
  final int confidence;

  factory FaceStaffDirectoryEntry.fromJson(Map<String, dynamic> json) {
    return FaceStaffDirectoryEntry(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      fullName: (json['full_name'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      enrolled: json['enrolled'] == true || json['enrolled'].toString() == '1',
      confidence: (json['confidence'] as num?)?.toInt() ?? 0,
    );
  }
}

class FaceEnrollmentStatus {
  const FaceEnrollmentStatus({
    required this.userId,
    required this.enrolled,
    required this.confidence,
    this.enrolledAt,
  });

  final int userId;
  final bool enrolled;
  final int confidence;
  final String? enrolledAt;

  factory FaceEnrollmentStatus.fromJson(Map<String, dynamic> json) {
    return FaceEnrollmentStatus(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      enrolled: json['enrolled'] == true || json['enrolled'].toString() == '1',
      confidence: (json['confidence'] as num?)?.toInt() ?? 0,
      enrolledAt: json['enrolled_at']?.toString(),
    );
  }
}

class FaceVerifyResult {
  const FaceVerifyResult({
    required this.matched,
    this.userId,
    this.fullName,
    this.role,
    this.distance,
    this.confidence,
    this.message,
  });

  final bool matched;
  final int? userId;
  final String? fullName;
  final String? role;
  final double? distance;
  final int? confidence;
  final String? message;

  factory FaceVerifyResult.fromJson(Map<String, dynamic> json) {
    return FaceVerifyResult(
      matched: json['matched'] == true || json['matched'].toString() == '1',
      userId: (json['user_id'] as num?)?.toInt(),
      fullName: json['full_name']?.toString(),
      role: json['role']?.toString(),
      distance: (json['distance'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toInt(),
      message: json['message']?.toString(),
    );
  }
}
