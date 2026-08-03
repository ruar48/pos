import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/top_toast.dart';
import '../pos/pages/pos_home_page.dart';
import '../pos/widgets/app_drawer_section.dart';
import '../pos/widgets/app_shell_scaffold.dart';
import '../receipt/receipt_preview_widget.dart';
import '../receipt/receipt_printer.dart';
import '../transactions/refund_dialog.dart';
import '../transactions/refund_pin_dialog.dart';
import '../transactions/transaction_model.dart';
import '../transactions/transaction_payment_summary.dart';
import '../transactions/transaction_service.dart';
import '../transactions/transactions_screen.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TransactionState>(
      create: (_) {
        final state = TransactionState(
          service: TransactionService(apiBaseUrl),
          actorUserId: pageState.widget.currentUser.id,
        );
        state.loadTransactions();
        return state;
      },
      child: TabletOrdersScreen(pageState: pageState),
    );
  }
}

class TabletOrdersScreen extends StatefulWidget {
  const TabletOrdersScreen({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<TabletOrdersScreen> createState() => _TabletOrdersScreenState();
}

class _TabletOrdersScreenState extends State<TabletOrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.pageState.refreshAppSettings());
    });
  }

  @override
  Widget build(BuildContext context) {
    final pageState = widget.pageState;
    return AppShellScaffold(
      pageState: pageState,
      activeSection: AppDrawerSection.orders,
      title: 'Orders',
      subtitle: 'Look up receipts, reprint, or refund',
      body: Consumer<TransactionState>(
        builder: (context, state, child) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                height: constraints.maxHeight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 340,
                        child: _OrderListPane(state: state),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _OrderDetailPane(
                          state: state,
                          pageState: pageState,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _OrderListPane extends StatefulWidget {
  const _OrderListPane({required this.state});

  final TransactionState state;

  @override
  State<_OrderListPane> createState() => _OrderListPaneState();
}

class _OrderListPaneState extends State<_OrderListPane> {
  late final TextEditingController searchController;

  TransactionState get state => widget.state;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController(text: state.query);
    searchController.addListener(() {
      state.setQuery(searchController.text);
      setState(() {});
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = state.groupedTransactions;
    final visibleCount = state.filteredTransactions.length;
    final todayOrders =
        state.transactions.where((order) => order.isToday).toList();
    final todayTotal = todayOrders.fold<double>(
      0,
      (sum, order) => sum + order.grandTotal,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Orders',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: state.refresh,
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Refresh orders',
                    ),
                  ],
                ),
                Text(
                  visibleCount == state.transactions.length
                      ? '${state.transactions.length} orders'
                      : '$visibleCount of ${state.transactions.length} orders',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _OrderStatChip(
                        label: 'Today',
                        value: '${todayOrders.length} orders',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _OrderStatChip(
                        label: 'Today sales',
                        value: formatMoney('₱', todayTotal),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search order, receipt, or customer...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: searchController.clear,
                            icon: const Icon(Icons.close, size: 18),
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.softSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final option in TransactionFilterType.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(_filterLabel(option)),
                            selected: state.filter == option,
                            onSelected: (_) => state.setFilter(option),
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
          Expanded(
            child: groups.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No orders match your search.',
                        style: TextStyle(color: AppColors.muted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: groups.length,
                    itemBuilder: (context, groupIndex) {
                      final group = groups[groupIndex];
                      return _OrderGroupCard(
                        group: group,
                        selectedOrder: state.selectedTransaction,
                        onSelect: state.select,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _filterLabel(TransactionFilterType type) {
    return switch (type) {
      TransactionFilterType.all => 'All',
      TransactionFilterType.today => 'Today',
      TransactionFilterType.cash => 'Cash',
      TransactionFilterType.card => 'Card',
      TransactionFilterType.refunded => 'Refunded',
    };
  }
}

class _OrderStatChip extends StatelessWidget {
  const _OrderStatChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greenBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.green,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderGroupCard extends StatelessWidget {
  const _OrderGroupCard({
    required this.group,
    required this.selectedOrder,
    required this.onSelect,
  });

  final TransactionGroup group;
  final TransactionRecord? selectedOrder;
  final void Function(TransactionRecord) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            group.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        ...group.transactions.map(
          (order) {
            final isSelected = selectedOrder?.id == order.id;
            return _OrderListItem(
              order: order,
              isSelected: isSelected,
              onTap: () => onSelect(order),
            );
          },
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class _OrderListItem extends StatelessWidget {
  const _OrderListItem({
    required this.order,
    required this.isSelected,
    required this.onTap,
  });

  final TransactionRecord order;
  final bool isSelected;
  final VoidCallback onTap;

  String get _statusLabel {
    if (order.refundedAmount > 0 &&
        order.refundedAmount >= order.grandTotal - 0.01) {
      return 'Refunded';
    }
    if (order.refundedAmount > 0) return 'Partial Refund';
    return 'Completed';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected ? Colors.white : AppColors.text;
    final mutedColor = isSelected ? Colors.white70 : AppColors.muted;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.green : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.green : AppColors.border,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.green.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.receiptNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMoney('₱', order.grandTotal),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  order.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: mutedColor,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      order.displayTime,
                      style: TextStyle(fontSize: 12, color: mutedColor),
                    ),
                    Text(' • ', style: TextStyle(color: mutedColor)),
                    Expanded(
                      child: Text(
                        order.isSplitPayment
                            ? order.paymentSummaryLabel
                            : order.paymentMethod,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              order.isSplitPayment ? FontWeight.w800 : FontWeight.w600,
                          color: order.isSplitPayment
                              ? (isSelected ? Colors.white : AppColors.green)
                              : mutedColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.18)
                            : AppColors.lightGreen,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.white : AppColors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderDetailPane extends StatelessWidget {
  const _OrderDetailPane({
    required this.state,
    required this.pageState,
  });

  final TransactionState state;
  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    final order = state.selectedTransaction;

    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: order == null
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 56,
                      color: AppColors.muted,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Select an order',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Search or select an order to view line items,\nreprint a receipt, or start a refund.',
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${order.paymentMethod}  #${order.id}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      Text(
                        order.displayTime,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.customerName}  •  ${order.cashierName}  •  ${order.receiptNumber}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: _buildReceiptCard(order)),
                  const SizedBox(height: 10),
                  _buildActionButtons(context, order, state),
                ],
              ),
      ),
    );
  }

  Future<void> _handleRefund(
    BuildContext context,
    TransactionState state,
    TransactionRecord transaction,
  ) async {
    final result = await showDialog<RefundDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RefundDialog(
        title: 'Refund Order',
        transactionId: transaction.id,
        actionLabel: 'Refund',
        items: transaction.items,
      ),
    );
    if (result == null) return;
    if (!context.mounted) return;

    String? refundPin;
    if (pageState.settings.hasRefundPin) {
      refundPin = await showRefundPinDialog(context);
      if (refundPin == null) return;
      if (!context.mounted) return;
    }

    final apiResult = await state.refundSelectedTransaction(
      reason: result.reason,
      refundType: result.refundType,
      items: result.items,
      refundPin: refundPin,
    );

    if (!context.mounted) return;

    if (apiResult.success) {
      await pageState.refreshProductCatalog();
      if (!context.mounted) return;
      showTopSuccess(context, apiResult.message);
      await state.refresh();
    } else {
      showTopError(context, apiResult.message);
    }
  }

  Future<void> _handleReprint(
    BuildContext context,
    TransactionState state,
  ) async {
    final apiResult = await state.reprintSelectedTransaction();

    if (!context.mounted) return;

    if (apiResult.success) {
      showTopSuccess(context, apiResult.message);
    } else {
      showTopError(context, apiResult.message);
    }
  }

  Widget _buildReceiptCard(TransactionRecord transaction) {
    final totalDiscount = transaction.discountAmount +
        transaction.couponDiscount +
        transaction.loyaltyDiscount;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatMoney('₱', transaction.grandTotal),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppColors.text,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.greenBorder),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Items',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${transaction.totalQuantity}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: transaction.items.isEmpty
                ? const Center(
                    child: Text(
                      'No items in this order.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    itemCount: transaction.items.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 20,
                      color: AppColors.border,
                    ),
                    itemBuilder: (context, index) {
                      return _OrderLineItemRow(
                        item: transaction.items[index],
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: Column(
              children: [
                _TotalsRow(
                  label: 'Subtotal',
                  value: formatMoney('₱', transaction.subtotal),
                ),
                if (totalDiscount > 0) ...[
                  const SizedBox(height: 4),
                  _TotalsRow(
                    label: 'Discounts',
                    value: '-${formatMoney('₱', totalDiscount)}',
                    valueColor: AppColors.danger,
                  ),
                ],
                if (transaction.vat > 0) ...[
                  const SizedBox(height: 4),
                  _TotalsRow(
                    label: 'VAT',
                    value: formatMoney('₱', transaction.vat),
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 110,
                      child: Text(
                        'Payment',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TransactionPaymentSummary(
                        transaction: transaction,
                        compact: true,
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

  Widget _buildActionButtons(
    BuildContext context,
    TransactionRecord transaction,
    TransactionState state,
  ) {
    final canRefund = transaction.items.any((item) => item.hasRefundableQuantity);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 540;
        return isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ThemedActionButton(
                    label: 'Receipt ${transaction.receiptNumber}',
                    icon: Icons.receipt_long,
                    backgroundColor: AppColors.green,
                    onTap: () => _showReceiptPreviewDialog(
                      context,
                      state,
                      state.selectedTransaction ?? transaction,
                    ),
                  ),
                  if (canRefund) ...[
                    const SizedBox(height: 10),
                    _ThemedActionButton(
                      label: 'Refund',
                      icon: Icons.undo,
                      backgroundColor: AppColors.danger,
                      onTap: () async {
                        await _handleRefund(context, state, transaction);
                      },
                    ),
                  ],
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: _ThemedActionButton(
                      label: 'Receipt ${transaction.receiptNumber}',
                      icon: Icons.receipt_long,
                      backgroundColor: AppColors.green,
                      onTap: () => _showReceiptPreviewDialog(
                        context,
                        state,
                        state.selectedTransaction ?? transaction,
                      ),
                    ),
                  ),
                  if (canRefund) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ThemedActionButton(
                        label: 'Refund',
                        icon: Icons.undo,
                        backgroundColor: AppColors.danger,
                        onTap: () async {
                          await _handleRefund(context, state, transaction);
                        },
                      ),
                    ),
                  ],
                ],
              );
      },
    );
  }

  Future<void> _showReceiptPreviewDialog(
    BuildContext context,
    TransactionState state,
    TransactionRecord transaction,
  ) async {
    final store = await ReceiptStoreConfig.loadFromPrefs();
    final receipt = state.service.buildReceiptData(
      transaction,
      store: store,
    );
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Receipt Preview',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            transaction.receiptNumber,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Center(
                    child: ThermalReceiptPreview(
                      receipt: receipt,
                      usePrintLayout: true,
                      compact: true,
                      fitToContent: true,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 420;
                    return isNarrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton(
                                onPressed: () async {
                                  await _handleReprint(context, state);
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.green,
                                ),
                                child: const Text('Reprint'),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    await _handleReprint(context, state);
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.green,
                                  ),
                                  child: const Text('Reprint'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ),
                            ],
                          );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.muted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: valueColor ?? AppColors.text,
          ),
        ),
      ],
    );
  }
}

class _OrderLineItemRow extends StatelessWidget {
  const _OrderLineItemRow({required this.item});

  final TransactionItem item;

  String get _detailLine {
    final variety = item.varietyName?.trim();
    if (variety != null && variety.isNotEmpty) {
      return variety;
    }

    final sku = item.sku.trim();
    if (sku.isNotEmpty && !sku.startsWith('SKU-')) {
      return sku;
    }

    return '${item.quantity} x ${formatMoney('₱', item.unitPrice)}';
  }

  @override
  Widget build(BuildContext context) {
    final amount = item.subtotal;
    final amountText = amount < 0
        ? '-${formatMoney('₱', amount.abs())}'
        : formatMoney('₱', amount);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName.toUpperCase(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _detailLine,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
              if (item.refundedQuantity > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${item.refundedQuantity} refunded',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          amountText,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: amount < 0 ? AppColors.danger : AppColors.text,
          ),
        ),
      ],
    );
  }
}

class _ThemedActionButton extends StatelessWidget {
  const _ThemedActionButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
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
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
