import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/top_toast.dart';
import '../../models/attendance_board.dart';
import '../../models/attendance_status.dart';
import '../../services/pos_api.dart';
import '../management/widgets/management_widgets.dart';
import '../management/widgets/super_admin_widgets.dart';
import '../pos/pages/pos_home_page.dart';
import '../pos/widgets/app_drawer_section.dart';
import 'attendance_formatters.dart';
import 'widgets/attendance_staff_card.dart';
import 'widgets/attendance_selfie_sheet.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final _api = const PosApi();
  final _searchController = TextEditingController();

  AttendanceStatus? _status;
  AttendanceSchedule? _schedule;
  List<AttendanceBoardRow> _boardRows = [];
  String _boardDate = toIsoDate(DateTime.now());
  bool _loading = true;
  bool _submitting = false;
  int? _punchingUserId;
  String? _error;
  String? _lastPunchSummary;
  String _searchQuery = '';

  int get _userId => widget.pageState.widget.currentUser.id;
  int get _branchId => widget.pageState.activeBranchId;
  bool get _canManageBoard =>
      widget.pageState.widget.currentUser.canManageOperations;
  bool get _canAddEmployee =>
      widget.pageState.widget.currentUser.canManageOperations;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_canManageBoard) {
        final board = await _api.fetchAttendanceBoard(
          actorUserId: _userId,
          date: _boardDate,
          branchId: _branchId,
        );
        if (!mounted) return;
        setState(() {
          _boardRows = board.rows;
          _schedule = board.schedule;
          _loading = false;
        });
        return;
      }

      final status = await _api.fetchAttendanceStatus(userId: _userId);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _selectBoardDate(DateTime date) async {
    final iso = toIsoDate(date);
    if (iso == _boardDate) return;
    setState(() => _boardDate = iso);
    await _load();
  }

  Future<void> _pickBoardDate() async {
    final initial = DateTime.tryParse(_boardDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      lastDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    await _selectBoardDate(picked);
  }

  Future<void> _addEmployee() async {
    await showStaffUserFormDialog(
      context,
      widget.pageState,
      onSaved: () {
        if (mounted) _load();
      },
    );
  }

  Future<void> _punchStaff({
    required int targetUserId,
    required String staffName,
    required String? nextAction,
    required int punchCount,
    required bool dayComplete,
    required int branchId,
  }) async {
    if (_submitting || !mounted) return;

    if (!isTodayIso(_boardDate) && _canManageBoard) {
      showAppTopError('Switch to today’s date to punch attendance.');
      return;
    }

    if (!attendanceCanPunch(dayComplete: dayComplete, nextAction: nextAction)) {
      showAppTopError(
        dayComplete
            ? '$staffName is done for today.'
            : 'No punch available right now for $staffName.',
      );
      return;
    }

    final action = nextAction!;
    final actionLabel = attendancePunchButtonLabel(
      dayComplete: dayComplete,
      nextAction: nextAction,
      punchCount: punchCount,
    );

    final selfie = await showAttendanceSelfieSheet(
      context,
      staffName: staffName,
      actionLabel: actionLabel,
    );
    if (selfie == null || !mounted) return;

    setState(() {
      _submitting = true;
      _punchingUserId = targetUserId;
    });

    try {
      final clockResult = await _api.clockAttendance(
        action: action,
        userId: targetUserId,
        actorUserId: _userId,
        branchId: branchId,
        latitude: 0,
        longitude: 0,
        deviceInfo: kIsWeb
            ? 'Flutter Web Manual'
            : Platform.isAndroid
                ? 'Flutter Android Tablet'
                : Platform.isIOS
                    ? 'Flutter iOS'
                    : 'Flutter',
        tabletManual: true,
        photoBase64: selfie.base64,
        photoMime: selfie.mime,
      );

      if (!mounted) return;
      await _load();

      final punctuality = clockResult.status?.punctualityLabel;
      final lateSuffix =
          action == 'clock_in' && clockResult.status?.isLate == true
              ? ' · Late (${clockResult.status!.minutesLate}m)'
              : action == 'clock_in' && punctuality != null
                  ? ' · $punctuality'
                  : '';
      final summary = action == 'clock_in'
          ? '$staffName · $actionLabel$lateSuffix'
          : '$staffName · $actionLabel';

      setState(() {
        _submitting = false;
        _punchingUserId = null;
        _lastPunchSummary = summary;
      });

      if (action == 'clock_in' && clockResult.status?.isLate == true) {
        showAppTopError(
          'Clocked in late: $staffName (${clockResult.status!.minutesLate} min)',
        );
      } else {
        showAppTopSuccess('$actionLabel · $staffName');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _punchingUserId = null;
      });
      showAppTopError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _punchBoardRow(AttendanceBoardRow row) {
    return _punchStaff(
      targetUserId: row.userId,
      staffName: row.fullName,
      nextAction: row.nextAction,
      punchCount: row.punchCount,
      dayComplete: row.dayComplete,
      branchId: (row.branchId != null && row.branchId! > 0)
          ? row.branchId!
          : _branchId,
    );
  }

  Future<void> _punchSelf() {
    final status = _status;
    final user = widget.pageState.widget.currentUser;
    return _punchStaff(
      targetUserId: user.id,
      staffName: user.fullName,
      nextAction: status?.nextAction,
      punchCount: 0,
      dayComplete: status?.dayComplete ?? false,
      branchId: _branchId,
    );
  }

  List<AttendanceBoardRow> get _filteredRows {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _boardRows;
    return _boardRows
        .where(
          (row) =>
              row.fullName.toLowerCase().contains(q) ||
              row.role.toLowerCase().contains(q) ||
              row.branchName.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return ManagementPageShell(
      pageState: widget.pageState,
      activeSection: AppDrawerSection.attendance,
      title: 'Staff',
      subtitle: _canManageBoard
          ? 'Tap IN / OUT, take a selfie — no face recognition'
          : 'Tap IN / OUT, then take a selfie to record your punch',
      scrollBody: false,
      actions: [
        if (_canAddEmployee)
          IconButton(
            tooltip: 'Add employee',
            onPressed: _loading ? null : _addEmployee,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.green))
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _canManageBoard
                  ? _AdminBoardView(
                      boardDate: _boardDate,
                      schedule: _schedule,
                      filteredRows: _filteredRows,
                      searchController: _searchController,
                      submitting: _submitting,
                      punchingUserId: _punchingUserId,
                      clockEnabled: isTodayIso(_boardDate),
                      lastPunchSummary: _lastPunchSummary,
                      onPickDate: _pickBoardDate,
                      onSelectDate: _selectBoardDate,
                      onSearchChanged: (value) =>
                          setState(() => _searchQuery = value),
                      onPunch: _punchBoardRow,
                      onAddEmployee: _canAddEmployee ? _addEmployee : null,
                    )
                  : _SelfPunchView(
                      status: status,
                      submitting: _submitting,
                      lastPunchSummary: _lastPunchSummary,
                      staffName: widget.pageState.widget.currentUser.fullName,
                      onPunch: _punchSelf,
                    ),
    );
  }
}

class _AdminBoardView extends StatelessWidget {
  const _AdminBoardView({
    required this.boardDate,
    required this.schedule,
    required this.filteredRows,
    required this.searchController,
    required this.submitting,
    required this.punchingUserId,
    required this.clockEnabled,
    required this.lastPunchSummary,
    required this.onPickDate,
    required this.onSelectDate,
    required this.onSearchChanged,
    required this.onPunch,
    this.onAddEmployee,
  });

  final String boardDate;
  final AttendanceSchedule? schedule;
  final List<AttendanceBoardRow> filteredRows;
  final TextEditingController searchController;
  final bool submitting;
  final int? punchingUserId;
  final bool clockEnabled;
  final String? lastPunchSummary;
  final VoidCallback onPickDate;
  final Future<void> Function(DateTime date) onSelectDate;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function(AttendanceBoardRow) onPunch;
  final VoidCallback? onAddEmployee;

  @override
  Widget build(BuildContext context) {
    final dates = attendanceRecentDates();
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 132,
            child: ListView.separated(
              itemCount: dates.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == dates.length) {
                  return OutlinedButton(
                    onPressed: onPickDate,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('More…', style: TextStyle(fontSize: 12)),
                  );
                }
                final date = dates[index];
                final iso = toIsoDate(date);
                final selected = iso == boardDate;
                return Material(
                  color: selected
                      ? const Color(0xFFD4A574)
                      : const Color(0xFFF3EDE6),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onSelectDate(date),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF8B7355),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              attendanceDateRailLabel(date),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF5C4A3A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        onChanged: onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search…',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(999),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          attendanceDateRailLabel(
                            DateTime.tryParse(boardDate) ?? now,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          clockEnabled ? 'Today' : 'Past day',
                          style: TextStyle(
                            fontSize: 12,
                            color: clockEnabled
                                ? AppColors.green
                                : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    if (onAddEmployee != null) ...[
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: onAddEmployee,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.person_add_alt_1),
                        tooltip: 'Add employee',
                      ),
                    ],
                  ],
                ),
                if (lastPunchSummary != null) ...[
                  const SizedBox(height: 10),
                  _LastPunchCard(summary: lastPunchSummary!),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: filteredRows.isEmpty
                      ? const Center(
                          child: Text(
                            'No staff found',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filteredRows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final row = filteredRows[index];
                            return AttendanceStaffCard(
                              row: row,
                              schedule: schedule,
                              punchEnabled: clockEnabled,
                              punchBusy: submitting &&
                                  punchingUserId == row.userId,
                              onPunch: () => onPunch(row),
                            );
                          },
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

class _SelfPunchView extends StatelessWidget {
  const _SelfPunchView({
    required this.status,
    required this.submitting,
    required this.lastPunchSummary,
    required this.staffName,
    required this.onPunch,
  });

  final AttendanceStatus? status;
  final bool submitting;
  final String? lastPunchSummary;
  final String staffName;
  final VoidCallback onPunch;

  @override
  Widget build(BuildContext context) {
    final dayComplete = status?.dayComplete ?? false;
    final nextAction = status?.nextAction;
    final canPunch = attendanceCanPunch(
      dayComplete: dayComplete,
      nextAction: nextAction,
    );
    final buttonLabel = attendancePunchButtonLabel(
      dayComplete: dayComplete,
      nextAction: nextAction,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                staffName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                status?.totalHoursLabel ?? '0 hrs 0 mins',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              if (status?.nextActionNote != null &&
                  status!.nextActionNote!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  status!.nextActionNote!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: canPunch && !submitting ? onPunch : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.softSurface,
                    disabledForegroundColor: AppColors.muted,
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          buttonLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Tap the button, take a selfie, and your time is recorded.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (lastPunchSummary != null) ...[
          const SizedBox(height: 16),
          _LastPunchCard(summary: lastPunchSummary!),
        ],
      ],
    );
  }
}

class _LastPunchCard extends StatelessWidget {
  const _LastPunchCard({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greenBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              summary,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
