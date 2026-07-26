import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/sales_history_record.dart';
import '../../pos/pages/pos_home_page.dart';

Future<void> showSalesOrderDetailsDialog(
  BuildContext context, {
  required SalesHistoryRecord record,
  required String currencySymbol,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _SalesOrderDetailsDialog(
      record: record,
      currencySymbol: currencySymbol,
    ),
  );
}

class SalesHistoryManagementContent extends StatefulWidget {
  const SalesHistoryManagementContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<SalesHistoryManagementContent> createState() =>
      _SalesHistoryManagementContentState();
}

class _SalesHistoryManagementContentState
    extends State<SalesHistoryManagementContent> {
  final searchController = TextEditingController();
  String customerFilter = 'All';
  String paymentFilter = 'All';
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<SalesHistoryRecord> get records => widget.pageState.salesHistory;

  String get currency => widget.pageState.settings.currencySymbol;

  List<String> get paymentMethods {
    final methods = records.map((record) => record.paymentMethod).toSet().toList()
      ..sort();
    return ['All', ...methods];
  }

  List<SalesHistoryRecord> get filteredRecords {
    final query = searchController.text.trim().toLowerCase();
    return records.where((record) {
      final matchesCustomer = switch (customerFilter) {
        'Walk-In' => record.isWalkIn,
        'Registered' => !record.isWalkIn,
        _ => true,
      };
      final matchesPayment =
          paymentFilter == 'All' || record.paymentMethod == paymentFilter;
      final matchesSearch = query.isEmpty ||
          record.customerName.toLowerCase().contains(query) ||
          record.paymentMethod.toLowerCase().contains(query) ||
          record.reference.toLowerCase().contains(query) ||
          '#${record.orderId}'.contains(query) ||
          '${record.orderId}'.contains(query);
      return matchesCustomer && matchesPayment && matchesSearch;
    }).toList();
  }

  double get todaySalesTotal {
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

  int get walkInCount => records.where((record) => record.isWalkIn).length;

  int get registeredCount => records.length - walkInCount;

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.pageState.reloadSalesHistory();
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = filteredRecords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final cards = [
              _SalesStatCard(
                label: "Today's Sales",
                value: formatMoney(currency, todaySalesTotal),
                icon: Icons.payments_outlined,
                color: AppColors.green,
              ),
              _SalesStatCard(
                label: 'Total Orders',
                value: '${records.length}',
                icon: Icons.receipt_long_outlined,
                color: AppColors.darkGreen,
              ),
              _SalesStatCard(
                label: 'Walk-In Sales',
                value: '$walkInCount',
                icon: Icons.directions_walk_outlined,
                color: AppColors.amber,
              ),
              _SalesStatCard(
                label: 'Registered Sales',
                value: '$registeredCount',
                icon: Icons.person_outline,
                color: AppColors.green,
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
        Container(
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
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'Search order, customer, payment, reference...',
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
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: refreshing ? null : _refresh,
                    icon: refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.lightGreen,
                      foregroundColor: AppColors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final type in ['All', 'Walk-In', 'Registered'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(type),
                          selected: customerFilter == type,
                          onSelected: (_) =>
                              setState(() => customerFilter = type),
                          selectedColor: AppColors.lightGreen,
                          checkmarkColor: AppColors.green,
                          side: BorderSide(
                            color: customerFilter == type
                                ? AppColors.green
                                : AppColors.border,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    for (final method in paymentMethods.skip(1))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(method),
                          selected: paymentFilter == method,
                          onSelected: (_) =>
                              setState(() => paymentFilter = method),
                          selectedColor: AppColors.lightGreen,
                          checkmarkColor: AppColors.green,
                          side: BorderSide(
                            color: paymentFilter == method
                                ? AppColors.green
                                : AppColors.border,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (orders.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 48, color: AppColors.muted),
                const SizedBox(height: 12),
                Text(
                  records.isEmpty
                      ? 'No sales recorded yet.'
                      : 'No orders match your filters.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  records.isEmpty
                      ? 'Completed POS checkouts will appear here.'
                      : 'Try a different search or filter.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
                if (records.isEmpty) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: refreshing ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ],
            ),
          )
        else
          ...orders.map(
            (record) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SalesOrderTile(
                record: record,
                currencySymbol: currency,
                onTap: () => showSalesOrderDetailsDialog(
                  context,
                  record: record,
                  currencySymbol: currency,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SalesStatCard extends StatelessWidget {
  const _SalesStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
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

class _SalesOrderTile extends StatelessWidget {
  const _SalesOrderTile({
    required this.record,
    required this.currencySymbol,
    required this.onTap,
  });

  final SalesHistoryRecord record;
  final String currencySymbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: record.isWalkIn
                      ? AppColors.softSurface
                      : AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  record.isWalkIn
                      ? Icons.directions_walk_outlined
                      : Icons.receipt_long_outlined,
                  color: record.isWalkIn ? AppColors.muted : AppColors.green,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Order #${record.orderId}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SalesBadge(
                          label: record.isWalkIn ? 'Walk-In' : 'Registered',
                          color: record.isWalkIn
                              ? AppColors.muted
                              : AppColors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.customerName,
                      style: const TextStyle(fontSize: 13, color: AppColors.text),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _SalesBadge(
                          label: record.paymentMethod,
                          color: AppColors.darkGreen,
                        ),
                        _SalesBadge(
                          label: '${record.itemCount} items',
                          color: AppColors.amber,
                        ),
                        if (record.totalDiscount > 0)
                          _SalesBadge(
                            label:
                                'Disc ${formatMoney(currencySymbol, record.totalDiscount)}',
                            color: AppColors.green,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(currencySymbol, record.total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(record.createdAt),
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesOrderDetailsDialog extends StatelessWidget {
  const _SalesOrderDetailsDialog({
    required this.record,
    required this.currencySymbol,
  });

  final SalesHistoryRecord record;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 16, 24),
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              record.isWalkIn
                                  ? Icons.directions_walk_outlined
                                  : Icons.receipt_long_outlined,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Order #${record.orderId}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  record.customerName,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _SalesInfoChip(
                                icon: Icons.payments_outlined,
                                label: 'Payment',
                                value: record.paymentMethod,
                              ),
                              _SalesInfoChip(
                                icon: Icons.calendar_today_outlined,
                                label: 'Date',
                                value: _formatDateTime(record.createdAt),
                              ),
                              _SalesInfoChip(
                                icon: Icons.person_outline,
                                label: 'Customer Type',
                                value:
                                    record.isWalkIn ? 'Walk-In' : 'Registered',
                              ),
                              if (record.reference.isNotEmpty)
                                _SalesInfoChip(
                                  icon: Icons.tag_outlined,
                                  label: 'Reference',
                                  value: record.reference,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Items',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...record.items.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.softSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.productName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            '${item.quantity} x ${formatMoney(currencySymbol, item.price)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      formatMoney(currencySymbol, item.total),
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
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.lightGreen,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.greenBorder),
                            ),
                            child: Column(
                              children: [
                                _SalesTotalRow(
                                  label: 'Subtotal',
                                  value:
                                      formatMoney(currencySymbol, record.subtotal),
                                ),
                                if (record.totalDiscount > 0) ...[
                                  const SizedBox(height: 8),
                                  _SalesTotalRow(
                                    label: 'Discount',
                                    value:
                                        '-${formatMoney(currencySymbol, record.totalDiscount)}',
                                    valueColor: AppColors.amber,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                _SalesTotalRow(
                                  label: 'VAT',
                                  value: formatMoney(currencySymbol, record.vat),
                                ),
                                const Divider(height: 20),
                                _SalesTotalRow(
                                  label: 'Total',
                                  value: formatMoney(currencySymbol, record.total),
                                  emphasized: true,
                                ),
                                if (record.clientChange > 0) ...[
                                  const SizedBox(height: 8),
                                  _SalesTotalRow(
                                    label: 'Change',
                                    value: formatMoney(
                                      currencySymbol,
                                      record.clientChange,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesBadge extends StatelessWidget {
  const _SalesBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _SalesInfoChip extends StatelessWidget {
  const _SalesInfoChip({
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
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.green),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SalesTotalRow extends StatelessWidget {
  const _SalesTotalRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
              fontSize: emphasized ? 15 : 13,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: emphasized ? 18 : 13,
            color: valueColor ?? (emphasized ? AppColors.green : AppColors.text),
          ),
        ),
      ],
    );
  }
}

String _formatDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$month/$day/${value.year} $hour:$minute';
}
