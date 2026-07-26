import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/app_settings.dart';
import '../../../models/product.dart';
import '../../../models/sales_history_record.dart';
import '../../orders/orders.dart';
import '../../pos/pages/pos_home_page.dart';
import '../../pos/widgets/app_drawer_section.dart';
import '../widgets/customers_management_widgets.dart';
import '../widgets/catalog_management_widgets.dart';
import '../widgets/management_widgets.dart';
import '../widgets/accounting_dashboard_widgets.dart';
import '../widgets/analytics_reports_widgets.dart';
import '../widgets/reports_overview_widgets.dart';
import '../widgets/live_pos_monitor_widgets.dart';
import '../widgets/frontend_dashboard_widgets.dart';
import '../widgets/sales_history_management_widgets.dart';
import '../widgets/promotions_management_widgets.dart';
import '../widgets/super_admin_widgets.dart';
import '../widgets/branch_staff_management_widgets.dart';
import '../widgets/refund_center_widgets.dart';
import '../widgets/settings_management_widgets.dart';

class RefundCenterPage extends StatelessWidget {
  const RefundCenterPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RefundCenterState>(
      create: (_) => createRefundCenterState(),
      child: ManagementPageShell(
        pageState: pageState,
        activeSection: AppDrawerSection.refundCenter,
        title: 'Refunds',
        subtitle: 'Process refunds from completed orders',
        scrollBody: false,
        child: RefundCenterContent(pageState: pageState),
      ),
    );
  }
}

class ProductsManagementPage extends StatelessWidget {
  const ProductsManagementPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.inventory,
      title: 'Products & Inventory',
      scrollBody: false,
      child: CatalogManagementContent(
        pageState: pageState,
        initialTab: CatalogTab.products,
      ),
    );
  }
}

class FrontendDashboardPage extends StatelessWidget {
  const FrontendDashboardPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.frontendDashboard,
      title: 'Dashboard',
      child: FrontendDashboardContent(
        pageState: pageState,
        onReturnToRegister: () => Navigator.of(context).pop(),
        onOpenOrders: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OrdersPage(pageState: pageState),
          ),
        ),
        onOpenSalesHistory: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SalesHistoryPage(pageState: pageState),
          ),
        ),
        onOpenInventory: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => InventoryManagementPage(pageState: pageState),
          ),
        ),
        onOpenCustomers: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CustomersManagementPage(pageState: pageState),
          ),
        ),
      ),
    );
  }
}

class InventoryManagementPage extends StatelessWidget {
  const InventoryManagementPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.inventory,
      title: 'Products & Inventory',
      scrollBody: false,
      child: CatalogManagementContent(pageState: pageState),
    );
  }
}

class PromotionsPage extends StatelessWidget {
  const PromotionsPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.promotions,
      title: 'Promotions',
      subtitle: 'Create and manage coupon codes for the POS register',
      child: PromotionsManagementContent(pageState: pageState),
    );
  }
}

class AccountingDashboardPage extends StatelessWidget {
  const AccountingDashboardPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.accounting,
      title: 'Accounting Dashboard',
      subtitle: 'Revenue, tax, discounts, and payment summary',
      child: AccountingDashboardContent(pageState: pageState),
    );
  }
}

class SuperAdminDashboardPage extends StatefulWidget {
  const SuperAdminDashboardPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<SuperAdminDashboardPage> createState() =>
      _SuperAdminDashboardPageState();
}

class _SuperAdminDashboardPageState extends State<SuperAdminDashboardPage> {
  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    await Future.wait([
      widget.pageState.reloadBranches(includeInactive: true),
      widget.pageState.reloadStaffUsers(),
      widget.pageState.reloadAuditLogs(),
    ]);
    if (mounted) setState(() {});
  }

  void _openPage(Widget page) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: widget.pageState,
      activeSection: AppDrawerSection.superAdmin,
      title: 'Super Admin',
      subtitle: 'System oversight and privileged actions',
      child: SuperAdminDashboardContent(
        pageState: widget.pageState,
        onOpenUsers: () => _openPage(
          UsersManagementPage(pageState: widget.pageState),
        ),
        onOpenBranchesStaff: () => _openPage(
          BranchesStaffPage(pageState: widget.pageState),
        ),
        onOpenAuditLogs: () => _openPage(
          AuditLogsPage(pageState: widget.pageState),
        ),
        onOpenSettings: () => _openPage(
          SettingsPage(pageState: widget.pageState),
        ),
        onOpenPromotions: () => _openPage(
          PromotionsPage(pageState: widget.pageState),
        ),
      ),
    );
  }
}

class UsersManagementPage extends StatelessWidget {
  const UsersManagementPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.superAdmin,
      title: 'User Management',
      subtitle: 'Staff accounts, roles, and access control',
      child: UsersManagementContent(pageState: pageState),
    );
  }
}

class BranchesStaffPage extends StatefulWidget {
  const BranchesStaffPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<BranchesStaffPage> createState() => _BranchesStaffPageState();
}

class _BranchesStaffPageState extends State<BranchesStaffPage> {
  void _openPage(Widget page) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: widget.pageState,
      activeSection: AppDrawerSection.superAdmin,
      title: 'Branches & Staff',
      subtitle: 'Manage branches, assign staff, and record payouts',
      child: BranchesStaffContent(
        pageState: widget.pageState,
        onOpenBranches: () => _openPage(
          BranchDirectoryPage(pageState: widget.pageState),
        ),
        onOpenStaff: () => _openPage(
          StaffAssignmentsPage(pageState: widget.pageState),
        ),
        onOpenPayments: () => _openPage(
          StaffPaymentsPage(pageState: widget.pageState),
        ),
      ),
    );
  }
}

class BranchDirectoryPage extends StatelessWidget {
  const BranchDirectoryPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.superAdmin,
      title: 'Branch Directory',
      subtitle: 'Add, edit, and activate store branches',
      child: BranchesDirectoryContent(pageState: pageState),
    );
  }
}

class StaffAssignmentsPage extends StatelessWidget {
  const StaffAssignmentsPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.superAdmin,
      title: 'Staff & Assignments',
      subtitle: 'Add staff accounts and assign them to branches',
      child: StaffAssignmentsContent(pageState: pageState),
    );
  }
}

class StaffPaymentsPage extends StatelessWidget {
  const StaffPaymentsPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.superAdmin,
      title: 'Staff Payments',
      subtitle: 'Record salary, commission, bonus, or allowance payouts',
      child: StaffPaymentsContent(pageState: pageState),
    );
  }
}

class AuditLogsPage extends StatelessWidget {
  const AuditLogsPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.superAdmin,
      title: 'Audit Logs',
      subtitle: 'Track logins, changes, and privileged actions',
      child: AuditLogsContent(pageState: pageState),
    );
  }
}

class CustomersManagementPage extends StatelessWidget {
  const CustomersManagementPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.customers,
      title: 'Customers & Loyalty',
      subtitle: 'Farmer accounts and loyalty members synced from the server',
      child: CustomersManagementContent(pageState: pageState),
    );
  }
}

class SalesHistoryPage extends StatelessWidget {
  const SalesHistoryPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.salesHistory,
      title: 'Sales History',
      subtitle: 'Completed POS orders including walk-in sales',
      child: SalesHistoryManagementContent(pageState: pageState),
    );
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: widget.pageState,
      activeSection: AppDrawerSection.reports,
      title: 'Reports',
      subtitle: 'Sales summaries, payment breakdowns, and custom analytics',
      scrollBody: false,
      actions: [
        IconButton(
          onPressed: widget.pageState.reloadAnalyticsData,
          tooltip: 'Refresh data',
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: AppColors.green,
                unselectedLabelColor: AppColors.muted,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(
                    height: 48,
                    icon: Icon(Icons.summarize_outlined, size: 20),
                    text: 'Report Overview',
                  ),
                  Tab(
                    height: 48,
                    icon: Icon(Icons.analytics_outlined, size: 20),
                    text: 'Analytical Report',
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ReportsOverviewContent(pageState: widget.pageState),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: AnalyticsReportsContent(pageState: widget.pageState),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SalesLedgerPage extends StatelessWidget {
  const SalesLedgerPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    final currency = pageState.settings.currencySymbol;

    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.salesLedger,
      title: 'Sales Ledger',
      subtitle: 'Chronological sales journal',
      child: TableCard(
        title: 'Ledger Entries',
        columns: const [
          'Date',
          'Order',
          'Customer',
          'Subtotal',
          'VAT',
          'Discount',
          'Total',
        ],
        rows: pageState.salesHistory
            .map(
              (record) => [
                _formatDate(record.createdAt),
                '#${record.orderId}',
                record.customerName,
                formatMoney(currency, record.subtotal),
                formatMoney(currency, record.vat),
                formatMoney(
                  currency,
                  record.discountAmount +
                      record.couponDiscount +
                      record.loyaltyDiscount,
                ),
                formatMoney(currency, record.total),
              ],
            )
            .toList(),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.settings,
      title: 'Settings',
      subtitle: 'Store profile, tax, printer, branch, and POS rules',
      scrollBody: false,
      child: SettingsManagementContent(pageState: pageState),
    );
  }
}

double _todaySalesTotal(List<SalesHistoryRecord> records) {
  final now = DateTime.now();
  return records
      .where(
        (record) =>
            record.createdAt.year == now.year &&
            record.createdAt.month == now.month &&
            record.createdAt.day == now.day,
      )
      .fold<double>(0, (sum, record) => sum + record.total);
}

List<String> _categoryLabels(List<Product> products) {
  final totals = <String, double>{};
  for (final product in products) {
    totals[product.category] = (totals[product.category] ?? 0) + product.price;
  }
  return totals.keys.toList();
}

List<double> _categoryTotals(List<Product> products) {
  final totals = <String, double>{};
  for (final product in products) {
    totals[product.category] = (totals[product.category] ?? 0) + product.price;
  }
  return totals.values.toList();
}

List<String> _recentDayLabels(List<SalesHistoryRecord> records) {
  final grouped = <String, double>{};
  for (final record in records.take(7)) {
    final label = _formatDate(record.createdAt);
    grouped[label] = (grouped[label] ?? 0) + record.total;
  }
  return grouped.keys.toList();
}

List<double> _recentDayTotals(List<SalesHistoryRecord> records) {
  final grouped = <String, double>{};
  for (final record in records.take(7)) {
    final label = _formatDate(record.createdAt);
    grouped[label] = (grouped[label] ?? 0) + record.total;
  }
  return grouped.values.toList();
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}
