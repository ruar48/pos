import '../core/utils/format_utils.dart';

class AttendanceSchedule {
  const AttendanceSchedule({
    required this.startTime,
    required this.graceMinutes,
    required this.lateAfterTime,
    required this.lunchOutTime,
    required this.afternoonInTime,
    required this.dayEndTime,
    required this.morningAbsentAfterTime,
  });

  final String startTime;
  final int graceMinutes;
  final String lateAfterTime;
  final String lunchOutTime;
  final String afternoonInTime;
  final String dayEndTime;
  final String morningAbsentAfterTime;

  factory AttendanceSchedule.fromJson(Map<String, dynamic> json) {
    return AttendanceSchedule(
      startTime: (json['start_time'] ?? '08:00').toString(),
      graceMinutes: toInt(json['grace_minutes']).clamp(0, 120),
      lateAfterTime: (json['late_after_time'] ?? '08:15').toString(),
      lunchOutTime: (json['lunch_out_time'] ?? '12:00').toString(),
      afternoonInTime: (json['afternoon_in_time'] ?? '13:00').toString(),
      dayEndTime: (json['day_end_time'] ?? '17:00').toString(),
      morningAbsentAfterTime:
          (json['morning_absent_after_time'] ?? '09:00').toString(),
    );
  }
}

class AttendanceBoardRow {
  const AttendanceBoardRow({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.branchName,
    this.branchId,
    this.clockInAt,
    this.clockOutAt,
    this.morningInAt,
    this.lunchOutAt,
    this.afternoonInAt,
    this.dayOutAt,
    this.morningInDisplay,
    this.lunchOutDisplay,
    this.afternoonInDisplay,
    this.dayOutDisplay,
    this.morningInPhotoUrl,
    this.lunchOutPhotoUrl,
    this.afternoonInPhotoUrl,
    this.dayOutPhotoUrl,
    this.punchCount = 0,
    this.nextAction,
    this.nextActionNote,
    this.dayComplete = false,
    this.dayType = 'none',
    this.totalMinutes = 0,
    this.totalHoursLabel = '0 hrs 0 mins',
    this.isClockedIn = false,
    this.punctualityStatus,
    this.isMorningAbsent = false,
  });

  final int userId;
  final String fullName;
  final String role;
  final String branchName;
  final int? branchId;
  final DateTime? clockInAt;
  final DateTime? clockOutAt;
  final DateTime? morningInAt;
  final DateTime? lunchOutAt;
  final DateTime? afternoonInAt;
  final DateTime? dayOutAt;
  final String? morningInDisplay;
  final String? lunchOutDisplay;
  final String? afternoonInDisplay;
  final String? dayOutDisplay;
  final String? morningInPhotoUrl;
  final String? lunchOutPhotoUrl;
  final String? afternoonInPhotoUrl;
  final String? dayOutPhotoUrl;
  final int punchCount;
  final String? nextAction;
  final String? nextActionNote;
  final bool dayComplete;
  final String dayType;
  final int totalMinutes;
  final String totalHoursLabel;
  final bool isClockedIn;
  final String? punctualityStatus;
  final bool isMorningAbsent;

  String get punctualityLabel {
    switch (punctualityStatus) {
      case 'early':
        return 'Early';
      case 'on_time':
        return 'On time';
      case 'almost_late':
        return 'Almost late';
      case 'late':
        return 'Late';
      case 'morning_absent':
        return 'Morning absent';
      case 'absent':
        return 'Absent';
      default:
        return 'Not in yet';
    }
  }

  AttendanceBoardRow copyWith({
    int? userId,
    String? fullName,
    String? role,
    String? branchName,
    int? branchId,
    DateTime? clockInAt,
    DateTime? clockOutAt,
    DateTime? morningInAt,
    DateTime? lunchOutAt,
    DateTime? afternoonInAt,
    DateTime? dayOutAt,
    String? morningInDisplay,
    String? lunchOutDisplay,
    String? afternoonInDisplay,
    String? dayOutDisplay,
    String? morningInPhotoUrl,
    String? lunchOutPhotoUrl,
    String? afternoonInPhotoUrl,
    String? dayOutPhotoUrl,
    int? punchCount,
    String? nextAction,
    String? nextActionNote,
    bool? dayComplete,
    String? dayType,
    int? totalMinutes,
    String? totalHoursLabel,
    bool? isClockedIn,
    String? punctualityStatus,
    bool? isMorningAbsent,
  }) {
    return AttendanceBoardRow(
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      branchName: branchName ?? this.branchName,
      branchId: branchId ?? this.branchId,
      clockInAt: clockInAt ?? this.clockInAt,
      clockOutAt: clockOutAt ?? this.clockOutAt,
      morningInAt: morningInAt ?? this.morningInAt,
      lunchOutAt: lunchOutAt ?? this.lunchOutAt,
      afternoonInAt: afternoonInAt ?? this.afternoonInAt,
      dayOutAt: dayOutAt ?? this.dayOutAt,
      morningInDisplay: morningInDisplay ?? this.morningInDisplay,
      lunchOutDisplay: lunchOutDisplay ?? this.lunchOutDisplay,
      afternoonInDisplay: afternoonInDisplay ?? this.afternoonInDisplay,
      dayOutDisplay: dayOutDisplay ?? this.dayOutDisplay,
      morningInPhotoUrl: morningInPhotoUrl ?? this.morningInPhotoUrl,
      lunchOutPhotoUrl: lunchOutPhotoUrl ?? this.lunchOutPhotoUrl,
      afternoonInPhotoUrl: afternoonInPhotoUrl ?? this.afternoonInPhotoUrl,
      dayOutPhotoUrl: dayOutPhotoUrl ?? this.dayOutPhotoUrl,
      punchCount: punchCount ?? this.punchCount,
      nextAction: nextAction ?? this.nextAction,
      nextActionNote: nextActionNote ?? this.nextActionNote,
      dayComplete: dayComplete ?? this.dayComplete,
      dayType: dayType ?? this.dayType,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      totalHoursLabel: totalHoursLabel ?? this.totalHoursLabel,
      isClockedIn: isClockedIn ?? this.isClockedIn,
      punctualityStatus: punctualityStatus ?? this.punctualityStatus,
      isMorningAbsent: isMorningAbsent ?? this.isMorningAbsent,
    );
  }

  factory AttendanceBoardRow.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? value) => parseServerDateTime(value);

    return AttendanceBoardRow(
      userId: toInt(json['user_id']),
      fullName: (json['full_name'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      branchName: (json['branch_name'] ?? 'Unassigned').toString(),
      branchId: json['branch_id'] == null ? null : toInt(json['branch_id']),
      clockInAt: parse(json['clock_in_at']?.toString()),
      clockOutAt: parse(json['clock_out_at']?.toString()),
      morningInAt: parse(json['morning_in_at']?.toString()),
      lunchOutAt: parse(json['lunch_out_at']?.toString()),
      afternoonInAt: parse(json['afternoon_in_at']?.toString()),
      dayOutAt: parse(json['day_out_at']?.toString()),
      morningInDisplay: json['morning_in_display']?.toString(),
      lunchOutDisplay: json['lunch_out_display']?.toString(),
      afternoonInDisplay: json['afternoon_in_display']?.toString(),
      dayOutDisplay: json['day_out_display']?.toString(),
      morningInPhotoUrl: json['morning_in_photo_url']?.toString(),
      lunchOutPhotoUrl: json['lunch_out_photo_url']?.toString(),
      afternoonInPhotoUrl: json['afternoon_in_photo_url']?.toString(),
      dayOutPhotoUrl: json['day_out_photo_url']?.toString(),
      punchCount: toInt(json['punch_count']),
      nextAction: json['next_action']?.toString(),
      nextActionNote: json['next_action_note']?.toString(),
      dayComplete: json['day_complete'] == true ||
          json['day_complete'].toString() == '1' ||
          json['day_complete'].toString() == 'true',
      dayType: (json['day_type'] ?? 'none').toString(),
      totalMinutes: toInt(json['total_minutes']),
      totalHoursLabel: (json['total_hours_label'] ?? '0 hrs 0 mins').toString(),
      isClockedIn: json['is_clocked_in'] == true ||
          json['is_clocked_in'].toString() == '1' ||
          json['is_clocked_in'].toString() == 'true',
      punctualityStatus: json['punctuality_status']?.toString(),
      isMorningAbsent: json['is_morning_absent'] == true ||
          json['is_morning_absent'].toString() == '1' ||
          json['is_morning_absent'].toString() == 'true',
    );
  }
}

class AttendanceBoardResult {
  const AttendanceBoardResult({
    required this.date,
    required this.schedule,
    required this.rows,
  });

  final String date;
  final AttendanceSchedule schedule;
  final List<AttendanceBoardRow> rows;

  factory AttendanceBoardResult.fromJson(Map<String, dynamic> json) {
    final rows = (json['rows'] as List<dynamic>? ?? [])
        .map((row) => AttendanceBoardRow.fromJson(row as Map<String, dynamic>))
        .toList();

    return AttendanceBoardResult(
      date: (json['date'] ?? '').toString(),
      schedule: AttendanceSchedule.fromJson(
        json['schedule'] as Map<String, dynamic>? ?? {},
      ),
      rows: rows,
    );
  }
}
