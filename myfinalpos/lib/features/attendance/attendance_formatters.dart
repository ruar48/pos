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

/// Primary button label: Time In / Time Out only (no break / late windows).
String attendancePunchButtonLabel({
  required bool dayComplete,
  required bool isClockedIn,
}) {
  if (dayComplete) return 'DONE';
  return isClockedIn ? 'OUT' : 'IN';
}

bool attendanceCanPunch({
  required bool dayComplete,
  required bool isClockedIn,
}) {
  if (dayComplete) return false;
  return true;
}

bool attendanceCanPunchRow(AttendanceBoardRow row, {required bool punchEnabled}) {
  if (!punchEnabled) return false;
  return !attendanceIsDayComplete(row);
}

String attendancePunchAction({
  required bool dayComplete,
  required bool isClockedIn,
}) {
  if (dayComplete) return '';
  return isClockedIn ? 'clock_out' : 'clock_in';
}

String attendanceHoursLabel(String label) {
  return label
      .replaceAll(RegExp(r'\bhrs\b'), 'hours')
      .replaceAll(RegExp(r'\bhr\b'), 'hour')
      .replaceAll(RegExp(r'\bmins\b'), 'minutes')
      .replaceAll(RegExp(r'\bmin\b'), 'minute');
}

DateTime? attendanceTimeIn(AttendanceBoardRow row) =>
    row.morningInAt ?? row.clockInAt;

DateTime? attendanceTimeOut(AttendanceBoardRow row) =>
    row.dayOutAt ?? row.clockOutAt;

String formatDutyDuration(int minutes) {
  final safeMinutes = minutes < 0 ? 0 : minutes;
  final hours = safeMinutes ~/ 60;
  final mins = safeMinutes % 60;
  final hourLabel = hours == 1 ? 'hour' : 'hours';
  final minLabel = mins == 1 ? 'minute' : 'minutes';

  if (hours == 0 && mins == 0) return '0 hours 0 minutes';
  if (hours == 0) return '$mins $minLabel';
  if (mins == 0) return '$hours $hourLabel';
  return '$hours $hourLabel $mins $minLabel';
}

String attendanceDutyHoursLabel(AttendanceBoardRow row) {
  final timeIn = attendanceTimeIn(row);
  final timeOut = attendanceTimeOut(row);

  if (timeIn != null && timeOut != null) {
    return formatDutyDuration(timeOut.difference(timeIn).inMinutes);
  }

  if (timeIn != null && attendanceIsClockedIn(row)) {
    return '${formatDutyDuration(DateTime.now().difference(timeIn).inMinutes)} · on duty';
  }

  if (row.totalMinutes > 0) {
    return formatDutyDuration(row.totalMinutes);
  }

  final backendLabel = row.totalHoursLabel.trim();
  if (backendLabel.isNotEmpty && backendLabel != '0 hrs 0 mins') {
    return attendanceHoursLabel(backendLabel);
  }

  return '0 hours 0 minutes';
}

int? attendanceDutyMinutes(AttendanceBoardRow row) {
  final timeIn = attendanceTimeIn(row);
  final timeOut = attendanceTimeOut(row);
  if (timeIn != null && timeOut != null) {
    return timeOut.difference(timeIn).inMinutes;
  }
  if (timeIn != null && attendanceIsClockedIn(row)) {
    return DateTime.now().difference(timeIn).inMinutes;
  }
  if (row.totalMinutes > 0) return row.totalMinutes;
  return null;
}

AttendanceBoardRow attendanceWithDutyTotals(AttendanceBoardRow row) {
  final minutes = attendanceDutyMinutes(row);
  if (minutes == null) return row;
  return row.copyWith(
    totalMinutes: minutes,
    totalHoursLabel: formatDutyDuration(minutes),
  );
}

String? attendanceSelfieInUrl(AttendanceBoardRow row) => row.morningInPhotoUrl;

String attendanceSelfieInTime(AttendanceBoardRow row) {
  final display = row.morningInDisplay;
  if (display != null && display.isNotEmpty) return display;
  return formatAttendanceIsoTime(row.morningInAt ?? row.clockInAt);
}

bool attendanceHasTimedIn(AttendanceBoardRow row) {
  return row.morningInAt != null ||
      row.clockInAt != null ||
      (row.morningInPhotoUrl != null && row.morningInPhotoUrl!.isNotEmpty) ||
      attendanceSelfieInTime(row) != '—' ||
      row.isClockedIn;
}

bool attendanceHasTimedOut(AttendanceBoardRow row) {
  return row.dayOutAt != null ||
      row.clockOutAt != null ||
      (row.dayOutPhotoUrl != null && row.dayOutPhotoUrl!.isNotEmpty) ||
      attendanceSelfieOutTime(row) != '—';
}

bool attendanceIsDayComplete(AttendanceBoardRow row) {
  return row.dayComplete || attendanceHasTimedOut(row);
}

bool attendanceIsClockedIn(AttendanceBoardRow row) {
  if (attendanceIsDayComplete(row)) return false;
  if (row.isClockedIn) return true;
  return attendanceHasTimedIn(row);
}

bool attendanceCanTimeIn(AttendanceBoardRow row, {required bool punchEnabled}) {
  if (!punchEnabled) return false;
  if (attendanceIsDayComplete(row)) return false;
  return !attendanceIsClockedIn(row);
}

bool attendanceCanTimeOut(AttendanceBoardRow row, {required bool punchEnabled}) {
  if (!punchEnabled) return false;
  if (attendanceIsDayComplete(row)) return false;
  return attendanceIsClockedIn(row);
}

AttendanceBoardRow attendanceNormalizeRow(AttendanceBoardRow row) {
  final dayComplete = attendanceIsDayComplete(row);
  final isClockedIn = attendanceIsClockedIn(row);
  return attendanceWithDutyTotals(
    row.copyWith(
      dayComplete: dayComplete,
      isClockedIn: isClockedIn,
      nextAction: dayComplete ? null : (isClockedIn ? 'clock_out' : 'clock_in'),
    ),
  );
}

bool attendanceHasSelfieIn(AttendanceBoardRow row) {
  return attendanceSelfieInTime(row) != '—' ||
      attendanceSelfieInUrl(row) != null ||
      attendanceHasTimedIn(row);
}

String? attendanceSelfieOutUrl(AttendanceBoardRow row) => row.dayOutPhotoUrl;

String attendanceSelfieOutTime(AttendanceBoardRow row) {
  final display = row.dayOutDisplay;
  if (display != null && display.isNotEmpty) return display;
  return formatAttendanceIsoTime(row.dayOutAt ?? row.clockOutAt);
}

bool attendanceHasSelfieOut(AttendanceBoardRow row) {
  return attendanceSelfieOutTime(row) != '—' ||
      attendanceSelfieOutUrl(row) != null;
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
