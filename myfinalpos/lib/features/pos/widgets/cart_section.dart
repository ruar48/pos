import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/cart_item.dart';
import '../../../models/customer.dart';
import '../../../models/loyalty_card.dart';
import '../pages/pos_home_page.dart';
import 'order_total_panel.dart';
import 'quantity_entry_dialog.dart';
import 'rfid_customer_scan_dialog.dart';

class CartSection extends StatelessWidget {
  const CartSection({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomerBar(pageState: pageState),
          Expanded(
            child: pageState.cart.isEmpty
                ? EmptyCart(pageState: pageState)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: pageState.cart.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: 12,
                      endIndent: 12,
                      color: AppColors.border,
                    ),
                    itemBuilder: (context, index) {
                      return CartListTile(
                        item: pageState.cart[index],
                        currencySymbol: pageState.settings.currencySymbol,
                        canIncrement: pageState.canIncreaseCartQuantity(
                          pageState.cart[index],
                        ),
                        onIncrement: () => pageState.updateQuantity(
                          pageState.cart[index],
                          1,
                        ),
                        onDecrement: () => pageState.updateQuantity(
                          pageState.cart[index],
                          -1,
                        ),
                        onEditQuantity: () => openPosQuantityEditor(
                          context,
                          pageState,
                          product: pageState.cart[index].product,
                          variety: pageState.cart[index].variety,
                        ),
                        onRemove: () => pageState.removeItem(pageState.cart[index]),
                      );
                    },
                  ),
          ),
          OrderTotalPanel(pageState: pageState, compact: true),
          _CartActionButtons(pageState: pageState),
        ],
      ),
    );
  }
}

class EmptyCart extends StatelessWidget {
  const EmptyCart({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined,
              size: 56, color: AppColors.muted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text(
            'Cart is empty',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap products to add items',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class CustomerBar extends StatelessWidget {
  const CustomerBar({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    final customer = pageState.selectedCustomer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.lightGreen,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer?.displayName ?? 'Walk In Farmer',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${pageState.orderType}${customer?.tableName.isNotEmpty == true ? ' • ${customer!.tableName}' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                if (customer != null &&
                    pageState.loyaltyCardFor(customer) != null)
                  Text(
                    '${pageState.loyaltyCardFor(customer)!.points} loyalty pts',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.darkGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Scan RFID loyalty card',
            onPressed: () => showRfidCustomerScanDialog(context, pageState),
            icon: const Icon(Icons.sensors, color: AppColors.green),
          ),
          IconButton(
            tooltip: 'Add / Change Customer',
            onPressed: () => showAddCustomerDialog(context, pageState),
            icon: const Icon(Icons.edit_outlined),
          ),
          if (customer != null)
            IconButton(
              tooltip: 'Clear Customer',
              onPressed: pageState.resetCustomer,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

Future<void> showAddCustomerDialog(
  BuildContext context,
  PosHomePageState pageState,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AddCustomerDialog(pageState: pageState),
  );
}

class AddCustomerDialog extends StatefulWidget {
  const AddCustomerDialog({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<AddCustomerDialog> {
  final customerName = TextEditingController();
  final tableName = TextEditingController();
  final existingSearch = TextEditingController();
  bool saving = false;
  bool openLoyaltyCard = false;
  int selectedTab = 0;

  @override
  void initState() {
    super.initState();
    customerName.addListener(_onCustomerNameChanged);
    existingSearch.addListener(() => setState(() {}));
    _refreshExistingCustomers();
  }

  Future<void> _refreshExistingCustomers() async {
    try {
      await widget.pageState.reloadCustomers();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        showAppTopError('Failed to refresh customer list. Showing last saved list.');
      }
    }
  }

  void _onCustomerNameChanged() {
    if (customerName.text.trim().isEmpty && openLoyaltyCard) {
      setState(() => openLoyaltyCard = false);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    customerName.removeListener(_onCustomerNameChanged);
    customerName.dispose();
    tableName.dispose();
    existingSearch.dispose();
    super.dispose();
  }

  List<Customer> get filteredExistingCustomers {
    final query = existingSearch.text.trim().toLowerCase();
    return widget.pageState.customers.where((customer) {
      if (query.isEmpty) return true;
      return customer.displayName.toLowerCase().contains(query) ||
          customer.tableName.toLowerCase().contains(query) ||
          customer.orderType.toLowerCase().contains(query);
    }).toList();
  }

  void _selectExisting(Customer customer) {
    widget.pageState.selectExistingCustomer(customer);
    Navigator.pop(context);
    showAppTopSuccess('Customer ${customer.displayName} selected');
  }

  Future<void> _saveNew() async {
    setState(() => saving = true);
    try {
      if (customerName.text.trim().isEmpty) {
        widget.pageState.resetCustomer();
        if (mounted) Navigator.pop(context);
        return;
      }

      await widget.pageState.saveCustomer(
        customerName: customerName.text,
        tableName: tableName.text,
        createLoyaltyCard: openLoyaltyCard,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        showAppTopError(error.toString());
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _buildExistingTab() {
    final customers = filteredExistingCustomers;
    final currency = widget.pageState.settings.currencySymbol;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final selected = await showRfidCustomerScanDialog(
              context,
              widget.pageState,
            );
            if (selected && mounted) {
              Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.sensors),
          label: const Text('Scan RFID loyalty card'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.green,
            side: const BorderSide(color: AppColors.greenBorder),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: existingSearch,
          decoration: const InputDecoration(
            labelText: 'Search customers',
            hintText: 'Name or reference',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        if (customers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No saved customers yet. Add one in the New tab.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: customers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final customer = customers[index];
                final card = widget.pageState.loyaltyCardFor(customer);
                return Material(
                  color: AppColors.softSurface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _selectExisting(customer),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, color: AppColors.green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${customer.orderType}${customer.tableName.isNotEmpty ? ' • ${customer.tableName}' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (card != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${card.points} pts',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.amber,
                                ),
                              ),
                            ),
                          if (card == null && widget.pageState.settings.loyaltyEnabled)
                            Text(
                              'No card',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.muted.withValues(alpha: 0.8),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        if (widget.pageState.settings.loyaltyEnabled) ...[
          const SizedBox(height: 12),
          Text(
            'Earn ${widget.pageState.settings.loyaltyEarnSummary(currency)} on checkout.',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ],
    );
  }

  Widget _buildNewTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: customerName,
          decoration: const InputDecoration(
            labelText: 'Customer Name',
            hintText: 'Leave blank for walk-in',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: tableName,
          decoration: const InputDecoration(
            labelText: 'Table / Reference',
            hintText: 'Optional',
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: openLoyaltyCard,
          onChanged: customerName.text.trim().isEmpty
              ? null
              : (value) => setState(() => openLoyaltyCard = value ?? false),
          title: const Text('Open loyalty card'),
          subtitle: Text(
            widget.pageState.settings.loyaltyEnabled
                ? 'Points auto-add after checkout (${widget.pageState.settings.loyaltyEarnSummary(widget.pageState.settings.currencySymbol)})'
                : 'Loyalty program is disabled in Settings',
            style: const TextStyle(fontSize: 12),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialogHeight = math.min(
      480.0,
      MediaQuery.sizeOf(context).height - 180,
    );

    return AlertDialog(
      title: const Text('Customer Details'),
      content: SizedBox(
        width: 420,
        height: dialogHeight.clamp(300.0, 480.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Existing')),
                ButtonSegment(value: 1, label: Text('New')),
              ],
              selected: {selectedTab},
              onSelectionChanged: saving
                  ? null
                  : (value) => setState(() => selectedTab = value.first),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: selectedTab == 0
                  ? _buildExistingTab()
                  : SingleChildScrollView(child: _buildNewTab()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (selectedTab == 1)
          TextButton(
            onPressed: saving
                ? null
                : () {
                    widget.pageState.resetCustomer();
                    Navigator.pop(context);
                  },
            child: const Text('Use Walk-In'),
          ),
        if (selectedTab == 1)
          FilledButton(
            onPressed: saving ? null : _saveNew,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Customer'),
          ),
      ],
    );
  }
}

class CartListTile extends StatelessWidget {
  const CartListTile({
    super.key,
    required this.item,
    required this.currencySymbol,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEditQuantity,
    required this.onRemove,
    this.canIncrement = true,
  });

  final CartItem item;
  final String currencySymbol;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onEditQuantity;
  final VoidCallback onRemove;
  final bool canIncrement;

  @override
  Widget build(BuildContext context) {
    final lineTotal = formatMoney(currencySymbol, item.total);
    final unitPrice = formatMoney(currencySymbol, item.unitPrice);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onEditQuantity,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$unitPrice each',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          QuantityStepper(
            quantity: item.quantity,
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            canIncrement: canIncrement,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Text(
              lineTotal,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.text,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                Icons.delete_outline,
                color: AppColors.danger,
                size: 20,
              ),
              tooltip: 'Remove',
            ),
          ),
        ],
      ),
    );
  }
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    this.canIncrement = true,
  });

  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool canIncrement;

  double get _width {
    final digits = quantity.toString().length;
    return (88 + (digits - 1) * 10).clamp(92.0, 132.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _width,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
        color: AppColors.surface,
      ),
      child: Row(
        children: [
          _StepperButton(icon: Icons.remove, onTap: onDecrement),
          Expanded(
            child: Text(
              '$quantity',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          _StepperButton(icon: Icons.add, onTap: canIncrement ? onIncrement : null),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.green : AppColors.muted.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

class _CartActionButtons extends StatelessWidget {
  const _CartActionButtons({required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    final hasItems = pageState.cart.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ActionChip(
                  label: 'Discount',
                  icon: Icons.percent,
                  onTap: hasItems ? () => _showDiscountDialog(context) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionChip(
                  label: 'Coupon',
                  icon: Icons.local_offer_outlined,
                  onTap: hasItems ? () => _showCouponDialog(context) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionChip(
                  label: 'Loyalty',
                  icon: Icons.card_giftcard,
                  onTap: hasItems && pageState.canUseLoyalty(pageState.selectedCustomer)
                      ? () => _showLoyaltyDialog(context)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionChip(
                  label: 'Hold',
                  icon: Icons.pause_circle_outline,
                  onTap: hasItems ? pageState.holdCurrentTransaction : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ActionChip(
            label: 'Clear',
            icon: Icons.delete_sweep_outlined,
            onTap: hasItems ? () => _confirmClearCart(context) : null,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: hasItems ? pageState.enterPaymentMode : null,
            icon: const Icon(Icons.payments_outlined),
            label: Text(
              'Charge ${formatMoney(pageState.settings.currencySymbol, pageState.grandTotal)}',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: AppColors.amber,
              foregroundColor: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiscountDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ManualDiscountDialog(pageState: pageState),
    );
  }

  Future<void> _showCouponDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _CouponApplyDialog(pageState: pageState),
    );
  }

  Future<void> _showLoyaltyDialog(BuildContext context) async {
    final customer = pageState.selectedCustomer;
    if (!pageState.canUseLoyalty(customer)) {
      showAppTopWarning(
        'Loyalty is only available for registered customers with a loyalty card',
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _LoyaltyRedeemDialog(pageState: pageState),
    );
  }

  Future<void> _confirmClearCart(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cart?'),
        content: const Text('Remove all items from the current cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) pageState.clearCart();
  }
}

class _ManualDiscountDialog extends StatefulWidget {
  const _ManualDiscountDialog({required this.pageState});

  final PosHomePageState pageState;

  @override
  State<_ManualDiscountDialog> createState() => _ManualDiscountDialogState();
}

class _ManualDiscountDialogState extends State<_ManualDiscountDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: widget.pageState.manualDiscount > 0
          ? widget.pageState.manualDiscount.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _apply() {
    widget.pageState.applyManualDiscount(toDouble(controller.text));
    Navigator.pop(context);
    showAppTopSuccess('Discount applied');
  }

  void _clearDiscount() {
    widget.pageState.applyManualDiscount(0);
    Navigator.pop(context);
    showAppTopSuccess('Discount removed');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Manual Discount'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: InputDecoration(
            prefixText: widget.pageState.settings.currencySymbol,
            labelText: 'Discount Amount',
          ),
        ),
      ),
      actions: [
        if (widget.pageState.manualDiscount > 0)
          TextButton(
            onPressed: _clearDiscount,
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _LoyaltyRedeemDialog extends StatefulWidget {
  const _LoyaltyRedeemDialog({required this.pageState});

  final PosHomePageState pageState;

  @override
  State<_LoyaltyRedeemDialog> createState() => _LoyaltyRedeemDialogState();
}

class _LoyaltyRedeemDialogState extends State<_LoyaltyRedeemDialog> {
  late final TextEditingController controller;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: widget.pageState.loyaltyPointsRedeemed > 0
          ? '${widget.pageState.loyaltyPointsRedeemed}'
          : '',
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  LoyaltyCard? get _card {
    final customer = widget.pageState.selectedCustomer;
    if (customer == null) return null;
    return widget.pageState.loyaltyCardFor(customer);
  }

  void _redeem() {
    final error = widget.pageState.redeemLoyaltyPoints(toInt(controller.text));
    if (error != null) {
      setState(() => errorMessage = error);
      return;
    }

    Navigator.pop(context);
    final points = widget.pageState.loyaltyPointsRedeemed;
    final discount = widget.pageState.settings.pesoValueForPoints(points);
    showAppTopSuccess(
      'Redeemed $points pts (${formatMoney(widget.pageState.settings.currencySymbol, discount)} off)',
    );
  }

  void _clearRedemption() {
    widget.pageState.clearLoyaltyRedemption();
    Navigator.pop(context);
    showAppTopSuccess('Loyalty redemption removed');
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    if (card == null) {
      return AlertDialog(
        title: const Text('Redeem Loyalty Points'),
        content: const Text('No loyalty card found for this customer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final settings = widget.pageState.settings;
    final currency = settings.currencySymbol;
    final previewPoints = toInt(controller.text);
    final previewDiscount = settings.pesoValueForPoints(previewPoints);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Redeem Loyalty Points'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard, color: AppColors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${card.points} points available',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${settings.loyaltyRedeemPointsPerPeso} pts = ${formatMoney(currency, 1)} off',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Points to Redeem',
                hintText: 'Enter points',
              ),
              onChanged: (_) {
                if (errorMessage != null) {
                  setState(() => errorMessage = null);
                } else {
                  setState(() {});
                }
              },
            ),
            if (previewPoints > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Discount preview: ${formatMoney(currency, previewDiscount.clamp(0, widget.pageState.subtotal))}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.pageState.loyaltyPointsRedeemed > 0)
          TextButton(
            onPressed: _clearRedemption,
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _redeem,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _CouponApplyDialog extends StatefulWidget {
  const _CouponApplyDialog({required this.pageState});

  final PosHomePageState pageState;

  @override
  State<_CouponApplyDialog> createState() => _CouponApplyDialogState();
}

class _CouponApplyDialogState extends State<_CouponApplyDialog> {
  late final TextEditingController controller;
  String? errorMessage;
  bool applying = false;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.pageState.appliedCouponCode);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() {
      applying = true;
      errorMessage = null;
    });

    final error = await widget.pageState.applyCoupon(controller.text);
    if (!mounted) return;

    if (error != null) {
      setState(() {
        errorMessage = error;
        applying = false;
      });
      return;
    }

    Navigator.pop(context);
    showAppTopSuccess('Coupon applied');
  }

  void _removeCoupon() {
    widget.pageState.clearCoupon();
    Navigator.pop(context);
    showAppTopSuccess('Coupon removed');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Apply Coupon'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              enabled: !applying,
              decoration: const InputDecoration(
                labelText: 'Coupon Code',
                hintText: 'Enter promotion code',
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) {
                if (errorMessage != null) {
                  setState(() => errorMessage = null);
                }
              },
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.pageState.appliedCouponCode.isNotEmpty)
          TextButton(
            onPressed: applying ? null : _removeCoupon,
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: applying ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: applying ? null : _apply,
          child: applying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Apply'),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        backgroundColor: AppColors.softSurface,
        side: const BorderSide(color: AppColors.border),
        foregroundColor: enabled ? AppColors.text : AppColors.muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: enabled ? AppColors.green : AppColors.muted.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: enabled ? AppColors.text : AppColors.muted.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
