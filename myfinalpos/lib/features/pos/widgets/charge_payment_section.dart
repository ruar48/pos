import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/pos_payment_methods.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../receipt/receipt_printer.dart';
import '../../../models/order_payment.dart';
import '../pages/pos_home_page.dart';
import 'order_total_panel.dart';
import 'receipt_note_dialog.dart';
import 'split_payment_sheet.dart';

class ChargePaymentSection extends StatefulWidget {
  const ChargePaymentSection({
    super.key,
    required this.pageState,
    required this.subtotal,
  });

  final PosHomePageState pageState;
  final double subtotal;

  @override
  State<ChargePaymentSection> createState() => _ChargePaymentSectionState();
}

class _ChargePaymentSectionState extends State<ChargePaymentSection> {
  static const _quickAmounts = [20, 50, 100, 200, 500, 1000];

  String paymentMethod = 'Cash';
  final amountController = TextEditingController();
  final referenceController = TextEditingController();
  bool processing = false;
  int? selectedQuickAmount;

  @override
  void initState() {
    super.initState();
    amountController.text = widget.pageState.grandTotal.toStringAsFixed(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.pageState.publishMonitorPaymentProcessing();
    });
  }

  @override
  void dispose() {
    amountController.dispose();
    referenceController.dispose();
    super.dispose();
  }

  double get amountTendered => toDouble(amountController.text);
  double get changeAmount =>
      (amountTendered - widget.pageState.grandTotal).clamp(0, double.infinity);

  bool get _requiresReference => PosPaymentMethods.requiresReference(paymentMethod);

  String get _referenceLabel => PosPaymentMethods.referenceLabel(paymentMethod);

  String get _referenceHint => PosPaymentMethods.referenceHint(paymentMethod);

  String get _referenceValidationMessage => paymentMethod == 'Cheque'
      ? 'Enter a cheque number to continue'
      : 'Enter a $paymentMethod reference to continue';

  bool get _canCompletePayment {
    if (widget.pageState.cart.isEmpty) return false;
    if (paymentMethod == 'Cash') {
      return amountTendered >= widget.pageState.grandTotal;
    }
    return referenceController.text.trim().isNotEmpty;
  }

  void _setQuickAmount(int amount) {
    setState(() {
      selectedQuickAmount = amount;
      amountController.text = amount.toStringAsFixed(2);
    });
  }

  void _setExactAmount() {
    setState(() {
      selectedQuickAmount = null;
      amountController.text =
          widget.pageState.grandTotal.toStringAsFixed(2);
    });
  }

  Future<void> _completePayment({
    List<OrderPayment>? splitPayments,
    String receiptNote = '',
  }) async {
    if (widget.pageState.cart.isEmpty) return;

    final splitLines = splitPayments;
    final isSplit = splitLines != null && splitLines.length >= 2;

    if (!isSplit) {
      if (paymentMethod == 'Cash' && amountTendered < widget.pageState.grandTotal) {
        showTopWarning(context, 'Amount tendered is less than total');
        return;
      }

      if (_requiresReference && referenceController.text.trim().isEmpty) {
        showTopWarning(context, _referenceValidationMessage);
        return;
      }
    }

    setState(() => processing = true);
    widget.pageState.publishMonitorPaymentProcessing();

    try {
      final customer = widget.pageState.selectedCustomer;

      final resolvedPaymentMethod = isSplit
          ? splitLines
              .map((p) => p.paymentMethod)
              .toSet()
              .join(' + ')
          : paymentMethod;

      final checkout = await widget.pageState.completeCheckout(
        customerId: customer?.id,
        cartItems: widget.pageState.cart,
        subtotal: widget.pageState.netSubtotal,
        vat: widget.pageState.vatAmount,
        totalAmount: widget.pageState.grandTotal,
        clientChange: isSplit
            ? 0
            : (paymentMethod == 'Cash' ? changeAmount : 0),
        paymentMethod: isSplit ? 'Split ($resolvedPaymentMethod)' : paymentMethod,
        reference: isSplit ? '' : referenceController.text.trim(),
        discountAmount: widget.pageState.manualDiscount,
        couponDiscount: widget.pageState.couponDiscount,
        couponCode: widget.pageState.appliedCouponCode,
        loyaltyDiscount: widget.pageState.loyaltyDiscountAmount,
        loyaltyPointsRedeemed: widget.pageState.loyaltyPointsRedeemed,
        payments: isSplit
            ? splitLines.map((payment) => payment.toJson()).toList()
            : null,
        receiptNote: receiptNote,
      );
      final orderId = checkout.orderId;
      final invoiceNumber = checkout.invoiceNumber;
      final currency = widget.pageState.settings.currencySymbol;
      final earnsLoyalty = !checkout.isOfflinePending &&
          widget.pageState.customerEarnsLoyalty(customer);
      final loyaltyCard = customer != null
          ? widget.pageState.loyaltyCardFor(customer)
          : null;
      final pointsEarned = earnsLoyalty
          ? widget.pageState.pointsEarnedForCurrentOrder()
          : 0;
      final loyaltyBalance = loyaltyCard == null
          ? pointsEarned
          : (loyaltyCard.points -
                  widget.pageState.loyaltyPointsRedeemed +
                  pointsEarned)
              .clamp(0, 999999999);
      final showLoyaltyOnReceipt =
          earnsLoyalty && (pointsEarned > 0 || loyaltyCard != null);

      final receipt = ReceiptData(
        orderId: orderId,
        invoiceNumber: invoiceNumber,
        customerName: customer?.displayName ?? 'Walk In Farmer',
        paymentMethod: isSplit ? 'Split ($resolvedPaymentMethod)' : paymentMethod,
        splitPayments: isSplit
            ? splitLines
                .map(
                  (payment) => ReceiptPaymentLine(
                    paymentMethod: payment.paymentMethod,
                    amount: payment.amount,
                    reference: payment.reference,
                  ),
                )
                .toList()
            : null,
        items: widget.pageState.cart
            .map(
              (item) => ReceiptLineItem(
                name: item.displayName,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                total: item.total,
              ),
            )
            .toList(),
        subtotal: widget.pageState.netSubtotal,
        vat: widget.pageState.vatAmount,
        discount: widget.pageState.totalDiscount,
        manualDiscount: widget.pageState.manualDiscount,
        couponDiscount: widget.pageState.couponDiscount,
        loyaltyDiscount: widget.pageState.loyaltyDiscountAmount,
        total: widget.pageState.grandTotal,
        amountTendered: isSplit
            ? splitLines.fold(0.0, (sum, p) => sum + p.amount)
            : (paymentMethod == 'Cash'
                ? amountTendered
                : widget.pageState.grandTotal),
        change: isSplit ? 0 : (paymentMethod == 'Cash' ? changeAmount : 0),
        currencySymbol: currency,
        cashierName: widget.pageState.widget.currentUser.fullName,
        itemCount: widget.pageState.cart.fold(0, (sum, item) => sum + item.quantity),
        orderType: widget.pageState.orderType,
        reference: referenceController.text.trim(),
        receiptNote: checkout.isOfflinePending
            ? [
                if (receiptNote.trim().isNotEmpty) receiptNote.trim(),
                'OFFLINE SALE - PENDING SYNC',
              ].join('\n')
            : receiptNote,
        loyaltyPointsEarned: pointsEarned,
        loyaltyBalance: loyaltyBalance,
        isLoyaltyCustomer: showLoyaltyOnReceipt,
        store: widget.pageState.receiptStore,
      );

      if (!mounted) return;

      unawaited(
        PosReceiptService.autoPrintOnComplete(
          receipt: receipt,
          autoPrint: widget.pageState.settings.autoPrintReceipt,
          doublePrint: widget.pageState.settings.doublePrintReceipt,
          openDrawer: isSplit
              ? splitLines.any((p) => p.paymentMethod == 'Cash')
              : paymentMethod == 'Cash',
          printer: widget.pageState.resolvedPrinter,
        ),
      );

      await widget.pageState.finishOrderAndShowReceipt(receipt);

      if (mounted) {
        showAppTopSuccess(
          checkout.isOfflinePending
              ? 'Offline sale saved • $invoiceNumber • ${formatMoney(currency, receipt.total)}'
              : 'Payment complete • $invoiceNumber • ${formatMoney(currency, receipt.total)}',
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        showTopError(context, message);
      }
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  Future<void> _promptReceiptNoteAndComplete({
    List<OrderPayment>? splitPayments,
  }) async {
    if (widget.pageState.cart.isEmpty || processing) return;

    final splitLines = splitPayments;
    final isSplit = splitLines != null && splitLines.length >= 2;

    if (!isSplit) {
      if (paymentMethod == 'Cash' &&
          amountTendered < widget.pageState.grandTotal) {
        showTopWarning(context, 'Amount tendered is less than total');
        return;
      }

      if (_requiresReference && referenceController.text.trim().isEmpty) {
        showTopWarning(context, _referenceValidationMessage);
        return;
      }
    }

    final note = await showReceiptNoteDialog(context);
    if (!mounted || note == null) return;

    await _completePayment(
      splitPayments: splitPayments,
      receiptNote: note,
    );
  }

  Future<void> _openSplitPayment() async {
    if (widget.pageState.cart.isEmpty || processing) return;

    final result = await showSplitPaymentSheet(
      context,
      pageState: widget.pageState,
    );

    if (result == null || !mounted) return;
    await _promptReceiptNoteAndComplete(splitPayments: result.payments);
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.pageState.settings.currencySymbol;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: processing ? null : widget.pageState.exitPaymentMode,
                  icon: const Icon(Icons.arrow_back),
                ),
                const Text(
                  'Charge Payment',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final method in PosPaymentMethods.all)
                        ChoiceChip(
                          label: Text(method),
                          selected: paymentMethod == method,
                          onSelected: (_) => setState(() {
                            paymentMethod = method;
                            if (method == 'Cash') {
                              referenceController.clear();
                            }
                          }),
                          selectedColor: AppColors.green,
                          labelStyle: TextStyle(
                            color: paymentMethod == method
                                ? Colors.white
                                : AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (paymentMethod == 'Cash') ...[
                    const Text(
                      'Quick Amount',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.2,
                      children: [
                        for (final amount in _quickAmounts)
                          _QuickAmountButton(
                            amount: amount,
                            currencySymbol: currency,
                            isSelected: selectedQuickAmount == amount,
                            onTap: () => _setQuickAmount(amount),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _setExactAmount,
                        child: Text(
                          'Exact ${formatMoney(currency, widget.pageState.grandTotal)}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Amount Tendered',
                        prefixText: currency,
                      ),
                      onChanged: (_) => setState(() => selectedQuickAmount = null),
                    ),
                    const SizedBox(height: 12),
                    _PaymentInfoRow(
                      label: 'Change',
                      value: formatMoney(currency, changeAmount),
                      emphasize: true,
                    ),
                  ] else ...[
                    TextField(
                      controller: referenceController,
                      decoration: InputDecoration(
                        labelText: _referenceLabel,
                        hintText: _referenceHint,
                        helperText: 'Required to complete payment',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: processing ? null : _openSplitPayment,
                    icon: const Icon(Icons.call_split),
                    label: const Text('Split Payment'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: AppColors.darkGreen,
                      side: const BorderSide(color: AppColors.greenBorder),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OrderTotalPanel(pageState: widget.pageState, compact: true),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: processing || !_canCompletePayment
                  ? null
                  : () => _promptReceiptNoteAndComplete(),
              icon: processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                processing
                    ? 'Processing...'
                    : 'Complete ${formatMoney(currency, widget.pageState.grandTotal)}',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAmountButton extends StatelessWidget {
  const _QuickAmountButton({
    required this.amount,
    required this.currencySymbol,
    required this.isSelected,
    required this.onTap,
  });

  final int amount;
  final String currencySymbol;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.lightGreen : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? AppColors.green : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            '$currencySymbol$amount',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isSelected ? AppColors.green : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentInfoRow extends StatelessWidget {
  const _PaymentInfoRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: emphasize ? 16 : 14,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            color: emphasize ? AppColors.text : AppColors.muted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 20 : 16,
            fontWeight: FontWeight.w800,
            color: AppColors.green,
          ),
        ),
      ],
    );
  }
}
