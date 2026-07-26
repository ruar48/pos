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
    return AttendanceStatus(
      clockInAt: parseServerDateTime(json['clock_in_at']?.toString()),
      clockOutAt: parseServerDateTime(json['clock_out_at']?.toString()),
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
    this.status,
  });

  final String eventType;
  final String branchName;
  final bool withinGeofence;
  final double? distanceKm;
  final bool geofenceSkipped;
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
      status: json['status'] is Map<String, dynamic>
          ? AttendanceStatus.fromJson(json['status'] as Map<String, dynamic>)
          : null,
    );
  }
}
