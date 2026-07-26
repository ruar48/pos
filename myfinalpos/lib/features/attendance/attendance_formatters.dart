import '../../models/attendance_board.dart';

String formatAttendanceClockTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return value;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts[1];
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final display = hour % 12 == 0 ? 12 : hour % 12;
  return '$display:$minute $suffix';
}

String formatAttendanceIsoTime(DateTime? value) {
  if (value == null) return '—';
  final hour = value.hour > 12 ? value.hour - 12 : (value.hour == 0 ? 12 : value.hour);
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute $suffix';
}

String attendanceInitials(String name) {
  return name
      .split(' ')
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}

String attendanceDayTypeLabel(String dayType) {
  switch (dayType) {
    case 'full':
      return 'Full day';
    case 'half':
      return 'Half day';
    case 'in_progress':
      return 'In progress';
    default:
      return 'Not started';
  }
}

String? attendanceNextActionLabel(
  AttendanceBoardRow row,
  AttendanceSchedule? schedule,
) {
  if (row.dayComplete) return 'Done for today';
  if (row.nextActionNote != null && row.nextActionNote!.isNotEmpty) {
    return row.nextActionNote;
  }
  if (row.nextAction == null &&
      row.punchCount == 0 &&
      (row.punctualityStatus == 'morning_absent' || row.isMorningAbsent)) {
    return schedule == null
        ? 'Morning absent'
        : 'Morning absent · PM ${formatAttendanceClockTime(schedule.afternoonInTime)}';
  }
  if (row.nextAction == 'clock_in') {
    if (row.punchCount == 0) return 'Next: morning in';
    if (row.punchCount == 2) return 'Next: afternoon in';
    return 'Next: clock in';
  }
  if (row.nextAction == 'clock_out') {
    if (row.punchCount == 1) return 'Next: lunch out';
    if (row.punchCount == 3) return 'Next: end of day out';
    return 'Next: clock out';
  }
  return null;
}

/// Primary button label for manual Time In / Out (matches past tablet UI).
String attendancePunchButtonLabel({
  required bool dayComplete,
  required String? nextAction,
  int punchCount = 0,
}) {
  if (dayComplete) return 'DONE';
  if (nextAction == 'clock_in') return 'IN';
  if (nextAction == 'clock_out') {
    if (punchCount == 1) return 'START BREAK';
    return 'OUT';
  }
  return 'WAIT';
}

bool attendanceCanPunch({
  required bool dayComplete,
  required String? nextAction,
}) {
  if (dayComplete) return false;
  return nextAction == 'clock_in' || nextAction == 'clock_out';
}

String attendanceHoursLabel(String label) {
  return label
      .replaceAll('hrs', 'hour')
      .replaceAll('hr', 'hour')
      .replaceAll('mins', 'minute')
      .replaceAll('min', 'minute');
}

/// Latest “in” selfie for the past-system two-column display.
String? attendanceSelfieInUrl(AttendanceBoardRow row) {
  if (row.afternoonInPhotoUrl != null && row.afternoonInPhotoUrl!.isNotEmpty) {
    return row.afternoonInPhotoUrl;
  }
  return row.morningInPhotoUrl;
}

String attendanceSelfieInTime(AttendanceBoardRow row) {
  if (row.afternoonInAt != null) {
    return row.afternoonInDisplay ?? formatAttendanceIsoTime(row.afternoonInAt);
  }
  return row.morningInDisplay ??
      formatAttendanceIsoTime(row.morningInAt ?? row.clockInAt);
}

/// Latest “out” selfie for the past-system two-column display.
String? attendanceSelfieOutUrl(AttendanceBoardRow row) {
  if (row.dayOutPhotoUrl != null && row.dayOutPhotoUrl!.isNotEmpty) {
    return row.dayOutPhotoUrl;
  }
  return row.lunchOutPhotoUrl;
}

String attendanceSelfieOutTime(AttendanceBoardRow row) {
  if (row.dayOutAt != null) {
    return row.dayOutDisplay ?? formatAttendanceIsoTime(row.dayOutAt);
  }
  return row.lunchOutDisplay ?? formatAttendanceIsoTime(row.lunchOutAt);
}

List<DateTime> attendanceRecentDates({int days = 7}) {
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  return List.generate(days, (i) => start.subtract(Duration(days: i)));
}

String attendanceDateRailLabel(DateTime date) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final weekday = weekdays[date.weekday - 1];
  return '$weekday, ${date.day} ${months[date.month - 1]}';
}

String attendanceScheduleSummary(AttendanceSchedule schedule) {
  return 'Full day: in ${formatAttendanceClockTime(schedule.startTime)} · out '
      '${formatAttendanceClockTime(schedule.lunchOutTime)} · in '
      '${formatAttendanceClockTime(schedule.afternoonInTime)} · out '
      '${formatAttendanceClockTime(schedule.dayEndTime)}. Absent after '
      '${formatAttendanceClockTime(schedule.morningAbsentAfterTime)}.';
}

String toIsoDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

bool isTodayIso(String date) => date == toIsoDate(DateTime.now());
