import '../core/utils/format_utils.dart';

class AttendanceStatus {
  const AttendanceStatus({
    this.clockInAt,
    this.clockOutAt,
    this.totalMinutes = 0,
    this.totalHoursLabel = '0 hrs 0 mins',
    this.isClockedIn = false,
    this.withinGeofence,
    this.distanceKm,
    this.punctualityStatus,
    this.isLate = false,
    this.minutesLate = 0,
    this.expectedStartTime,
    this.lateAfterTime,
    this.nextAction,
    this.nextActionNote,
    this.dayComplete = false,
    this.isOnBreak = false,
    this.breakStartAt,
    this.breakEndAt,
    this.totalBreakMinutes = 0,
  });

  final DateTime? clockInAt;
  final DateTime? clockOutAt;
  final int totalMinutes;
  final String totalHoursLabel;
  final bool isClockedIn;
  final bool? withinGeofence;
  final double? distanceKm;
  final String? punctualityStatus;
  final bool isLate;
  final int minutesLate;
  final String? expectedStartTime;
  final String? lateAfterTime;
  final String? nextAction;
  final String? nextActionNote;
  final bool dayComplete;
  final bool isOnBreak;
  final DateTime? breakStartAt;
  final DateTime? breakEndAt;
  final int totalBreakMinutes;

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
      case 'absent':
        return 'Absent';
      case 'morning_absent':
        return 'Morning absent';
      default:
        return 'Not in yet';
    }
  }

  factory AttendanceStatus.fromJson(Map<String, dynamic> json) {
    final morningIn = parseServerDateTime(json['morning_in_at']?.toString());
    final dayOut = parseServerDateTime(json['day_out_at']?.toString());
    final clockIn = parseServerDateTime(json['clock_in_at']?.toString()) ?? morningIn;
    final clockOut = parseServerDateTime(json['clock_out_at']?.toString()) ?? dayOut;

    return AttendanceStatus(
      clockInAt: clockIn,
      clockOutAt: clockOut,
      totalMinutes: toInt(json['total_minutes']),
      totalHoursLabel: (json['total_hours_label'] ?? '0 hrs 0 mins').toString(),
      isClockedIn: json['is_clocked_in'] == true ||
          json['is_clocked_in'].toString() == '1' ||
          json['is_clocked_in'].toString() == 'true',
      withinGeofence: json['within_geofence'] == null
          ? null
          : json['within_geofence'] == true ||
              json['within_geofence'].toString() == '1',
      distanceKm: json['distance_km'] == null
          ? null
          : toDouble(json['distance_km']),
      punctualityStatus: json['punctuality_status']?.toString(),
      isLate: json['is_late'] == true || json['is_late'].toString() == '1',
      minutesLate: toInt(json['minutes_late']),
      expectedStartTime: json['expected_start_time']?.toString(),
      lateAfterTime: json['late_after_time']?.toString(),
      nextAction: json['next_action']?.toString(),
      nextActionNote: json['next_action_note']?.toString(),
      dayComplete: json['day_complete'] == true ||
          json['day_complete'].toString() == '1' ||
          json['day_complete'].toString() == 'true',
      isOnBreak: json['is_on_break'] == true ||
          json['is_on_break'].toString() == '1' ||
          json['is_on_break'].toString() == 'true',
      breakStartAt: parseServerDateTime(json['break_start_at']?.toString()),
      breakEndAt: parseServerDateTime(json['break_end_at']?.toString()),
      totalBreakMinutes: toInt(json['total_break_minutes']),
    );
  }
}

class AttendanceClockResult {
  const AttendanceClockResult({
    required this.eventType,
    required this.branchName,
    required this.withinGeofence,
    this.distanceKm,
    this.geofenceSkipped = false,
    this.photoUrl,
    this.status,
  });

  final String eventType;
  final String branchName;
  final bool withinGeofence;
  final double? distanceKm;
  final bool geofenceSkipped;
  final String? photoUrl;
  final AttendanceStatus? status;

  factory AttendanceClockResult.fromJson(Map<String, dynamic> json) {
    return AttendanceClockResult(
      eventType: (json['event_type'] ?? '').toString(),
      branchName: (json['branch_name'] ?? '').toString(),
      withinGeofence: json['within_geofence'] == true ||
          json['within_geofence'].toString() == '1',
      distanceKm:
          json['distance_km'] == null ? null : toDouble(json['distance_km']),
      geofenceSkipped: json['geofence_skipped'] == true,
      photoUrl: json['photo_url']?.toString(),
      status: json['status'] is Map<String, dynamic>
          ? AttendanceStatus.fromJson(json['status'] as Map<String, dynamic>)
          : null,
    );
  }
}
