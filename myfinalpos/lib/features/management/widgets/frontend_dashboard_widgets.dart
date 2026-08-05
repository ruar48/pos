import 'package:flutter/material.dart';

import '../../../core/theme/agri_admin_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/top_toast.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/product.dart';
import '../../../models/sales_history_record.dart';
import '../../pos/pages/pos_home_page.dart';
import 'management_widgets.dart';
import 'sales_history_management_widgets.dart';

class FrontendDashboardContent extends StatefulWidget {
  const FrontendDashboardContent({
    super.key,
    required this.pageState,
    required this.onOpenOrders,
    required this.onOpenSalesHistory,
    required this.onOpenInventory,
    required this.onOpenCustomers,
    required this.onReturnToRegister,
  });

  final PosHomePageState pageState;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenSalesHistory;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenCustomers;
  final VoidCallback onReturnToRegister;

  @override
  State<FrontendDashboardContent> createState() =>
      _FrontendDashboardContentState();
}

class _FrontendDashboardContentState extends State<FrontendDashboardContent> {
  bool refreshing = false;

  String get currency => widget.pageState.settings.currencySymbol;

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.pageState.reloadDashboardData();
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _formatSyncedAt(List<SalesHistoryRecord> records) {
    if (records.isEmpty) return 'No transactions yet';
    final latest = records.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    return formatDateTime(latest.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final pageState = widget.pageState;
    final dashboardSales = pageState.salesHistoryForDashboard();
    final today = _recordsForToday(dashboardSales);
    final todaySales =
        today.fold<double>(0, (sum, record) => sum + record.total);
    final todayDiscounts = today.fold<double>(
      0,
      (sum, record) =>
          sum +
          record.discountAmount +
          record.couponDiscount +
          record.loyaltyDiscount,
    );
    final todayItems = today.fold<double>(
      0,
      (sum, record) =>
          sum + record.items.fold<double>(0, (s, item) => s + item.quantity),
    );
    final avgOrder = today.isEmpty ? 0.0 : todaySales / today.length;
    final lowStock = pageState.products.where(_isLowStock).toList();
    final paymentRows = _paymentBreakdownForToday(today, currency);
    final trendLabels = _recentDayLabels(dashboardSales);
    final trendValues = _recentDayTotals(dashboardSales, trendLabels);
    final storeName =
        (pageState.settings.receiptStore?['store_name'] ?? 'Agriculture POS')
            .toString()
            .trim();

    final rowOne = [
      DashboardKpiCard(
        label: 'Total Net Sales',
        value: formatMoney(currency, todaySales),
        tone: AgriKpiTone.orange,
      ),
      DashboardKpiCard(
        label: 'Total Discounts',
        value: formatMoney(currency, todayDiscounts),
        tone: AgriKpiTone.teal,
      ),
      DashboardKpiCard(
        label: 'No. of Transactions',
        value: '${today.length}',
        tone: AgriKpiTone.green,
      ),
      DashboardKpiCard(
        label: 'Average Order',
        value: formatMoney(currency, avgOrder),
        tone: AgriKpiTone.orange,
      ),
      DashboardKpiCard(
        label: 'No. of Items',
        value: formatQuantity(todayItems),
        tone: AgriKpiTone.teal,
      ),
    ];

    final rowTwo = [
      DashboardKpiCard(
        label: 'Products',
        value: '${pageState.products.length}',
        tone: AgriKpiTone.orange,
      ),
      DashboardKpiCard(
        label: 'Low Stock',
        value: '${lowStock.length}',
        tone: AgriKpiTone.green,
      ),
      DashboardKpiCard(
        label: 'Walk-In Today',
        value: '${today.where((r) => r.isWalkIn).length}',
        tone: AgriKpiTone.orange,
      ),
      DashboardKpiCard(
        label: 'Registered Today',
        value: '${today.where((r) => !r.isWalkIn).length}',
        tone: AgriKpiTone.coral,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.help_outline,
                      size: 16,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Text(
                  'Last synced: ${_formatSyncedAt(dashboardSales)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onReturnToRegister,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.point_of_sale, size: 16),
                label: const Text('POS'),
              ),
              IconButton(
                onPressed: refreshing ? null : _refresh,
                tooltip: 'Refresh',
                icon: refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 1200
                ? 5
                : constraints.maxWidth >= 700
                    ? 3
                    : 2;
            final itemWidth =
                (constraints.maxWidth - (cols - 1) * 12) / cols;
            return Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final card in rowOne)
                      SizedBox(width: itemWidth, child: card),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final card in rowTwo)
                      SizedBox(
                        width: (constraints.maxWidth - 36) / 4,
                        child: card,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Text(
          '${_greeting()}, ${storeName.toUpperCase()}!',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final chartSection = AgriCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Sales by Date',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DashboardSalesChart(
                    labels: trendLabels,
                    values: trendValues,
                  ),
                ],
              ),
            );

            final paymentSection = AgriCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Payment Types',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (paymentRows.isEmpty)
                    const Text(
                      'No payments recorded.',
                      style: TextStyle(color: AppColors.muted, fontSize: 14),
                    )
                  else
                    ...paymentRows.map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            _PaymentIcon(method: row[0]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                row[0],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Text(
                              row[2],
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );

            if (isWide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: chartSection),
                    const SizedBox(width: 16),
                    SizedBox(width: 260, child: paymentSection),
                  ],
                ),
              );
            }

            return Column(
              children: [
                chartSection,
                const SizedBox(height: 16),
                paymentSection,
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Orders',
                description: 'Look up receipts, reprint, or process refunds.',
                icon: Icons.receipt_long_outlined,
                badge: '${pageState.salesHistory.length}',
                onTap: widget.onOpenOrders,
              ),
            ),
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Sales History',
                description: 'Review sales trends and daily totals.',
                icon: Icons.history,
                badge: '${pageState.salesHistory.length}',
                onTap: widget.onOpenSalesHistory,
              ),
            ),
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Inventory Alerts',
                description: 'Check products that need replenishment.',
                icon: Icons.warehouse_outlined,
                badge: '${lowStock.length} low',
                onTap: widget.onOpenInventory,
              ),
            ),
            SizedBox(
              width: 260,
              child: ModuleOverviewCard(
                title: 'Customers',
                description: 'Registered farmers and loyalty members.',
                icon: Icons.people_outline,
                badge: '${pageState.customers.length}',
                onTap: widget.onOpenCustomers,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _RecentTodaySalesCard(
          records: today.take(6).toList(),
          currencySymbol: currency,
          onViewAll: widget.onOpenSalesHistory,
        ),
        if (lowStock.isNotEmpty) ...[
          const SizedBox(height: 16),
          _LowStockCard(
            products: lowStock.take(5).toList(),
            currencySymbol: currency,
            onManage: widget.onOpenInventory,
          ),
        ],
      ],
    );
  }
}

class _DashboardSalesChart extends StatelessWidget {
  const _DashboardSalesChart({
    required this.labels,
    required this.values,
  });

  final List<String> labels;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty || values.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'No sales in this period.',
            style: TextStyle(color: AppColors.muted, fontSize: 14),
          ),
        ),
      );
    }

    final maxValue = values.fold<double>(0, (a, b) => a > b ? a : b);
    final chartMax = maxValue <= 0 ? 1.0 : maxValue;

    return SizedBox(
      height: 200,
      child: CustomPaint(
        painter: _DashboardTrendPainter(
          values: values,
          maxValue: chartMax,
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              for (final label in labels)
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardTrendPainter extends CustomPainter {
  _DashboardTrendPainter({
    required this.values,
    required this.maxValue,
  });

  final List<double> values;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || maxValue == 0) return;

    final areaPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x59F5A962), Color(0x05F5A962)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height - 24));

    final linePaint = Paint()
      ..color = const Color(0xFFE8924A)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final areaPath = Path();
    final bottom = size.height - 24;

    for (var index = 0; index < values.length; index++) {
      final x = (size.width / (values.length - 1)) * index;
      final y = bottom - ((values[index] / maxValue) * (bottom - 12));
      if (index == 0) {
        path.moveTo(x, y);
        areaPath.moveTo(x, bottom);
        areaPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        areaPath.lineTo(x, y);
      }
    }

    areaPath.lineTo(size.width, bottom);
    areaPath.close();
    canvas.drawPath(areaPath, areaPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _DashboardTrendPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.maxValue != maxValue;
  }
}

class _PaymentIcon extends StatelessWidget {
  const _PaymentIcon({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final lower = method.toLowerCase();
    late Color bg;
    late Color fg;
    late IconData icon;

    if (lower.contains('cash')) {
      bg = const Color(0xFFD1FAE5);
      fg = const Color(0xFF059669);
      icon = Icons.account_balance_wallet_outlined;
    } else if (lower.contains('bank') || lower.contains('gcash')) {
      bg = const Color(0xFFFFEDD5);
      fg = const Color(0xFFEA580C);
      icon = Icons.payments_outlined;
    } else {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF475569);
      icon = Icons.shopping_bag_outlined;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 16, color: fg),
    );
  }
}

class _RecentTodaySalesCard extends StatelessWidget {
  const _RecentTodaySalesCard({
    required this.records,
    required this.currencySymbol,
    required this.onViewAll,
  });

  final List<SalesHistoryRecord> records;
  final String currencySymbol;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return AgriCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Today's Recent Sales",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(onPressed: onViewAll, child: const Text('View All')),
            ],
          ),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No sales completed today yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            ...records.map(
              (record) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.softSurface,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => showSalesOrderDetailsDialog(
                      context,
                      record: record,
                      currencySymbol: currencySymbol,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            record.isWalkIn
                                ? Icons.directions_walk_outlined
                                : Icons.receipt_long_outlined,
                            color: record.isWalkIn
                                ? AppColors.muted
                                : AppColors.green,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Order #${record.orderId}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${record.customerName} • ${record.paymentMethod}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatMoney(currencySymbol, record.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({
    required this.products,
    required this.currencySymbol,
    required this.onManage,
  });

  final List<Product> products;
  final String currencySymbol;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return AgriCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_outlined, color: AppColors.orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Low Stock Alerts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(onPressed: onManage, child: const Text('Manage')),
            ],
          ),
          const SizedBox(height: 10),
          ...products.map(
            (product) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${formatQuantity(product.stock ?? 0)} left',
                    style: const TextStyle(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatMoney(currencySymbol, product.price),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _isLowStock(Product product) {
  final stock = product.stock;
  return stock != null && stock <= 5;
}

List<SalesHistoryRecord> _recordsForToday(List<SalesHistoryRecord> records) {
  final now = DateTime.now();
  return records
      .where(
        (record) =>
            record.createdAt.year == now.year &&
            record.createdAt.month == now.month &&
            record.createdAt.day == now.day,
      )
      .toList();
}

List<List<String>> _paymentBreakdownForToday(
  List<SalesHistoryRecord> today,
  String currency,
) {
  final grouped = <String, List<SalesHistoryRecord>>{};
  for (final record in today) {
    grouped.putIfAbsent(record.paymentMethod, () => []).add(record);
  }

  return grouped.entries
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

List<String> _recentDayLabels(List<SalesHistoryRecord> records) {
  final now = DateTime.now();
  return List.generate(7, (index) {
    final day = now.subtract(Duration(days: 6 - index));
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '$month/$date';
  });
}

List<double> _recentDayTotals(
  List<SalesHistoryRecord> records,
  List<String> labels,
) {
  final grouped = <String, double>{};
  for (final label in labels) {
    grouped[label] = 0;
  }

  for (final record in records) {
    final month = record.createdAt.month.toString().padLeft(2, '0');
    final day = record.createdAt.day.toString().padLeft(2, '0');
    final label = '$month/$day';
    if (grouped.containsKey(label)) {
      grouped[label] = (grouped[label] ?? 0) + record.total;
    }
  }

  return labels.map((label) => grouped[label] ?? 0).toList();
}
