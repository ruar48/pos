import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/accounting_summary.dart';
import '../../pos/pages/pos_home_page.dart';
import '../pages/management_pages.dart';
import 'management_widgets.dart';

enum AccountingPeriodFilter { all, month, today }

extension on AccountingPeriodFilter {
  String get apiValue => switch (this) {
        AccountingPeriodFilter.today => 'today',
        AccountingPeriodFilter.month => 'month',
        AccountingPeriodFilter.all => 'all',
      };

  String get label => switch (this) {
        AccountingPeriodFilter.today => 'Today',
        AccountingPeriodFilter.month => 'This Month',
        AccountingPeriodFilter.all => 'All Time',
      };
}

class AccountingDashboardContent extends StatefulWidget {
  const AccountingDashboardContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<AccountingDashboardContent> createState() =>
      _AccountingDashboardContentState();
}

class _AccountingDashboardContentState extends State<AccountingDashboardContent> {
  AccountingSummary? summary;
  AccountingPeriodFilter period = AccountingPeriodFilter.month;
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final loaded = await widget.pageState.api.fetchAccountingSummary(
        period: period.apiValue,
      );
      await widget.pageState.reloadSalesHistory();
      if (!mounted) return;
      setState(() {
        summary = loaded;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        summary = null;
        loading = false;
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _openSalesLedger() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SalesLedgerPage(pageState: widget.pageState),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.pageState.settings.currencySymbol;
    final data = summary ?? AccountingSummary.empty(period: period.apiValue);

    if (loading && summary == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    errorMessage == null
                        ? '${data.orderCount} orders • ${period.label.toLowerCase()}'
                        : 'Could not load accounting summary',
                    style: TextStyle(
                      color:
                          errorMessage == null ? AppColors.muted : AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                  if (errorMessage == null && period != AccountingPeriodFilter.all) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Today ${formatMoney(currency, data.todayNetSales)} (${data.todayOrderCount}) • '
                      'Month ${formatMoney(currency, data.monthNetSales)} (${data.monthOrderCount})',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : _loadSummary,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(loading ? 'Refreshing...' : 'Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<AccountingPeriodFilter>(
          segments: [
            for (final item in AccountingPeriodFilter.values)
              ButtonSegment(
                value: item,
                label: Text(item.label),
              ),
          ],
          selected: {period},
          onSelectionChanged: loading
              ? null
              : (value) {
                  setState(() => period = value.first);
                  _loadSummary();
                },
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
            ),
            child: Text(
              errorMessage!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SummaryCards(data: data, currency: currency),
        const SizedBox(height: 16),
        AnalyticsTrendChart(
          labels: data.trend.map((point) => point.label).toList(),
          values: data.trend.map((point) => point.total).toList(),
          subtitle: 'Last 7 days net sales (all branches)',
        ),
        const SizedBox(height: 16),
        _DiscountBreakdownSection(data: data, currency: currency),
        const SizedBox(height: 16),
        TableCard(
          title: 'Payment Methods',
          columns: const ['Method', 'Orders', 'Net Sales'],
          rows: data.paymentMethods
              .map(
                (row) => [
                  row.paymentMethod,
                  '${row.orderCount}',
                  formatMoney(currency, row.netTotal),
                ],
              )
              .toList(),
          emptyMessage: 'No payment activity for ${period.label.toLowerCase()}.',
        ),
        const SizedBox(height: 16),
        _RecentOrdersSection(
          data: data,
          currency: currency,
          onViewLedger: _openSalesLedger,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.softSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Text(
            'Accounting shows financial totals for bookkeeping. Use Reports for product, payment, and branch analysis.',
            style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.data, required this.currency});

  final AccountingSummary data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        const minCardWidth = 196.0;
        final columns =
            (constraints.maxWidth / (minCardWidth + spacing)).floor().clamp(1, 5);
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        final cards = [
          SummaryCard(
            label: 'Gross Sales',
            value: formatMoney(currency, data.grossSales),
            icon: Icons.receipt_long_outlined,
            color: AppColors.blue,
            subtitle: 'Before refunds and deductions',
          ),
          SummaryCard(
            label: 'Net Sales After Refunds',
            value: formatMoney(currency, data.netSales),
            icon: Icons.payments_outlined,
            subtitle: data.refundedAmount > 0
                ? 'Gross ${formatMoney(currency, data.grossSales)} less refunds'
                : 'No refunds deducted',
          ),
          SummaryCard(
            label: 'VAT Collected',
            value: formatMoney(currency, data.vatCollected),
            icon: Icons.receipt_outlined,
            color: AppColors.blue,
            subtitle: '${data.orderCount} orders',
          ),
          SummaryCard(
            label: 'Total Discounts',
            value: formatMoney(currency, data.totalDiscounts),
            icon: Icons.percent,
            color: AppColors.orange,
            subtitle: _discountSubtitle(data, currency),
          ),
          SummaryCard(
            label: 'Avg Order',
            value: formatMoney(currency, data.averageOrderValue),
            icon: Icons.shopping_bag_outlined,
            color: AppColors.darkGreen,
            subtitle: '${data.orderCount} orders',
          ),
          SummaryCard(
            label: 'Refunds Deducted',
            value: formatMoney(currency, data.refundedAmount),
            icon: Icons.undo_outlined,
            color: AppColors.danger,
            subtitle: data.refundCount > 0
                ? '${data.refundCount} refunds'
                : 'No refunds in this period',
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }

  String _discountSubtitle(AccountingSummary data, String currency) {
    final parts = <String>[];
    if (data.manualDiscounts > 0) {
      parts.add('Manual ${formatMoney(currency, data.manualDiscounts)}');
    }
    if (data.couponDiscounts > 0) {
      parts.add('Coupon ${formatMoney(currency, data.couponDiscounts)}');
    }
    if (data.loyaltyDiscounts > 0) {
      parts.add('Loyalty ${formatMoney(currency, data.loyaltyDiscounts)}');
    }
    if (parts.isEmpty) {
      return 'No discounts applied';
    }
    return parts.join(' · ');
  }
}

class _DiscountBreakdownSection extends StatelessWidget {
  const _DiscountBreakdownSection({
    required this.data,
    required this.currency,
  });

  final AccountingSummary data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _DiscountRow(
        label: 'Manual Discounts',
        value: data.manualDiscounts,
        color: AppColors.orange,
        currency: currency,
      ),
      _DiscountRow(
        label: 'Coupon Discounts',
        value: data.couponDiscounts,
        color: AppColors.amber,
        currency: currency,
      ),
      _DiscountRow(
        label: 'Loyalty Redemptions',
        value: data.loyaltyDiscounts,
        color: AppColors.green,
        currency: currency,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Discount Breakdown',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Total saved by customers: ${formatMoney(currency, data.totalDiscounts)}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _DiscountRow extends StatelessWidget {
  const _DiscountRow({
    required this.label,
    required this.value,
    required this.color,
    required this.currency,
  });

  final String label;
  final double value;
  final Color color;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          formatMoney(currency, value),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _RecentOrdersSection extends StatelessWidget {
  const _RecentOrdersSection({
    required this.data,
    required this.currency,
    required this.onViewLedger,
  });

  final AccountingSummary data;
  final String currency;
  final VoidCallback onViewLedger;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Transactions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: onViewLedger,
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('Full Ledger'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (data.recentOrders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No transactions for this period.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.softSurface),
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Order')),
                  DataColumn(label: Text('Customer')),
                  DataColumn(label: Text('Payment')),
                  DataColumn(label: Text('Discount')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Status')),
                ],
                rows: [
                  for (final order in data.recentOrders)
                    DataRow(
                      cells: [
                        DataCell(Text(formatShortDate(order.createdAt ?? DateTime.now()))),
                        DataCell(Text('#${order.orderId}')),
                        DataCell(Text(order.customerName)),
                        DataCell(Text(order.paymentMethod)),
                        DataCell(Text(formatMoney(currency, order.discountTotal))),
                        DataCell(Text(formatMoney(currency, order.total))),
                        DataCell(
                          Text(
                            order.statusLabel,
                            style: TextStyle(
                              color: order.status == 'completed'
                                  ? AppColors.green
                                  : AppColors.danger,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
