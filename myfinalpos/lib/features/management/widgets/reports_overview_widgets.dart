import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/sales_history_record.dart';
import '../../../services/analytics_engine.dart';
import '../../pos/pages/pos_home_page.dart';
import 'management_widgets.dart';
import 'report_visual_widgets.dart';

enum ReportsOverviewPeriod { today, month, all }

extension on ReportsOverviewPeriod {
  String get label => switch (this) {
        ReportsOverviewPeriod.today => 'Today',
        ReportsOverviewPeriod.month => 'This Month',
        ReportsOverviewPeriod.all => 'All Time',
      };
}

class ReportsOverviewContent extends StatefulWidget {
  const ReportsOverviewContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<ReportsOverviewContent> createState() => _ReportsOverviewContentState();
}

class _ReportsOverviewContentState extends State<ReportsOverviewContent> {
  ReportsOverviewPeriod period = ReportsOverviewPeriod.month;
  bool refreshing = false;

  String get currency => widget.pageState.settings.currencySymbol;

  Map<int, String> get branchNames => {
        for (final branch in widget.pageState.branches) branch.id: branch.name,
      };

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.pageState.reloadAnalyticsData();
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  AnalyticsDateRange _rangeForPeriod(List<SalesHistoryRecord> records) {
    switch (period) {
      case ReportsOverviewPeriod.today:
        return AnalyticsEngine.rangeForPreset(AnalyticsPeriodPreset.today);
      case ReportsOverviewPeriod.month:
        return AnalyticsEngine.rangeForPreset(AnalyticsPeriodPreset.thisMonth);
      case ReportsOverviewPeriod.all:
        if (records.isEmpty) {
          return AnalyticsEngine.rangeForPreset(AnalyticsPeriodPreset.thisMonth);
        }
        final sorted = [...records]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return AnalyticsDateRange(
          start: sorted.first.createdAt,
          end: sorted.last.createdAt,
          label: 'All Time',
        );
    }
  }

  AnalyticsPeriodPreset? get _comparePresetA => switch (period) {
        ReportsOverviewPeriod.today => AnalyticsPeriodPreset.today,
        ReportsOverviewPeriod.month => AnalyticsPeriodPreset.thisMonth,
        ReportsOverviewPeriod.all => null,
      };

  AnalyticsPeriodPreset? get _comparePresetB => switch (period) {
        ReportsOverviewPeriod.today => AnalyticsPeriodPreset.yesterday,
        ReportsOverviewPeriod.month => AnalyticsPeriodPreset.lastMonth,
        ReportsOverviewPeriod.all => null,
      };

  @override
  Widget build(BuildContext context) {
    final records = widget.pageState.salesHistory;
    final range = _rangeForPeriod(records);
    final filtered = period == ReportsOverviewPeriod.all
        ? records
        : AnalyticsEngine.filterRecords(records: records, range: range);
    final summary = AnalyticsEngine.summarize(filtered);
    final totalVat =
        filtered.fold<double>(0, (sum, record) => sum + record.vat);
    final totalSubtotal =
        filtered.fold<double>(0, (sum, record) => sum + record.subtotal);
    final manualDiscounts = filtered.fold<double>(
      0,
      (sum, record) => sum + record.discountAmount,
    );
    final couponDiscounts = filtered.fold<double>(
      0,
      (sum, record) => sum + record.couponDiscount,
    );
    final loyaltyDiscounts = filtered.fold<double>(
      0,
      (sum, record) => sum + record.loyaltyDiscount,
    );
    final granularity = AnalyticsEngine.granularityForRange(range);
    final trend = AnalyticsEngine.salesTrend(
      records: filtered,
      granularity: granularity,
      range: range,
    );
    final payments = AnalyticsEngine.paymentBreakdown(filtered);
    final categories = AnalyticsEngine.salesByCategory(
      records: filtered,
      products: widget.pageState.products,
    );
    final topProducts = AnalyticsEngine.bestSellers(records: filtered, limit: 10);
    final topByRevenue = AnalyticsEngine.bestSellers(
      records: filtered,
      limit: 10,
      byRevenue: true,
    );
    final branchSales = AnalyticsEngine.salesByBranch(
      records: filtered,
      branchNames: branchNames,
    );
    final customerMix = AnalyticsEngine.customerTypeBreakdown(filtered);
    final recent = [...filtered]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    AnalyticsComparisonResult? periodComparison;
    final presetA = _comparePresetA;
    final presetB = _comparePresetB;
    if (presetA != null && presetB != null) {
      periodComparison = AnalyticsEngine.comparePeriods(
        records: records,
        rangeA: AnalyticsEngine.rangeForPreset(presetA),
        rangeB: AnalyticsEngine.rangeForPreset(presetB),
      );
    }

    AnalyticsComparisonResult? branchComparison;
    final branches = widget.pageState.branches;
    if (branches.length >= 2) {
      branchComparison = AnalyticsEngine.compareBranches(
        records: records,
        range: range,
        branchIdA: branches[0].id,
        branchIdB: branches[1].id,
        branchNameA: branches[0].name,
        branchNameB: branches[1].name,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverviewHero(
          periodLabel: period.label,
          orderCount: summary.orderCount,
          totalSales: summary.totalSales,
          currency: currency,
          refreshing: refreshing,
          onRefresh: _refresh,
        ),
        const SizedBox(height: 16),
        SegmentedButton<ReportsOverviewPeriod>(
          segments: const [
            ButtonSegment(
              value: ReportsOverviewPeriod.all,
              label: Text('All Time'),
            ),
            ButtonSegment(
              value: ReportsOverviewPeriod.month,
              label: Text('This Month'),
            ),
            ButtonSegment(
              value: ReportsOverviewPeriod.today,
              label: Text('Today'),
            ),
          ],
          selected: {period},
          onSelectionChanged: (value) =>
              setState(() => period = value.first),
        ),
        const SizedBox(height: 16),
        _SummaryCardsGrid(
          currency: currency,
          summary: summary,
          totalVat: totalVat,
          totalSubtotal: totalSubtotal,
          totalDiscounts: summary.totalDiscount,
        ),
        const SizedBox(height: 16),
        ReportVisualsSection(
          periodLabel: period.label,
          range: range,
          records: filtered,
          currency: currency,
        ),
        const SizedBox(height: 16),
        _DiscountBreakdownCard(
          currency: currency,
          manual: manualDiscounts,
          coupon: couponDiscounts,
          loyalty: loyaltyDiscounts,
          total: summary.totalDiscount,
        ),
        if (periodComparison != null) ...[
          const SizedBox(height: 16),
          _PeriodComparisonCard(
            currency: currency,
            comparison: periodComparison,
          ),
        ],
        const SizedBox(height: 16),
        AnalyticsTrendChart(
          labels: trend.map((point) => point.label).toList(),
          values: trend.map((point) => point.value).toList(),
          subtitle:
              '${AnalyticsEngine.chartTitleForGranularity(granularity)} • ${AnalyticsEngine.rangeDescription(range)}',
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final paymentTable = TableCard(
              title: 'Payment Methods',
              columns: const ['Method', 'Orders', 'Sales'],
              rows: _paymentRows(filtered, currency),
              emptyMessage: 'No payment data for ${period.label.toLowerCase()}.',
            );
            final customerTable = TableCard(
              title: 'Customer Mix',
              columns: const ['Type', 'Orders', 'Sales'],
              rows: [
                [
                  'Walk-In',
                  '${summary.walkInOrders}',
                  formatMoney(currency, customerMix.first.value),
                ],
                [
                  'Registered',
                  '${summary.registeredOrders}',
                  formatMoney(currency, customerMix.last.value),
                ],
              ],
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: paymentTable),
                  const SizedBox(width: 16),
                  Expanded(child: customerTable),
                ],
              );
            }

            return Column(
              children: [
                paymentTable,
                const SizedBox(height: 16),
                customerTable,
              ],
            );
          },
        ),
        if (payments.isNotEmpty) ...[
          const SizedBox(height: 16),
          AnalyticsBarChart(
            title: 'Payment Split',
            labels: payments.map((row) => row.label).toList(),
            values: payments.map((row) => row.value).toList(),
            currencySymbol: currency,
            barColor: AppColors.green,
          ),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final topQty = TableCard(
              title: 'Top Products by Quantity',
              columns: const ['Product', 'Qty Sold', 'Revenue'],
              rows: topProducts
                  .map(
                    (item) => [
                      item.label,
                      '${item.secondary ?? item.value.toInt()}',
                      formatMoney(currency, _revenueForProduct(topByRevenue, item.label)),
                    ],
                  )
                  .toList(),
              emptyMessage: 'No product sales for ${period.label.toLowerCase()}.',
            );
            final topRev = TableCard(
              title: 'Top Products by Revenue',
              columns: const ['Product', 'Revenue', 'Qty Sold'],
              rows: topByRevenue
                  .map(
                    (item) => [
                      item.label,
                      formatMoney(currency, item.value),
                      '${item.secondary ?? 0}',
                    ],
                  )
                  .toList(),
              emptyMessage: 'No product sales for ${period.label.toLowerCase()}.',
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: topQty),
                  const SizedBox(width: 16),
                  Expanded(child: topRev),
                ],
              );
            }

            return Column(
              children: [
                topQty,
                const SizedBox(height: 16),
                topRev,
              ],
            );
          },
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 16),
          AnalyticsBarChart(
            title: 'Sales by Category',
            labels: categories.map((row) => row.label).toList(),
            values: categories.map((row) => row.value).toList(),
            currencySymbol: currency,
            barColor: AppColors.darkGreen,
          ),
          const SizedBox(height: 16),
          TableCard(
            title: 'Category Breakdown',
            columns: const ['Category', 'Sales'],
            rows: categories
                .map((row) => [row.label, formatMoney(currency, row.value)])
                .toList(),
          ),
        ],
        if (branchSales.length > 1) ...[
          const SizedBox(height: 16),
          AnalyticsBarChart(
            title: 'Sales by Branch',
            labels: branchSales.map((row) => row.label).toList(),
            values: branchSales.map((row) => row.value).toList(),
            currencySymbol: currency,
            barColor: AppColors.blue,
          ),
          const SizedBox(height: 16),
          TableCard(
            title: 'Branch Performance',
            columns: const ['Branch', 'Sales'],
            rows: branchSales
                .map((row) => [row.label, formatMoney(currency, row.value)])
                .toList(),
          ),
        ],
        if (branchComparison != null) ...[
          const SizedBox(height: 16),
          _BranchComparisonCard(
            currency: currency,
            comparison: branchComparison,
          ),
        ],
        const SizedBox(height: 16),
        _RecentTransactionsCard(
          currency: currency,
          records: recent.take(10).toList(),
          periodLabel: period.label,
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
            'Overview shows POS sales snapshots from loaded history. Use Analytical Report for custom date ranges, filters, and detailed comparisons.',
            style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _OverviewHero extends StatelessWidget {
  const _OverviewHero({
    required this.periodLabel,
    required this.orderCount,
    required this.totalSales,
    required this.currency,
    required this.refreshing,
    required this.onRefresh,
  });

  final String periodLabel;
  final int orderCount;
  final double totalSales;
  final String currency;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.summarize_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sales Overview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$periodLabel • $orderCount orders • ${formatMoney(currency, totalSales)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroChip(
                icon: Icons.receipt_long_outlined,
                label: 'Period',
                value: periodLabel,
              ),
              _HeroChip(
                icon: Icons.shopping_bag_outlined,
                label: 'Orders',
                value: '$orderCount',
              ),
              _HeroChip(
                icon: Icons.payments_outlined,
                label: 'Net Sales',
                value: formatMoney(currency, totalSales),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCardsGrid extends StatelessWidget {
  const _SummaryCardsGrid({
    required this.currency,
    required this.summary,
    required this.totalVat,
    required this.totalSubtotal,
    required this.totalDiscounts,
  });

  final String currency;
  final AnalyticsSummary summary;
  final double totalVat;
  final double totalSubtotal;
  final double totalDiscounts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        const minCardWidth = 196.0;
        final columns =
            (constraints.maxWidth / (minCardWidth + spacing)).floor().clamp(1, 3);
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        final cards = [
          SummaryCard(
            label: 'Net Sales',
            value: formatMoney(currency, summary.totalSales),
            icon: Icons.payments_outlined,
            subtitle: 'Subtotal ${formatMoney(currency, totalSubtotal)}',
          ),
          SummaryCard(
            label: 'Orders',
            value: '${summary.orderCount}',
            icon: Icons.receipt_long_outlined,
            color: AppColors.darkGreen,
            subtitle: '${summary.itemCount} items sold',
          ),
          SummaryCard(
            label: 'Avg Ticket',
            value: formatMoney(currency, summary.averageTicket),
            icon: Icons.trending_up,
            color: AppColors.blue,
            subtitle: '${summary.orderCount} transactions',
          ),
          SummaryCard(
            label: 'VAT Collected',
            value: formatMoney(currency, totalVat),
            icon: Icons.receipt_outlined,
            color: AppColors.blue,
            subtitle: '${summary.orderCount} orders',
          ),
          SummaryCard(
            label: 'Discounts',
            value: formatMoney(currency, totalDiscounts),
            icon: Icons.percent,
            color: AppColors.orange,
            subtitle: summary.totalDiscount > 0 ? 'Applied on sales' : 'None applied',
          ),
          SummaryCard(
            label: 'Customers',
            value: '${summary.registeredOrders} reg.',
            icon: Icons.people_outline,
            color: AppColors.amber,
            subtitle: '${summary.walkInOrders} walk-in orders',
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
}

class _DiscountBreakdownCard extends StatelessWidget {
  const _DiscountBreakdownCard({
    required this.currency,
    required this.manual,
    required this.coupon,
    required this.loyalty,
    required this.total,
  });

  final String currency;
  final double manual;
  final double coupon;
  final double loyalty;
  final double total;

  @override
  Widget build(BuildContext context) {
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
            'Total saved: ${formatMoney(currency, total)}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          _DiscountRow(
            label: 'Manual Discounts',
            value: formatMoney(currency, manual),
            color: AppColors.orange,
          ),
          const SizedBox(height: 10),
          _DiscountRow(
            label: 'Coupon Discounts',
            value: formatMoney(currency, coupon),
            color: AppColors.amber,
          ),
          const SizedBox(height: 10),
          _DiscountRow(
            label: 'Loyalty Redemptions',
            value: formatMoney(currency, loyalty),
            color: AppColors.green,
          ),
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
  });

  final String label;
  final String value;
  final Color color;

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
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w800, color: color),
        ),
      ],
    );
  }
}

class _PeriodComparisonCard extends StatelessWidget {
  const _PeriodComparisonCard({
    required this.currency,
    required this.comparison,
  });

  final String currency;
  final AnalyticsComparisonResult comparison;

  @override
  Widget build(BuildContext context) {
    final change = comparison.changePercent;
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
            'Period Comparison',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${comparison.labelA} vs ${comparison.labelB}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SummaryCard(
                  label: comparison.labelA,
                  value: formatMoney(currency, comparison.summaryA.totalSales),
                  icon: Icons.filter_1_outlined,
                  color: AppColors.green,
                  subtitle: '${comparison.summaryA.orderCount} orders',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SummaryCard(
                  label: comparison.labelB,
                  value: formatMoney(currency, comparison.summaryB.totalSales),
                  icon: Icons.filter_2_outlined,
                  color: AppColors.blue,
                  subtitle: '${comparison.summaryB.orderCount} orders',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SummaryCard(
                  label: 'Change',
                  value: '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                  icon: Icons.compare_arrows,
                  color: change >= 0 ? AppColors.green : AppColors.danger,
                  subtitle: 'Sales vs prior period',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BranchComparisonCard extends StatelessWidget {
  const _BranchComparisonCard({
    required this.currency,
    required this.comparison,
  });

  final String currency;
  final AnalyticsComparisonResult comparison;

  @override
  Widget build(BuildContext context) {
    final change = comparison.changePercent;
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
            'Branch Sales Comparison',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${comparison.labelA} vs ${comparison.labelB}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SummaryCard(
                  label: comparison.labelA,
                  value: formatMoney(currency, comparison.summaryA.totalSales),
                  icon: Icons.store_outlined,
                  color: AppColors.green,
                  subtitle: '${comparison.summaryA.orderCount} orders',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SummaryCard(
                  label: comparison.labelB,
                  value: formatMoney(currency, comparison.summaryB.totalSales),
                  icon: Icons.store_outlined,
                  color: AppColors.blue,
                  subtitle: '${comparison.summaryB.orderCount} orders',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SummaryCard(
                  label: 'Difference',
                  value: '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                  icon: Icons.compare_arrows,
                  color: change >= 0 ? AppColors.green : AppColors.danger,
                  subtitle: 'Branch sales gap',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentTransactionsCard extends StatelessWidget {
  const _RecentTransactionsCard({
    required this.currency,
    required this.records,
    required this.periodLabel,
  });

  final String currency;
  final List<SalesHistoryRecord> records;
  final String periodLabel;

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
          Text(
            'Recent Transactions',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Latest orders for $periodLabel',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No transactions for ${periodLabel.toLowerCase()}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
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
                  DataColumn(label: Text('Items')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Status')),
                ],
                rows: [
                  for (final record in records)
                    DataRow(
                      cells: [
                        DataCell(Text(_formatShortDate(record.createdAt))),
                        DataCell(Text('#${record.orderId}')),
                        DataCell(Text(record.customerName)),
                        DataCell(Text(record.paymentMethod)),
                        DataCell(Text('${record.itemCount}')),
                        DataCell(Text(formatMoney(currency, record.total))),
                        DataCell(
                          Text(
                            record.status,
                            style: TextStyle(
                              color: record.status == 'completed'
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

List<List<String>> _paymentRows(
  List<SalesHistoryRecord> records,
  String currency,
) {
  final grouped = <String, List<SalesHistoryRecord>>{};
  for (final record in records) {
    final method =
        record.paymentMethod.trim().isEmpty ? 'Cash' : record.paymentMethod;
    grouped.putIfAbsent(method, () => []).add(record);
  }

  final entries = grouped.entries.toList()
    ..sort(
      (a, b) => b.value
          .fold<double>(0, (sum, item) => sum + item.total)
          .compareTo(a.value.fold<double>(0, (sum, item) => sum + item.total)),
    );

  return entries
      .map(
        (entry) => [
          entry.key,
          '${entry.value.length}',
          formatMoney(
            currency,
            entry.value.fold<double>(0, (sum, item) => sum + item.total),
          ),
        ],
      )
      .toList();
}

double _revenueForProduct(List<AnalyticsNamedValue> byRevenue, String name) {
  for (final item in byRevenue) {
    if (item.label == name) return item.value;
  }
  return 0;
}

String _formatShortDate(DateTime value) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}
