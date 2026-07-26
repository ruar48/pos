import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../orders/orders.dart';
import '../../pos/pages/pos_home_page.dart';
import '../../transactions/transaction_model.dart';
import '../../transactions/transaction_service.dart';

class RefundCenterState extends ChangeNotifier {
  RefundCenterState({required this.service});

  final TransactionService service;

  bool isLoading = false;
  String errorMessage = '';
  List<TransactionRecord> orders = [];
  List<RefundRecord> refunds = [];

  Future<void> load() async {
    isLoading = true;
    errorMessage = '';
    notifyListeners();

    try {
      final results = await Future.wait([
        service.fetchTransactions(),
        service.fetchRefunds(),
      ]);
      orders = results[0] as List<TransactionRecord>;
      refunds = results[1] as List<RefundRecord>;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  int get refundableOrderCount => orders.where(_hasRefundableItems).length;

  double get totalRefundedAmount =>
      refunds.fold<double>(0, (sum, refund) => sum + refund.amount);

  bool _hasRefundableItems(TransactionRecord order) {
    if (order.refundedAmount >= order.grandTotal - 0.01) return false;
    return order.items.any((item) => item.hasRefundableQuantity);
  }
}

class RefundCenterContent extends StatelessWidget {
  const RefundCenterContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return Consumer<RefundCenterState>(
      builder: (context, state, child) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.errorMessage.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 40,
                    color: AppColors.muted.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.errorMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: state.load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _RefundStatTile(
                      label: 'Refundable',
                      value: '${state.refundableOrderCount}',
                      hint: 'orders ready',
                      icon: Icons.assignment_return_outlined,
                      accent: AppColors.green,
                      background: AppColors.lightGreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _RefundStatTile(
                      label: 'Total refunded',
                      value: formatMoney('₱', state.totalRefundedAmount),
                      hint: '${state.refunds.length} records',
                      icon: Icons.payments_outlined,
                      accent: AppColors.amber,
                      background: const Color(0xFFFFF6E8),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            _OpenOrdersBanner(
              orderCount: state.orders.length,
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrdersPage(pageState: pageState),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            _RefundHistoryHeader(
              count: state.refunds.length,
              onRefresh: state.load,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: state.refunds.isEmpty
                  ? _EmptyRefundHistory(
                      onOpenOrders: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrdersPage(pageState: pageState),
                          ),
                        );
                      },
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: state.refunds.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _RefundHistoryCard(
                          refund: state.refunds[index],
                          initiallyExpanded: index == 0,
                        );
                      },
                    ),
            ),
            ],
          ),
        );
      },
    );
  }
}

class _RefundStatTile extends StatelessWidget {
  const _RefundStatTile({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.accent,
    required this.background,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color accent;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: accent == AppColors.green
                        ? AppColors.darkGreen
                        : AppColors.text,
                  ),
                ),
                Text(
                  hint,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenOrdersBanner extends StatelessWidget {
  const _OpenOrdersBanner({
    required this.orderCount,
    required this.onTap,
  });

  final int orderCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.green.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.manage_search_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Search & refund orders',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$orderCount completed orders • full or partial refund',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Open',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded,
                          color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RefundHistoryHeader extends StatelessWidget {
  const _RefundHistoryHeader({
    required this.count,
    required this.onRefresh,
  });

  final int count;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, size: 18, color: AppColors.green),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Refund history',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.darkGreen,
              ),
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

class _EmptyRefundHistory extends StatelessWidget {
  const _EmptyRefundHistory({required this.onOpenOrders});

  final VoidCallback onOpenOrders;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 42,
            color: AppColors.muted.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          const Text(
            'No refunds yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Refunds you process from Orders will appear here\nwith item details and amounts.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onOpenOrders,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Go to Orders'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.green,
              minimumSize: const Size(0, 42),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundHistoryCard extends StatefulWidget {
  const _RefundHistoryCard({
    required this.refund,
    this.initiallyExpanded = false,
  });

  final RefundRecord refund;
  final bool initiallyExpanded;

  @override
  State<_RefundHistoryCard> createState() => _RefundHistoryCardState();
}

class _RefundHistoryCardState extends State<_RefundHistoryCard> {
  late bool expanded = widget.initiallyExpanded;

  RefundRecord get refund => widget.refund;

  String get _statusLabel {
    if (refund.orderStatus == 'refunded') return 'Fully refunded';
    if (refund.orderStatus == 'partial_refund') return 'Partial refund';
    return refund.refundType == 'all' ? 'Full refund' : 'Item refund';
  }

  Color get _statusColor {
    if (refund.orderStatus == 'refunded') return AppColors.green;
    return AppColors.amber;
  }

  Color get _statusBackground {
    if (refund.orderStatus == 'refunded') return AppColors.lightGreen;
    return const Color(0xFFFFF6E8);
  }

  @override
  Widget build(BuildContext context) {
    final itemCount =
        refund.items.fold<int>(0, (sum, item) => sum + item.quantity);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: expanded ? AppColors.greenBorder : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => expanded = !expanded),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(16),
                bottom: Radius.circular(expanded ? 0 : 16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _statusBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: _statusColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  refund.receiptNumber,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _statusBackground,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _statusLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: _statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            refund.customerName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${refund.displayTime} • ${refund.paymentMethod} • $itemCount item${itemCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            formatMoney('₱', refund.amount),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.darkGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (refund.reason.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.softSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 16,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              refund.reason,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: AppColors.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (refund.items.isNotEmpty) ...[
                    if (refund.reason.isNotEmpty) const SizedBox(height: 10),
                    Text(
                      'Refunded items (${refund.items.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < refund.items.length; i++)
                            _RefundItemRow(
                              item: refund.items[i],
                              shaded: i.isOdd,
                              showDivider: i < refund.items.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RefundItemRow extends StatelessWidget {
  const _RefundItemRow({
    required this.item,
    required this.shaded,
    required this.showDivider,
  });

  final RefundLineItem item;
  final bool shaded;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: shaded ? AppColors.softSurface : AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${item.quantity}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkGreen,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoney('₱', item.amount),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, thickness: 1),
      ],
    );
  }
}

RefundCenterState createRefundCenterState() {
  final state = RefundCenterState(service: TransactionService(apiBaseUrl));
  state.load();
  return state;
}
