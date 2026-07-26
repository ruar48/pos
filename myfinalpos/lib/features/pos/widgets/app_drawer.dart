import 'package:flutter/material.dart';

import '../../../core/constants/brand.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../services/offline/offline_catalog_store.dart';
import '../../auth/change_password_dialog.dart';
import '../../auth/login.dart';
import '../../attendance/attendance_page.dart';
import '../../management/widgets/live_pos_monitor_widgets.dart';
import '../../management/pages/management_pages.dart';
import '../../orders/orders.dart';
import '../../transactions_report/transactions_report_page.dart';
import '../pages/pos_home_page.dart';
import '../pages/tablet_printer_page.dart';
import 'app_drawer_section.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.pageState,
    required this.activeSection,
  });

  final PosHomePageState pageState;
  final AppDrawerSection activeSection;

  void _goToPosRegister(BuildContext context) {
    Navigator.pop(context);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    pageState.refreshProductCatalog();
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.pop(context);
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute(builder: (_) => page);
    if (navigator.canPop()) {
      navigator.pushReplacement(route);
    } else {
      navigator.push(route);
    }
  }

  Future<void> _logout(BuildContext context) async {
    await OfflineSessionStore.clearUser();
    if (!context.mounted) return;
    Navigator.pop(context);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = pageState.widget.currentUser;
    final canManageOperations = user.canManageOperations;
    final canAccessReports = user.canAccessReports;
    final canAccessSuperAdmin = user.canAccessSuperAdmin;
    final canManageSettings = user.canManageSettings;
    final isCashier = user.isCashier;

    return Drawer(
      backgroundColor: AppColors.sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(
              userName: user.fullName,
              roleLabel: user.roleLabel,
              branchLabel: pageState.monitoredBranchLabel,
              showBranch: false,
            ),
            const Divider(height: 1, color: AppColors.sidebarBorder),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                children: [
                  if (canAccessReports) ...[
                    const _DrawerSectionLabel('Overview'),
                    _DrawerTile(
                      icon: Icons.dashboard_outlined,
                      label: 'Dashboard',
                      selected:
                          activeSection == AppDrawerSection.frontendDashboard,
                      onTap: () => _openPage(
                        context,
                        FrontendDashboardPage(pageState: pageState),
                      ),
                    ),
                    if (user.canMonitorAllBranches)
                      _DrawerTile(
                        icon: Icons.monitor_heart_outlined,
                        label: 'Live POS Monitor',
                        selected:
                            activeSection == AppDrawerSection.livePosMonitor,
                        onTap: () => _openPage(
                          context,
                          LivePosMonitorPage(pageState: pageState),
                        ),
                      ),
                  ],
                  _DrawerTile(
                    icon: Icons.point_of_sale_outlined,
                    label: 'POS Sales',
                    selected: activeSection == AppDrawerSection.posRegister,
                    onTap: () => _goToPosRegister(context),
                  ),
                  _DrawerTile(
                    icon: Icons.fingerprint_outlined,
                    label: 'Attendance',
                    selected: activeSection == AppDrawerSection.attendance,
                    onTap: () => _openPage(
                      context,
                      AttendancePage(pageState: pageState),
                    ),
                  ),
                  const _DrawerDivider(),
                  const _DrawerSectionLabel('Operations'),
                  _DrawerTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Orders',
                    selected: activeSection == AppDrawerSection.orders,
                    onTap: () => _openPage(
                      context,
                      OrdersPage(pageState: pageState),
                    ),
                  ),
                  if (canManageOperations)
                    _DrawerTile(
                      icon: Icons.undo_outlined,
                      label: 'Refunds',
                      selected: activeSection == AppDrawerSection.refundCenter,
                      onTap: () => _openPage(
                        context,
                        RefundCenterPage(pageState: pageState),
                      ),
                    ),
                  if (canManageOperations) ...[
                    _DrawerTile(
                      icon: Icons.local_offer_outlined,
                      label: 'Promotions',
                      selected: activeSection == AppDrawerSection.promotions,
                      onTap: () => _openPage(
                        context,
                        PromotionsPage(pageState: pageState),
                      ),
                    ),
                  ],
                  if (canAccessReports && !isCashier) ...[
                    const _DrawerDivider(),
                    const _DrawerSectionLabel('Finance & Reports'),
                    _DrawerTile(
                      icon: Icons.table_chart_outlined,
                      label: 'Transactions',
                      selected:
                          activeSection == AppDrawerSection.transactionReports,
                      onTap: () => _openPage(
                        context,
                        TransactionsReportPage(pageState: pageState),
                      ),
                    ),
                    _DrawerTile(
                      icon: Icons.history,
                      label: 'Sales History',
                      selected: activeSection == AppDrawerSection.salesHistory,
                      onTap: () => _openPage(
                        context,
                        SalesHistoryPage(pageState: pageState),
                      ),
                    ),
                    _DrawerTile(
                      icon: Icons.assessment_outlined,
                      label: 'Reports',
                      selected: activeSection == AppDrawerSection.reports,
                      onTap: () => _openPage(
                        context,
                        ReportsPage(pageState: pageState),
                      ),
                    ),
                  ] else ...[
                    const _DrawerDivider(),
                    const _DrawerSectionLabel('Records'),
                    _DrawerTile(
                      icon: Icons.history,
                      label: 'Sales History',
                      selected: activeSection == AppDrawerSection.salesHistory,
                      onTap: () => _openPage(
                        context,
                        SalesHistoryPage(pageState: pageState),
                      ),
                    ),
                  ],
                  if (canManageSettings || (canAccessSuperAdmin && !isCashier)) ...[
                    const _DrawerDivider(),
                    const _DrawerSectionLabel('Administration'),
                    if (canManageSettings)
                      _DrawerTile(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        selected: activeSection == AppDrawerSection.settings,
                        onTap: () => _openPage(
                          context,
                          SettingsPage(pageState: pageState),
                        ),
                      ),
                    if (canAccessSuperAdmin && !isCashier)
                      _DrawerTile(
                        icon: Icons.admin_panel_settings_outlined,
                        label: 'Super Admin',
                        selected: activeSection == AppDrawerSection.superAdmin,
                        onTap: () => _openPage(
                          context,
                          SuperAdminDashboardPage(pageState: pageState),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.sidebarBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _DrawerSectionLabel('System'),
                  _DrawerTile(
                    icon: Icons.print_outlined,
                    label: 'My Printer',
                    selected: activeSection == AppDrawerSection.tabletPrinter,
                    onTap: () => _openPage(
                      context,
                      TabletPrinterPage(pageState: pageState),
                    ),
                  ),
                  if (user.canLogin)
                    _DrawerTile(
                      icon: Icons.lock_outline,
                      label: 'Change password',
                      onTap: () {
                        Navigator.pop(context);
                        showChangePasswordDialog(
                          context,
                          pageState: pageState,
                        );
                      },
                    ),
                  _DrawerTile(
                    icon: Icons.logout,
                    label: 'Log out',
                    onTap: () => _logout(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.userName,
    required this.roleLabel,
    required this.branchLabel,
    required this.showBranch,
  });

  final String userName;
  final String roleLabel;
  final String branchLabel;
  final bool showBranch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLogo(
            size: BrandLogoSize.sm,
            subtitle: AppBrand.posSubtitle,
            onDark: true,
          ),
          const SizedBox(height: 14),
          Text(
            userName,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.sidebarForeground,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            roleLabel,
            style: const TextStyle(
              color: AppColors.sidebarMuted,
              fontSize: 12,
            ),
          ),
          if (showBranch) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.sidebarAccent.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.sidebarBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.store_outlined,
                    color: AppColors.sidebarMuted,
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    branchLabel,
                    style: const TextStyle(
                      color: AppColors.sidebarForeground,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.sidebarMuted,
        ),
      ),
    );
  }
}

class _DrawerDivider extends StatelessWidget {
  const _DrawerDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Divider(height: 1, color: AppColors.sidebarBorder),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.sidebarAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppColors.sidebarAccent.withValues(alpha: 0.5),
          splashColor: AppColors.sidebarAccent,
          child: Stack(
            children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: AppColors.sidebarWheat,
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: selected
                          ? AppColors.sidebarForeground
                          : AppColors.sidebarMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13,
                          color: selected
                              ? AppColors.sidebarForeground
                              : AppColors.sidebarForeground.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
