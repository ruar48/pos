import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/audit_log_entry.dart';
import '../../../models/staff_user.dart';
import '../../pos/pages/pos_home_page.dart';
import 'management_widgets.dart';

Future<void> showStaffUserFormDialog(
  BuildContext context,
  PosHomePageState pageState, {
  StaffUser? user,
  VoidCallback? onSaved,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _UserFormDialog(
      pageState: pageState,
      user: user,
      onSaved: onSaved,
    ),
  );
}

class SuperAdminDashboardContent extends StatelessWidget {
  const SuperAdminDashboardContent({
    super.key,
    required this.pageState,
    required this.onOpenUsers,
    required this.onOpenBranchesStaff,
    required this.onOpenAuditLogs,
    required this.onOpenSettings,
    required this.onOpenPromotions,
  });

  final PosHomePageState pageState;
  final VoidCallback onOpenUsers;
  final VoidCallback onOpenBranchesStaff;
  final VoidCallback onOpenAuditLogs;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPromotions;

  @override
  Widget build(BuildContext context) {
    final user = pageState.widget.currentUser;
    final staffCount = pageState.staffUsers.length;
    final activeCount =
        pageState.staffUsers.where((staff) => staff.isActive).length;
    final auditCount = pageState.auditLogs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final cards = [
              SummaryCard(
                label: 'Signed In Admin',
                value: user.fullName,
                icon: Icons.admin_panel_settings_outlined,
                subtitle: '${user.roleLabel} • ${user.email}',
              ),
              SummaryCard(
                label: 'Staff Accounts',
                value: '$staffCount',
                icon: Icons.people_outline,
                color: AppColors.blue,
                subtitle: '$activeCount active',
              ),
              SummaryCard(
                label: 'Recent Audit Events',
                value: '$auditCount',
                icon: Icons.history_toggle_off,
                color: AppColors.amber,
                subtitle: 'Latest system activity',
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
        const Text(
          'Administration Modules',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'User Management',
                description: 'Create staff accounts, assign roles, and reset passwords.',
                icon: Icons.manage_accounts_outlined,
                badge: '$staffCount users',
                onTap: onOpenUsers,
              ),
            ),
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Branches & Staff',
                description:
                    'Add branches, assign staff, and record salary or commission payouts.',
                icon: Icons.storefront_outlined,
                badge: '${pageState.branches.length} branches',
                onTap: onOpenBranchesStaff,
              ),
            ),
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Audit Logs',
                description: 'Review logins, changes, and privileged actions.',
                icon: Icons.fact_check_outlined,
                badge: '$auditCount events',
                onTap: onOpenAuditLogs,
              ),
            ),
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Store Settings',
                description: 'Tax, receipt, loyalty, and printer configuration.',
                icon: Icons.settings_outlined,
                onTap: onOpenSettings,
              ),
            ),
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Promotions',
                description: 'Manage coupon codes used at checkout.',
                icon: Icons.local_offer_outlined,
                badge: '${pageState.coupons.length} coupons',
                onTap: onOpenPromotions,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class UsersManagementContent extends StatefulWidget {
  const UsersManagementContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<UsersManagementContent> createState() => _UsersManagementContentState();
}

class _UsersManagementContentState extends State<UsersManagementContent> {
  final searchController = TextEditingController();
  String roleFilter = 'All';
  String statusFilter = 'All';
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
    _refresh();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.pageState.reloadStaffUsers();
    } catch (_) {}
    if (mounted) setState(() => refreshing = false);
  }

  List<StaffUser> get filteredUsers {
    final query = searchController.text.trim().toLowerCase();
    return widget.pageState.staffUsers.where((user) {
      final matchesRole =
          roleFilter == 'All' || user.roleLabel == roleFilter;
      final matchesStatus = switch (statusFilter) {
        'Active' => user.isActive,
        'Inactive' => !user.isActive,
        _ => true,
      };
      final matchesSearch = query.isEmpty ||
          user.fullName.toLowerCase().contains(query) ||
          user.username.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          user.role.toLowerCase().contains(query);
      return matchesRole && matchesStatus && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final users = filteredUsers;
    final currentUserId = widget.pageState.widget.currentUser.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name, username, email, or role...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () => searchController.clear(),
                          icon: const Icon(Icons.close),
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.softSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in [
                      'All',
                      'Super Admin',
                      'Admin',
                      'Manager',
                      'Cashier',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(filter),
                          selected: roleFilter == filter,
                          onSelected: (_) =>
                              setState(() => roleFilter = filter),
                          selectedColor: AppColors.lightGreen,
                          checkmarkColor: AppColors.green,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in ['All', 'Active', 'Inactive'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(filter),
                          selected: statusFilter == filter,
                          onSelected: (_) =>
                              setState(() => statusFilter = filter),
                          selectedColor: AppColors.lightGreen,
                          checkmarkColor: AppColors.green,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Staff Directory',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${users.length} shown',
              style: const TextStyle(color: AppColors.muted),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: refreshing ? null : _refresh,
              icon: refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(refreshing ? 'Refreshing...' : 'Refresh'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showUserFormDialog(),
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Add User'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (users.isEmpty)
          const _EmptyPanel(message: 'No staff accounts match your filters.')
        else
          ...users.map(
            (user) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _StaffUserCard(
                user: user,
                isSelf: user.id == currentUserId,
                onEdit: () => _showUserFormDialog(user: user),
                onToggle: user.id == currentUserId
                    ? null
                    : () async {
                        try {
                          await widget.pageState
                              .toggleManagedUserStatus(user.id);
                          if (!mounted) return;
                          setState(() {});
                          showTopSuccess(
                            context,
                            user.isActive
                                ? '${user.fullName} deactivated'
                                : '${user.fullName} activated',
                          );
                        } catch (error) {
                          if (!mounted) return;
                          showTopError(context, error.toString());
                        }
                      },
                onResetPassword: () => _showResetPasswordDialog(user),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showUserFormDialog({StaffUser? user}) {
    return showStaffUserFormDialog(
      context,
      widget.pageState,
      user: user,
      onSaved: () {
        _refresh();
        setState(() {});
      },
    );
  }

  Future<void> _showResetPasswordDialog(StaffUser user) {
    return showDialog<void>(
      context: context,
      builder: (_) => _ResetPasswordDialog(
        pageState: widget.pageState,
        user: user,
      ),
    );
  }
}

class AuditLogsContent extends StatefulWidget {
  const AuditLogsContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<AuditLogsContent> createState() => _AuditLogsContentState();
}

class _AuditLogsContentState extends State<AuditLogsContent> {
  String moduleFilter = 'All';
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.pageState.reloadAuditLogs(
        module: moduleFilter == 'All' ? null : moduleFilter,
      );
    } catch (_) {}
    if (mounted) setState(() => refreshing = false);
  }

  List<AuditLogEntry> get filteredLogs {
    if (moduleFilter == 'All') return widget.pageState.auditLogs;
    return widget.pageState.auditLogs
        .where((log) => log.module == moduleFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final logs = filteredLogs;
    final modules = {
      for (final log in widget.pageState.auditLogs) log.module,
    }.toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in ['All', ...modules])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter),
                    selected: moduleFilter == filter,
                    onSelected: (_) async {
                      setState(() => moduleFilter = filter);
                      await _refresh();
                    },
                    selectedColor: AppColors.lightGreen,
                    checkmarkColor: AppColors.green,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Audit Trail',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${logs.length} events',
              style: const TextStyle(color: AppColors.muted),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: refreshing ? null : _refresh,
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
        if (logs.isEmpty)
          const _EmptyPanel(message: 'No audit events found for this filter.')
        else
          TableCard(
            title: 'Recent Activity',
            columns: const ['When', 'User', 'Action', 'Module', 'Details'],
            rows: logs
                .map(
                  (log) => [
                    formatDateTime(log.createdAt),
                    log.actorLabel,
                    log.action,
                    log.module,
                    log.description,
                  ],
                )
                .toList(),
          ),
      ],
    );
  }
}

class _StaffUserCard extends StatelessWidget {
  const _StaffUserCard({
    required this.user,
    required this.isSelf,
    required this.onEdit,
    this.onToggle,
    required this.onResetPassword,
  });

  final StaffUser user;
  final bool isSelf;
  final VoidCallback onEdit;
  final VoidCallback? onToggle;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final statusColor = user.isActive ? AppColors.green : AppColors.muted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.lightGreen,
                child: Text(
                  user.fullName.isNotEmpty
                      ? user.fullName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          user.fullName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.lightGreen,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.green,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      user.isLabor
                          ? 'Attendance only • ${user.branchLabel}'
                          : '${user.username} • ${user.email}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    if (!user.isLabor)
                      Text(
                        user.branchLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.darkGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    user.roleLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              if (!user.isLabor)
                TextButton.icon(
                  onPressed: onResetPassword,
                  icon: const Icon(Icons.lock_reset, size: 18),
                  label: const Text('Reset Password'),
                ),
              if (onToggle != null)
                TextButton.icon(
                  onPressed: onToggle,
                  icon: Icon(
                    user.isActive
                        ? Icons.person_off_outlined
                        : Icons.person_outline,
                    size: 18,
                  ),
                  label: Text(user.isActive ? 'Deactivate' : 'Activate'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({
    required this.pageState,
    this.user,
    this.onSaved,
  });

  final PosHomePageState pageState;
  final StaffUser? user;
  final VoidCallback? onSaved;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final fullNameController = TextEditingController();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  late UserRole selectedRole;
  int? selectedBranchId;
  bool saving = false;

  bool get isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    if (user != null) {
      fullNameController.text = user.fullName;
      usernameController.text = user.username;
      emailController.text = user.email;
      selectedRole = user.userRole;
      selectedBranchId = user.branchId;
    } else {
      selectedRole = UserRole.cashier;
      selectedBranchId = widget.pageState.activeBranchId;
    }
  }

  @override
  void dispose() {
    fullNameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fullName = fullNameController.text.trim();
    final username = usernameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final isLabor = selectedRole == UserRole.labor;

    if (fullName.isEmpty) {
      _showError('Full name is required.');
      return;
    }
    if (!isLabor && (username.isEmpty || email.isEmpty)) {
      _showError('Username and email are required.');
      return;
    }
    if (!isEditing && !isLabor && password.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }

    setState(() => saving = true);
    try {
      if (isEditing) {
        await widget.pageState.updateManagedUser(
          id: widget.user!.id,
          fullName: fullName,
          username: isLabor ? widget.user!.username : username,
          email: isLabor ? widget.user!.email : email,
          role: selectedRole,
          branchId: selectedBranchId,
        );
      } else {
        await widget.pageState.addManagedUser(
          fullName: fullName,
          username: isLabor ? null : username,
          email: isLabor ? null : email,
          password: isLabor ? null : password,
          role: selectedRole,
          branchId: selectedBranchId,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved?.call();
      showAppTopSuccess(isEditing ? 'User updated' : 'User created');
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
    final isLabor = selectedRole == UserRole.labor;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.manage_accounts_outlined, color: AppColors.green),
          const SizedBox(width: 10),
          Text(isEditing ? 'Edit User' : 'Add User'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: fullNameController,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              value: selectedRole,
              decoration: const InputDecoration(
                labelText: 'Role *',
                prefixIcon: Icon(Icons.shield_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: UserRole.admin,
                  child: Text('Admin'),
                ),
                DropdownMenuItem(
                  value: UserRole.cashier,
                  child: Text('Cashier'),
                ),
                DropdownMenuItem(
                  value: UserRole.labor,
                  child: Text('Labor (no login)'),
                ),
              ],
              onChanged: saving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => selectedRole = value);
                    },
            ),
            if (isLabor) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.greenBorder),
                ),
                child: const Text(
                  'Labor staff are for attendance and face clock-in only. '
                  'They cannot sign in to the POS.',
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              if (!isEditing) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password *',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
              ],
            ],
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
                  child: Text('Unassigned'),
                ),
                for (final branch in widget.pageState.branches
                    .where((item) => item.isActive))
                  DropdownMenuItem<int?>(
                    value: branch.id,
                    child: Text(branch.name),
                  ),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() => selectedBranchId = value),
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

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({
    required this.pageState,
    required this.user,
  });

  final PosHomePageState pageState;
  final StaffUser user;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final passwordController = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = passwordController.text;
    if (password.length < 6) {
      showTopWarning(context, 'Password must be at least 6 characters.');
      return;
    }

    setState(() => saving = true);
    try {
      await widget.pageState.resetManagedUserPassword(
        id: widget.user.id,
        password: password,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppTopSuccess('Password reset for ${widget.user.fullName}');
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set a new password for ${widget.user.fullName}.'),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New Password',
              prefixIcon: Icon(Icons.lock_reset),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : 'Reset'),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

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
          Text(message, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}
