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
    final inUrl = resolveAttendancePhotoUrl(attendanceSelfieInUrl(row));
    final outUrl = resolveAttendancePhotoUrl(attendanceSelfieOutUrl(row));
    final inTime = attendanceSelfieInTime(row);
    final outTime = attendanceSelfieOutTime(row);
    final actionColor = _actionColor(buttonLabel);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.fullName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.2,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  attendanceHoursLabel(row.totalHoursLabel),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          _PhotoCircle(url: inUrl, emptyIcon: Icons.login_rounded),
          const SizedBox(width: 8),
          _PhotoCircle(url: outUrl, emptyIcon: Icons.logout_rounded),
          const SizedBox(width: 12),
          _ActionCircle(
            label: buttonLabel,
            color: actionColor,
            enabled: canPunch,
            busy: punchBusy,
            onTap: canPunch && !punchBusy ? onPunch : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: _SelfieMeta(
                    label: 'Selfie-In',
                    time: inTime,
                    color: const Color(0xFF0D9488),
                  ),
                ),
                Expanded(
                  child: _SelfieMeta(
                    label: 'Selfie-Out',
                    time: outTime,
                    color: AppColors.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _actionColor(String label) {
    switch (label) {
      case 'OUT':
        return AppColors.orange;
      case 'START BREAK':
        return const Color(0xFF38BDF8);
      case 'DONE':
      case 'WAIT':
        return AppColors.border;
      default:
        return AppColors.green;
    }
  }
}

class _PhotoCircle extends StatelessWidget {
  const _PhotoCircle({required this.url, required this.emptyIcon});

  final String? url;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.softSurface,
        border: Border.all(color: AppColors.border, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                emptyIcon,
                color: AppColors.muted,
                size: 22,
              ),
            )
          : Icon(emptyIcon, color: AppColors.muted, size: 22),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({
    required this.label,
    required this.color,
    required this.enabled,
    required this.busy,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool enabled;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isBreak = label == 'START BREAK';
    return Material(
      color: enabled ? color : AppColors.softSurface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: isBreak ? 88 : 72,
          height: isBreak ? 88 : 72,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: enabled ? Colors.white : AppColors.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: isBreak ? 11 : 14,
                        height: 1.1,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SelfieMeta extends StatelessWidget {
  const _SelfieMeta({
    required this.label,
    required this.time,
    required this.color,
  });

  final String label;
  final String time;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hasTime = time != '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: hasTime ? color : AppColors.border,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          hasTime ? 'Today' : '—',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: hasTime ? AppColors.text : AppColors.muted,
          ),
        ),
        if (hasTime)
          Text(
            time,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
      ],
    );
  }
}
