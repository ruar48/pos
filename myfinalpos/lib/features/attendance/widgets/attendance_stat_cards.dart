import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/attendance_board.dart';
import '../attendance_formatters.dart';

class AttendanceStatCards extends StatelessWidget {
  const AttendanceStatCards({
    super.key,
    required this.rows,
    required this.schedule,
    this.compact = false,
  });

  final List<AttendanceBoardRow> rows;
  final AttendanceSchedule? schedule;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final onDuty = rows.where((row) => row.isClockedIn).length;
    final late = rows.where((row) => row.punctualityStatus == 'late').length;
    final morningAbsent = rows
        .where(
          (row) =>
              row.punctualityStatus == 'morning_absent' || row.isMorningAbsent,
        )
        .length;
    final almostLate =
        rows.where((row) => row.punctualityStatus == 'almost_late').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompact = compact || constraints.maxWidth < 1200;
        final crossCount = constraints.maxWidth >= 1100
            ? 5
            : constraints.maxWidth >= 820
                ? 5
                : constraints.maxWidth >= 560
                    ? 3
                    : constraints.maxWidth >= 380
                        ? 2
                        : 1;

        final aspectRatio = crossCount >= 5
            ? (useCompact ? 3.4 : 2.8)
            : useCompact
                ? 3.0
                : crossCount == 1
                    ? 3.2
                    : 2.2;

        final cards = [
          _StatCard(label: 'ON DUTY NOW', value: '$onDuty', compact: useCompact),
          _StatCard(label: 'LATE TODAY', value: '$late', compact: useCompact),
          _StatCard(
            label: 'MORNING ABSENT',
            value: '$morningAbsent',
            compact: useCompact,
          ),
          _StatCard(label: 'ALMOST LATE', value: '$almostLate', compact: useCompact),
          _StatCard(
            label: 'START + GRACE',
            value: schedule == null
                ? '—'
                : '${formatAttendanceClockTime(schedule!.startTime)} · ${schedule!.graceMinutes}m',
            subtitle: schedule == null
                ? null
                : 'Absent after ${formatAttendanceClockTime(schedule!.morningAbsentAfterTime)}',
            compact: useCompact,
          ),
        ];

        return GridView.count(
          crossAxisCount: crossCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: useCompact ? 8 : 10,
          crossAxisSpacing: useCompact ? 8 : 10,
          childAspectRatio: aspectRatio,
          children: cards,
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.subtitle,
    this.compact = false,
  });

  final String label;
  final String value;
  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 8 : 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.muted,
            ),
          ),
          SizedBox(height: compact ? 2 : 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: subtitle == null
                  ? (compact ? 16 : 20)
                  : (compact ? 13 : 15),
              fontWeight: FontWeight.w800,
              color: AppColors.text,
              height: 1.1,
            ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: compact ? 1 : 2),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 9 : 10,
                color: AppColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
