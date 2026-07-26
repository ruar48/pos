import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/branch.dart';
import '../../../models/staff_payment.dart';
import '../../../models/staff_user.dart';
import '../../pos/pages/pos_home_page.dart';
import 'management_widgets.dart';
import 'super_admin_widgets.dart';

class BranchesStaffContent extends StatefulWidget {
  const BranchesStaffContent({
    super.key,
    required this.pageState,
    required this.onOpenBranches,
    required this.onOpenStaff,
    required this.onOpenPayments,
  });

  final PosHomePageState pageState;
  final VoidCallback onOpenBranches;
  final VoidCallback onOpenStaff;
  final VoidCallback onOpenPayments;

  @override
  State<BranchesStaffContent> createState() => _BranchesStaffContentState();
}

class _BranchesStaffContentState extends State<BranchesStaffContent> {
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => refreshing = true);
    try {
      await Future.wait([
        widget.pageState.reloadBranches(includeInactive: true),
        widget.pageState.reloadStaffUsers(),
        widget.pageState.reloadStaffPayments(),
      ]);
    } catch (_) {}
    if (mounted) setState(() => refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.pageState.settings.currencySymbol;
    final branchCount = widget.pageState.branches.length;
    final assignedStaff = widget.pageState.staffUsers
        .where((user) => user.branchId != null && user.branchId! > 0)
        .length;
    final totalPaid = widget.pageState.staffPayments.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final cards = [
              SummaryCard(
                label: 'Branches',
                value: '$branchCount',
                icon: Icons.storefront_outlined,
                subtitle:
                    '${widget.pageState.branches.where((b) => b.isActive).length} active',
              ),
              SummaryCard(
                label: 'Assigned Staff',
                value: '$assignedStaff',
                icon: Icons.badge_outlined,
                color: AppColors.blue,
                subtitle:
                    '${widget.pageState.staffUsers.length} total accounts',
              ),
              SummaryCard(
                label: 'Payments Recorded',
                value: formatMoney(currency, totalPaid),
                icon: Icons.payments_outlined,
                color: AppColors.amber,
                subtitle: '${widget.pageState.staffPayments.length} entries',
              ),
            ];

            if (isWide) {
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards) SizedBox(width: 220, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              'Branches & Staff Modules',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: refreshing ? null : _refreshAll,
              icon: refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(refreshing ? 'Refreshing...' : 'Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Branch Directory',
                description: 'Add, edit, and activate store branches.',
                icon: Icons.storefront_outlined,
                badge: '$branchCount branches',
                onTap: widget.onOpenBranches,
              ),
            ),
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Staff & Assignments',
                description:
                    'Add staff accounts and assign them to branches.',
                icon: Icons.badge_outlined,
                badge: '$assignedStaff assigned',
                onTap: widget.onOpenStaff,
              ),
            ),
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Staff Payments',
                description: 'Record salary, commission, bonus, or allowance.',
                icon: Icons.payments_outlined,
                badge: formatMoney(currency, totalPaid),
                onTap: widget.onOpenPayments,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class BranchesDirectoryContent extends StatefulWidget {
  const BranchesDirectoryContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<BranchesDirectoryContent> createState() =>
      _BranchesDirectoryContentState();
}

class _BranchesDirectoryContentState extends State<BranchesDirectoryContent> {
  bool refreshing = false;

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.pageState.reloadBranches(includeInactive: true);
    } catch (_) {}
    if (mounted) setState(() => refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _BranchesTab(
      pageState: widget.pageState,
      refreshing: refreshing,
      onRefresh: _refresh,
      onChanged: () => setState(() {}),
    );
  }
}

class StaffAssignmentsContent extends StatefulWidget {
  const StaffAssignmentsContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<StaffAssignmentsContent> createState() =>
      _StaffAssignmentsContentState();
}

class _StaffAssignmentsContentState extends State<StaffAssignmentsContent> {
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      await Future.wait([
        widget.pageState.reloadStaffUsers(),
        widget.pageState.reloadAnalyticsData(),
      ]);
    } catch (_) {}
    if (mounted) setState(() => refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _StaffAssignmentsTab(
      pageState: widget.pageState,
      refreshing: refreshing,
      onRefresh: _refresh,
      onChanged: () => setState(() {}),
    );
  }
}

class StaffPaymentsContent extends StatefulWidget {
  const StaffPaymentsContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<StaffPaymentsContent> createState() => _StaffPaymentsContentState();
}

class _StaffPaymentsContentState extends State<StaffPaymentsContent> {
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.pageState.reloadStaffPayments();
    } catch (_) {}
    if (mounted) setState(() => refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _StaffPaymentsTab(
      pageState: widget.pageState,
      refreshing: refreshing,
      onRefresh: _refresh,
      onChanged: () => setState(() {}),
    );
  }
}

class _BranchesTab extends StatelessWidget {
  const _BranchesTab({
    required this.pageState,
    required this.onChanged,
    this.refreshing = false,
    this.onRefresh,
  });

  final PosHomePageState pageState;
  final VoidCallback onChanged;
  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final branches = pageState.branches;

    return ListView(
      children: [
        Row(
          children: [
            const Text(
              'Branch Directory',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            if (onRefresh != null)
              OutlinedButton.icon(
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(refreshing ? 'Refreshing...' : 'Refresh'),
              ),
            if (onRefresh != null) const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showBranchDialog(context),
              icon: const Icon(Icons.add_business, size: 18),
              label: const Text('Add Branch'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (branches.isEmpty)
          const _EmptyPanel(message: 'No branches found.')
        else
          ...branches.map(
            (branch) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _BranchCard(
                branch: branch,
                staffCount: pageState.staffUsers
                    .where((user) => user.branchId == branch.id)
                    .length,
                onEdit: () => _showBranchDialog(context, branch: branch),
                onToggle: branch.id == 1
                    ? null
                    : () async {
                        try {
                          await pageState.toggleManagedBranchStatus(branch.id);
                          onChanged();
                          if (!context.mounted) return;
                          showTopSuccess(
                            context,
                            branch.isActive
                                ? '${branch.name} deactivated'
                                : '${branch.name} activated',
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          showTopError(context, error.toString());
                        }
                      },
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showBranchDialog(BuildContext context, {Branch? branch}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _BranchFormDialog(
        pageState: pageState,
        branch: branch,
        onSaved: onChanged,
      ),
    );
  }
}

class _StaffAssignmentsTab extends StatelessWidget {
  const _StaffAssignmentsTab({
    required this.pageState,
    required this.onChanged,
    this.refreshing = false,
    this.onRefresh,
  });

  final PosHomePageState pageState;
  final VoidCallback onChanged;
  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final currency = pageState.settings.currencySymbol;
    final staff = pageState.staffUsers.toList();

    return ListView(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Create staff accounts, assign branches, and review sales handled',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
            if (onRefresh != null)
              OutlinedButton.icon(
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(refreshing ? 'Refreshing...' : 'Refresh'),
              ),
            if (onRefresh != null) const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showStaffFormDialog(context),
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Add Staff'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (staff.isEmpty)
          _EmptyPanel(
            message: 'No staff yet. Tap Add Staff to create an admin, cashier, or labor worker.',
            actionLabel: 'Add Staff',
            onAction: () => _showStaffFormDialog(context),
          )
        else
          ...staff.map(
            (user) {
              final salesTotal = pageState.staffSalesTotal(user.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.fullName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${user.username} • ${user.roleLabel}',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            Text(
                              user.branchLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.darkGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sales handled: ${formatMoney(currency, salesTotal)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.darkGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _showStaffFormDialog(
                              context,
                              user: user,
                            ),
                            child: const Text('Edit'),
                          ),
                          TextButton(
                            onPressed: () =>
                                _showAssignBranchDialog(context, user),
                            child: const Text('Assign Branch'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _showStaffFormDialog(
    BuildContext context, {
    StaffUser? user,
  }) {
    return showStaffUserFormDialog(
      context,
      pageState,
      user: user,
      onSaved: () async {
        await pageState.reloadStaffUsers();
        onChanged();
      },
    );
  }

  Future<void> _showAssignBranchDialog(BuildContext context, StaffUser user) {
    return showDialog<void>(
      context: context,
      builder: (_) => _AssignBranchDialog(
        pageState: pageState,
        user: user,
        onSaved: onChanged,
      ),
    );
  }
}

class _StaffPaymentsTab extends StatelessWidget {
  const _StaffPaymentsTab({
    required this.pageState,
    required this.onChanged,
    this.refreshing = false,
    this.onRefresh,
  });

  final PosHomePageState pageState;
  final VoidCallback onChanged;
  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final currency = pageState.settings.currencySymbol;
    final payments = pageState.staffPayments;

    return ListView(
      children: [
        Row(
          children: [
            const Text(
              'Payroll & Payouts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            if (onRefresh != null)
              OutlinedButton.icon(
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(refreshing ? 'Refreshing...' : 'Refresh'),
              ),
            if (onRefresh != null) const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showPaymentDialog(context),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Record Payment'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (payments.isEmpty)
          const _EmptyPanel(
            message: 'No staff payments recorded yet. Use Record Payment to log salary, commission, or bonus payouts.',
          )
        else
          TableCard(
            title: 'Recent Payments',
            columns: const [
              'Date',
              'Staff',
              'Branch',
              'Type',
              'Amount',
              'Notes',
            ],
            rows: payments
                .map(
                  (payment) => [
                    formatDateTime(payment.createdAt),
                    payment.staffName,
                    payment.branchName ?? '—',
                    payment.typeLabel,
                    formatMoney(currency, payment.amount),
                    payment.notes ?? '—',
                  ],
                )
                .toList(),
          ),
      ],
    );
  }

  Future<void> _showPaymentDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => _StaffPaymentDialog(
        pageState: pageState,
        onSaved: onChanged,
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.staffCount,
    required this.onEdit,
    this.onToggle,
  });

  final Branch branch;
  final int staffCount;
  final VoidCallback onEdit;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.storefront_outlined, color: AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  branch.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  [
                    if (branch.code?.isNotEmpty == true) branch.code!,
                    if (branch.location?.isNotEmpty == true) branch.location!,
                    '$staffCount staff assigned',
                  ].join(' • '),
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                branch.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: branch.isActive ? AppColors.green : AppColors.muted,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(onPressed: onEdit, child: const Text('Edit')),
                  if (onToggle != null)
                    TextButton(
                      onPressed: onToggle,
                      child: Text(branch.isActive ? 'Deactivate' : 'Activate'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BranchFormDialog extends StatefulWidget {
  const _BranchFormDialog({
    required this.pageState,
    this.branch,
    this.onSaved,
  });

  final PosHomePageState pageState;
  final Branch? branch;
  final VoidCallback? onSaved;

  @override
  State<_BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends State<_BranchFormDialog> {
  final nameController = TextEditingController();
  final codeController = TextEditingController();
  final locationController = TextEditingController();
  bool saving = false;

  bool get isEditing => widget.branch != null;

  @override
  void initState() {
    super.initState();
    final branch = widget.branch;
    if (branch != null) {
      nameController.text = branch.name;
      codeController.text = branch.code ?? '';
      locationController.text = branch.location ?? '';
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    codeController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showError('Branch name is required.');
      return;
    }

    setState(() => saving = true);
    try {
      if (isEditing) {
        await widget.pageState.updateManagedBranch(
          id: widget.branch!.id,
          name: name,
          code: codeController.text.trim(),
          location: locationController.text.trim(),
        );
      } else {
        await widget.pageState.addBranch(
          name: name,
          code: codeController.text.trim(),
          location: locationController.text.trim(),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved?.call();
      showAppTopSuccess(isEditing ? 'Branch updated' : 'Branch created');
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString());
      setState(() => saving = false);
    }
  }

  void _showError(String message) {
    showTopError(context, message.replaceFirst('Exception: ', ''));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.storefront_outlined, color: AppColors.green),
          const SizedBox(width: 10),
          Text(isEditing ? 'Edit Branch' : 'Add Branch'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Branch Name *',
                prefixIcon: Icon(Icons.store_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Branch Code',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : (isEditing ? 'Update' : 'Save')),
        ),
      ],
    );
  }
}

class _AssignBranchDialog extends StatefulWidget {
  const _AssignBranchDialog({
    required this.pageState,
    required this.user,
    this.onSaved,
  });

  final PosHomePageState pageState;
  final StaffUser user;
  final VoidCallback? onSaved;

  @override
  State<_AssignBranchDialog> createState() => _AssignBranchDialogState();
}

class _AssignBranchDialogState extends State<_AssignBranchDialog> {
  int? selectedBranchId;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    selectedBranchId = widget.user.branchId;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.pageState.updateManagedUser(
        id: widget.user.id,
        fullName: widget.user.fullName,
        username: widget.user.username,
        email: widget.user.email,
        role: widget.user.userRole,
        branchId: selectedBranchId,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved?.call();
      showAppTopSuccess('${widget.user.fullName} assigned to branch');
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeBranches = widget.pageState.branches
        .where((branch) => branch.isActive)
        .toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Assign ${widget.user.fullName}'),
      content: SizedBox(
        width: 380,
        child: DropdownButtonFormField<int?>(
          value: selectedBranchId,
          decoration: const InputDecoration(
            labelText: 'Branch',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Unassigned'),
            ),
            for (final branch in activeBranches)
              DropdownMenuItem<int?>(
                value: branch.id,
                child: Text(branch.name),
              ),
          ],
          onChanged: saving
              ? null
              : (value) => setState(() => selectedBranchId = value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : 'Save Assignment'),
        ),
      ],
    );
  }
}

class _StaffPaymentDialog extends StatefulWidget {
  const _StaffPaymentDialog({
    required this.pageState,
    this.onSaved,
  });

  final PosHomePageState pageState;
  final VoidCallback? onSaved;

  @override
  State<_StaffPaymentDialog> createState() => _StaffPaymentDialogState();
}

class _StaffPaymentDialogState extends State<_StaffPaymentDialog> {
  final amountController = TextEditingController();
  final notesController = TextEditingController();
  int? selectedUserId;
  int? selectedBranchId;
  StaffPaymentType selectedType = StaffPaymentType.salary;
  DateTime? periodStart;
  DateTime? periodEnd;
  bool saving = false;

  List<StaffUser> get payableStaff => widget.pageState.staffUsers
      .where((user) => user.isActive)
      .toList();

  @override
  void dispose() {
    amountController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required bool isStart,
  }) async {
    final initial = isStart
        ? (periodStart ?? DateTime.now())
        : (periodEnd ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        periodStart = picked;
      } else {
        periodEnd = picked;
      }
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    if (selectedUserId == null || amount <= 0) {
      _showError('Select a staff member and enter a valid amount.');
      return;
    }

    setState(() => saving = true);
    try {
      await widget.pageState.addStaffPayment(
        userId: selectedUserId!,
        amount: amount,
        paymentType: selectedType,
        branchId: selectedBranchId,
        periodStart: periodStart == null
            ? null
            : periodStart!.toIso8601String().split('T').first,
        periodEnd:
            periodEnd == null ? null : periodEnd!.toIso8601String().split('T').first,
        notes: notesController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved?.call();
      showAppTopSuccess('Staff payment recorded');
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString());
      setState(() => saving = false);
    }
  }

  void _showError(String message) {
    showTopError(context, message.replaceFirst('Exception: ', ''));
  }

  @override
  Widget build(BuildContext context) {
    final activeBranches = widget.pageState.branches
        .where((branch) => branch.isActive)
        .toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.payments_outlined, color: AppColors.green),
          SizedBox(width: 10),
          Text('Record Staff Payment'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: selectedUserId,
                decoration: const InputDecoration(
                  labelText: 'Staff Member *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                items: [
                  for (final user in payableStaff)
                    DropdownMenuItem(
                      value: user.id,
                      child: Text('${user.fullName} (${user.roleLabel})'),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        final user = payableStaff.firstWhere(
                          (staff) => staff.id == value,
                        );
                        setState(() {
                          selectedUserId = value;
                          selectedBranchId = user.branchId;
                        });
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: selectedBranchId,
                decoration: const InputDecoration(
                  labelText: 'Branch',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('No branch'),
                  ),
                  for (final branch in activeBranches)
                    DropdownMenuItem<int?>(
                      value: branch.id,
                      child: Text(branch.name),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => selectedBranchId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StaffPaymentType>(
                value: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Payment Type *',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: StaffPaymentType.salary,
                    child: Text('Salary'),
                  ),
                  DropdownMenuItem(
                    value: StaffPaymentType.commission,
                    child: Text('Commission'),
                  ),
                  DropdownMenuItem(
                    value: StaffPaymentType.bonus,
                    child: Text('Bonus'),
                  ),
                  DropdownMenuItem(
                    value: StaffPaymentType.allowance,
                    child: Text('Allowance'),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => selectedType = value);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount *',
                  prefixIcon: const Icon(Icons.attach_money),
                  prefixText: widget.pageState.settings.currencySymbol,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: saving ? null : () => _pickDate(isStart: true),
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        periodStart == null
                            ? 'Period Start'
                            : periodStart!.toIso8601String().split('T').first,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: saving ? null : () => _pickDate(isStart: false),
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        periodEnd == null
                            ? 'Period End'
                            : periodEnd!.toIso8601String().split('T').first,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : 'Record Payment'),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 42, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
