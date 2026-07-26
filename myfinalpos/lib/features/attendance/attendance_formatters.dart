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

/// Primary button label for manual Time In / Out (no face recognition).
String attendancePunchButtonLabel({
  required bool dayComplete,
  required String? nextAction,
  int punchCount = 0,
}) {
  if (dayComplete) return 'DONE';
  if (nextAction == 'clock_in') return 'TIME IN';
  if (nextAction == 'clock_out') {
    if (punchCount == 1) return 'START BREAK';
    if (punchCount == 3) return 'OUT';
    return 'TIME OUT';
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
