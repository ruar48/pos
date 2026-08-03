import 'dart:async';

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
    this.punchEnabled = true,
    this.punchBusy = false,
    this.onTimeIn,
    this.onTimeOut,
    this.onBreak,
  });

  final AttendanceBoardRow row;
  final bool punchEnabled;
  final bool punchBusy;
  final VoidCallback? onTimeIn;
  final VoidCallback? onTimeOut;
  /// Toggles break state - caller decides break_in vs break_out based on
  /// [AttendanceBoardRow.isOnBreak].
  final VoidCallback? onBreak;

  @override
  Widget build(BuildContext context) {
    final inUrl = resolveAttendancePhotoUrl(attendanceSelfieInUrl(row));
    final outUrl = resolveAttendancePhotoUrl(attendanceSelfieOutUrl(row));
    final inTime = attendanceSelfieInTime(row);
    final outTime = attendanceSelfieOutTime(row);
    final hasIn = attendanceHasSelfieIn(row);
    final hasOut = attendanceHasSelfieOut(row);
    final isClockedIn = attendanceIsClockedIn(row);
    final isDayDone = attendanceIsDayComplete(row);
    final canTimeIn = attendanceCanTimeIn(row, punchEnabled: punchEnabled);
    final canTimeOut = attendanceCanTimeOut(row, punchEnabled: punchEnabled);
    final inDone = isClockedIn || isDayDone;
    final outDone = isDayDone;
    final isOnBreak = attendanceIsOnBreak(row);
    final canBreak = isOnBreak
        ? attendanceCanBreakOut(row, punchEnabled: punchEnabled)
        : attendanceCanBreakIn(row, punchEnabled: punchEnabled);

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
                _DutyHoursText(row: row),
              ],
            ),
          ),
          _ActionCircle(
            label: 'IN',
            caption: 'Time In',
            color: AppColors.green,
            enabled: canTimeIn,
            done: inDone && !canTimeIn,
            busy: punchBusy,
            onTap: canTimeIn && !punchBusy && onTimeIn != null ? onTimeIn : null,
          ),
          const SizedBox(width: 8),
          _ActionCircle(
            label: 'OUT',
            caption: 'Time Out',
            color: AppColors.orange,
            enabled: canTimeOut,
            done: outDone && !canTimeOut,
            busy: punchBusy,
            onTap:
                canTimeOut && !punchBusy && onTimeOut != null ? onTimeOut : null,
          ),
          const SizedBox(width: 8),
          _ActionCircle(
            label: isOnBreak ? 'END' : 'BRK',
            caption: isOnBreak ? 'End Break' : 'Break',
            color: AppColors.amber,
            enabled: canBreak,
            done: isOnBreak,
            busy: punchBusy,
            onTap: canBreak && !punchBusy && onBreak != null ? onBreak : null,
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
                    photoUrl: inUrl,
                    hasRecord: hasIn,
                    emptyIcon: Icons.login_rounded,
                  ),
                ),
                Expanded(
                  child: _SelfieMeta(
                    label: 'Selfie-Out',
                    time: outTime,
                    color: AppColors.orange,
                    photoUrl: outUrl,
                    hasRecord: hasOut,
                    emptyIcon: Icons.logout_rounded,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DutyHoursText extends StatefulWidget {
  const _DutyHoursText({required this.row});

  final AttendanceBoardRow row;

  @override
  State<_DutyHoursText> createState() => _DutyHoursTextState();
}

class _DutyHoursTextState extends State<_DutyHoursText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _DutyHoursText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    _timer?.cancel();
    final timeIn = attendanceTimeIn(widget.row);
    if (timeIn != null && attendanceIsClockedIn(widget.row)) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      attendanceDutyHoursLabel(widget.row),
      style: const TextStyle(
        fontSize: 12,
        color: AppColors.muted,
      ),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({
    required this.label,
    required this.caption,
    required this.color,
    required this.enabled,
    required this.done,
    required this.busy,
    this.onTap,
  });

  final String label;
  final String caption;
  final Color color;
  final bool enabled;
  final bool done;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = enabled
        ? color
        : done
            ? color.withValues(alpha: 0.14)
            : AppColors.softSurface;
    final borderColor = enabled
        ? color
        : done
            ? color.withValues(alpha: 0.45)
            : AppColors.border;
    final textColor = enabled
        ? Colors.white
        : done
            ? color
            : AppColors.muted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 2),
              ),
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: enabled ? Colors.white : color,
                        ),
                      )
                    : Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.1,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: enabled || done ? color : AppColors.muted,
          ),
        ),
      ],
    );
  }
}

class _SelfieMeta extends StatelessWidget {
  const _SelfieMeta({
    required this.label,
    required this.time,
    required this.color,
    required this.hasRecord,
    required this.emptyIcon,
    this.photoUrl,
  });

  final String label;
  final String time;
  final Color color;
  final bool hasRecord;
  final IconData emptyIcon;
  final String? photoUrl;

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
                color: hasRecord ? color : AppColors.border,
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
        const SizedBox(height: 6),
        _SelfieThumb(
          photoUrl: photoUrl,
          hasRecord: hasRecord,
          emptyIcon: emptyIcon,
          accent: color,
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

class _SelfieThumb extends StatelessWidget {
  const _SelfieThumb({
    required this.photoUrl,
    required this.hasRecord,
    required this.emptyIcon,
    required this.accent,
  });

  final String? photoUrl;
  final bool hasRecord;
  final IconData emptyIcon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.softSurface,
        border: Border.all(
          color: hasRecord ? accent.withValues(alpha: 0.45) : AppColors.border,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl != null
          ? Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                emptyIcon,
                color: AppColors.muted,
                size: 22,
              ),
            )
          : Icon(
              emptyIcon,
              color: hasRecord ? accent : AppColors.muted,
              size: 22,
            ),
    );
  }
}
