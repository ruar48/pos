import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/attendance_board.dart';
import '../attendance_formatters.dart';

String? resolveAttendancePhotoUrl(String? imageUrl) {
  if (imageUrl == null || imageUrl.trim().isEmpty) return null;
  final trimmed = imageUrl.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final normalized =
      trimmed.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
  return '$serverOrigin/$normalized';
}

class AttendanceStaffCard extends StatelessWidget {
  const AttendanceStaffCard({
    super.key,
    required this.row,
    this.schedule,
    this.punchEnabled = true,
    this.punchBusy = false,
    this.onPunch,
  });

  final AttendanceBoardRow row;
  final AttendanceSchedule? schedule;
  final bool punchEnabled;
  final bool punchBusy;
  final VoidCallback? onPunch;

  @override
  Widget build(BuildContext context) {
    final nextLabel = attendanceNextActionLabel(row, schedule);
    final buttonLabel = attendancePunchButtonLabel(
      dayComplete: row.dayComplete,
      nextAction: row.nextAction,
      punchCount: row.punchCount,
    );
    final canPunch = punchEnabled &&
        onPunch != null &&
        attendanceCanPunch(
          dayComplete: row.dayComplete,
          nextAction: row.nextAction,
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      '${row.role.replaceAll('_', ' ')} · ${row.branchName}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 18,
                backgroundColor: row.isClockedIn
                    ? AppColors.lightGreen
                    : AppColors.softSurface,
                child: Text(
                  attendanceInitials(row.fullName),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: row.isClockedIn ? AppColors.green : AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final punchCells = [
                _PunchCell(
                  label: 'In AM',
                  time: row.morningInDisplay ??
                      formatAttendanceIsoTime(row.morningInAt ?? row.clockInAt),
                  photoUrl: resolveAttendancePhotoUrl(row.morningInPhotoUrl),
                  active: row.isClockedIn && row.punchCount == 1,
                ),
                _PunchCell(
                  label: 'Out lunch',
                  time: row.lunchOutDisplay ??
                      formatAttendanceIsoTime(row.lunchOutAt),
                  photoUrl: resolveAttendancePhotoUrl(row.lunchOutPhotoUrl),
                  active: row.isClockedIn && row.punchCount == 1,
                ),
                _PunchCell(
                  label: 'In PM',
                  time: row.afternoonInDisplay ??
                      formatAttendanceIsoTime(row.afternoonInAt),
                  photoUrl: resolveAttendancePhotoUrl(row.afternoonInPhotoUrl),
                  active: row.isClockedIn && row.punchCount == 3,
                ),
                _PunchCell(
                  label: 'Out EOD',
                  time: row.dayOutDisplay ??
                      formatAttendanceIsoTime(
                    row.dayOutAt ?? (!row.isClockedIn ? row.clockOutAt : null),
                  ),
                  photoUrl: resolveAttendancePhotoUrl(row.dayOutPhotoUrl),
                ),
              ];

              if (constraints.maxWidth >= 440) {
                return Row(
                  children: [
                    for (final cell in punchCells) Expanded(child: cell),
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: punchCells[0]),
                      Expanded(child: punchCells[1]),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: punchCells[2]),
                      Expanded(child: punchCells[3]),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Badge(
                label: row.totalHoursLabel,
                background: AppColors.softSurface,
                foreground: AppColors.muted,
              ),
              _Badge(
                label: attendanceDayTypeLabel(row.dayType),
                background: row.dayType == 'full'
                    ? AppColors.lightGreen
                    : row.dayType == 'half'
                        ? const Color(0xFFFFF7E6)
                        : AppColors.softSurface,
                foreground: row.dayType == 'full'
                    ? AppColors.green
                    : row.dayType == 'half'
                        ? const Color(0xFFB45309)
                        : AppColors.muted,
              ),
              if (row.clockInAt != null)
                _Badge(
                  label: row.punctualityLabel,
                  background: _punctualityBackground(row.punctualityStatus),
                  foreground: _punctualityForeground(row.punctualityStatus),
                ),
              if (nextLabel != null)
                _Badge(
                  label: nextLabel,
                  background: row.dayComplete
                      ? AppColors.softSurface
                      : AppColors.lightGreen,
                  foreground:
                      row.dayComplete ? AppColors.muted : AppColors.green,
                ),
            ],
          ),
          if (onPunch != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: canPunch && !punchBusy ? onPunch : null,
                style: FilledButton.styleFrom(
                  backgroundColor: canPunch
                      ? (row.nextAction == 'clock_out'
                          ? const Color(0xFF0D9488)
                          : AppColors.green)
                      : AppColors.border,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.softSurface,
                  disabledForegroundColor: AppColors.muted,
                ),
                child: punchBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        buttonLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _punctualityBackground(String? status) {
    switch (status) {
      case 'late':
        return const Color(0xFFFEE2E2);
      case 'morning_absent':
        return const Color(0xFFFFEDD5);
      case 'almost_late':
        return const Color(0xFFFFF7E6);
      case 'on_time':
      case 'early':
        return AppColors.lightGreen;
      default:
        return AppColors.softSurface;
    }
  }

  Color _punctualityForeground(String? status) {
    switch (status) {
      case 'late':
        return const Color(0xFFB91C1C);
      case 'morning_absent':
        return const Color(0xFFC2410C);
      case 'almost_late':
        return const Color(0xFFB45309);
      case 'on_time':
      case 'early':
        return AppColors.green;
      default:
        return AppColors.muted;
    }
  }
}

class _PunchCell extends StatelessWidget {
  const _PunchCell({
    required this.label,
    required this.time,
    this.photoUrl,
    this.active = false,
  });

  final String label;
  final String time;
  final String? photoUrl;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 44,
            height: 44,
            child: photoUrl != null
                ? Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _photoPlaceholder(),
                  )
                : _photoPlaceholder(),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active
                ? AppColors.green
                : time == '—'
                    ? AppColors.muted
                    : AppColors.text,
          ),
        ),
      ],
    );
  }

  Widget _photoPlaceholder() {
    return ColoredBox(
      color: AppColors.softSurface,
      child: Icon(
        Icons.person_outline,
        size: 22,
        color: active ? AppColors.green : AppColors.muted,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
