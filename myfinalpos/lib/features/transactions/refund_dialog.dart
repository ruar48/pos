import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/top_toast.dart';
import '../../models/refund_item_request.dart';
import 'transaction_model.dart';

double _roundQty(double value) => (value * 1000).round() / 1000;

/// Starting quantity for an item refund: one unit, or the whole remainder
/// when less than one is left (e.g. 0.5 kg). Starting at the full remainder
/// meant one tap of Refund returned everything.
double defaultRefundQuantity(double remaining) {
  final left = _roundQty(remaining);
  if (left <= 0) return 0;
  return left < 1 ? left : 1;
}

/// Keeps a refund quantity inside (0, remaining], to 3 decimals. Returns
/// null when nothing would be refunded.
double? clampRefundQuantity(double? value, double remaining) {
  if (value == null || value.isNaN) return null;
  final left = _roundQty(remaining);
  final qty = _roundQty(value);
  if (qty <= 0 || left <= 0) return null;
  return qty > left ? left : qty;
}

/// Parses what the cashier typed ("2.5", ".25") and clamps it like
/// [clampRefundQuantity].
double? parseRefundQuantity(String text, double remaining) {
  return clampRefundQuantity(double.tryParse(text.trim()), remaining);
}

/// Tells the cashier, in big print, how much to hand back. The amount is
/// the server's (order discounts prorated, VAT added), so it can differ from
/// the line price on screen.
Future<void> showRefundSuccessDialog(
  BuildContext context,
  TransactionApiResult result,
) {
  // Older servers don't report the amount - never show "₱0.00" as the
  // amount to hand back; show just the server's message instead.
  final amount = result.refundAmount;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(
        Icons.check_circle_outline,
        color: AppColors.green,
        size: 40,
      ),
      title: const Text('Refund processed'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (amount != null) ...[
              const Text(
                'Give back to the customer',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatMoney('₱', amount),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: AppColors.danger,
                  height: 1.1,
                ),
              ),
            ],
            if (result.message.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                result.message.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: FilledButton.styleFrom(backgroundColor: AppColors.green),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

/// Shows how a refund went: the give-back dialog on success, the error
/// otherwise. The list reloads underneath while a refund runs, so when the
/// screen's [context] is gone (pass null) the app's root navigator shows it
/// instead - the cashier must never be left guessing.
Future<void> showRefundOutcome(
  BuildContext? context,
  TransactionApiResult result,
) async {
  final target = (context != null && context.mounted)
      ? context
      : appNavigatorKey.currentContext;
  if (target == null || !target.mounted) {
    if (result.success) {
      showAppTopSuccess(result.message);
    } else {
      showAppTopError(result.message);
    }
    return;
  }
  if (result.success) {
    await showRefundSuccessDialog(target, result);
  } else {
    showTopError(target, result.message);
  }
}

const _refundReasonTemplates = [
  'Wrong item',
  'Defective or damaged',
  'Customer changed mind',
  'Pricing error',
  'Duplicate transaction',
  'Expired or spoiled',
  'Quality issue',
];

class RefundDialogResult {
  RefundDialogResult({
    required this.items,
    required this.refundType,
    required this.reason,
  });

  final List<RefundItemRequest> items;
  final String refundType;
  final String reason;
}

class RefundDialog extends StatefulWidget {
  const RefundDialog({
    required this.title,
    required this.transactionId,
    required this.actionLabel,
    required this.items,
    super.key,
  });

  final String title;
  final int transactionId;
  final String actionLabel;
  final List<TransactionItem> items;

  @override
  State<RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  int? selectedOrderItemId;

  /// Null while the typed quantity is empty or zero.
  double? selectedQuantity;
  String? selectedReasonTemplate;
  final TextEditingController reasonController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final refundable = refundableItems;
    if (refundable.isNotEmpty) {
      selectedOrderItemId = refundable.first.orderItemId;
      _setQuantity(defaultRefundQuantity(maxQuantity));
    }
    selectedReasonTemplate = _refundReasonTemplates.first;
    reasonController.text = selectedReasonTemplate!;
    reasonController.addListener(_onReasonChanged);
  }

  void _setQuantity(double value) {
    final qty = clampRefundQuantity(value, maxQuantity);
    selectedQuantity = qty;
    final text = qty == null ? '' : formatQuantity(qty);
    quantityController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onQuantityTyped(String text) {
    final typed = double.tryParse(text.trim());
    setState(() {
      if (typed != null && typed > maxQuantity) {
        // Snap down to what's left rather than letting the server reject it.
        _setQuantity(maxQuantity);
      } else {
        selectedQuantity = parseRefundQuantity(text, maxQuantity);
      }
    });
  }

  void _onReasonChanged() {
    final text = reasonController.text.trim();
    if (selectedReasonTemplate != null && text != selectedReasonTemplate) {
      setState(() => selectedReasonTemplate = null);
    } else {
      setState(() {});
    }
  }

  void _selectReasonTemplate(String reason) {
    setState(() {
      selectedReasonTemplate = reason;
      reasonController.text = reason;
    });
  }

  @override
  void dispose() {
    reasonController.removeListener(_onReasonChanged);
    reasonController.dispose();
    quantityController.dispose();
    super.dispose();
  }

  bool get hasReason => reasonController.text.trim().isNotEmpty;

  List<TransactionItem> get refundableItems =>
      widget.items.where((item) => item.hasRefundableQuantity).toList();

  TransactionItem? get selectedItem {
    if (selectedOrderItemId == null) return null;
    for (final item in refundableItems) {
      if (item.orderItemId == selectedOrderItemId) return item;
    }
    return null;
  }

  double get maxQuantity {
    final item = selectedItem;
    if (item == null) return 0;
    return item.remainingQuantity;
  }

  void _submitFullRefund() {
    if (!hasReason) return;
    Navigator.pop(
      context,
      RefundDialogResult(
        items: const [],
        refundType: 'all',
        reason: reasonController.text.trim(),
      ),
    );
  }

  void _submitItemRefund() {
    final item = selectedItem;
    final quantity = clampRefundQuantity(selectedQuantity, maxQuantity);
    if (item == null || quantity == null || !hasReason) return;

    Navigator.pop(
      context,
      RefundDialogResult(
        items: [
          RefundItemRequest(
            orderItemId: item.orderItemId,
            quantity: quantity,
          ),
        ],
        refundType: 'items',
        reason: reasonController.text.trim(),
      ),
    );
  }

  Widget _buildQuantityRow() {
    final qty = selectedQuantity;
    final max = maxQuantity;
    // Steppers move a whole unit; typing covers fractions (e.g. 0.75 kg).
    final canDecrease = qty != null && qty - 1 > 0.0005;
    final canIncrease = qty == null || qty < max - 0.0005;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
            ],
            decoration: InputDecoration(
              labelText: 'Quantity to refund',
              helperText: 'Up to ${formatQuantity(max)} left',
              errorText: qty == null ? 'Enter a quantity above 0' : null,
            ),
            onChanged: _onQuantityTyped,
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: IconButton(
            onPressed: canDecrease
                ? () => setState(() => _setQuantity(qty - 1))
                : null,
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'One less',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: IconButton(
            onPressed: canIncrease
                ? () => setState(() => _setQuantity((qty ?? 0) + 1))
                : null,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'One more',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final refundable = refundableItems;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Refund Reason',
                hintText: 'Tap a quick reason below or type your own',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            const Text(
              'Quick reasons',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final reason in _refundReasonTemplates)
                  FilterChip(
                    label: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selectedReasonTemplate == reason
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    selected: selectedReasonTemplate == reason,
                    showCheckmark: false,
                    selectedColor: AppColors.lightGreen,
                    side: BorderSide(
                      color: selectedReasonTemplate == reason
                          ? AppColors.green
                          : AppColors.border,
                    ),
                    onSelected: (_) => _selectReasonTemplate(reason),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (refundable.isEmpty)
              const Text('No refundable items remain on this transaction.')
            else ...[
              DropdownButtonFormField<int>(
                initialValue: selectedOrderItemId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Item'),
                items: [
                  for (final item in refundable)
                    DropdownMenuItem(
                      value: item.orderItemId,
                      child: Text(
                        item.refundedQuantity > 0
                            ? '${item.productName} x${formatQuantity(item.quantity)}'
                                ' (${formatQuantity(item.remainingQuantity)} left)'
                            : '${item.productName} x${formatQuantity(item.quantity)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    selectedOrderItemId = value;
                    _setQuantity(defaultRefundQuantity(maxQuantity));
                  });
                },
              ),
              const SizedBox(height: 12),
              _buildQuantityRow(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (refundable.isNotEmpty)
          OutlinedButton(
            onPressed: hasReason && selectedQuantity != null
                ? _submitItemRefund
                : null,
            child: Text(
              selectedQuantity == null
                  ? '${widget.actionLabel} Item'
                  : '${widget.actionLabel} Item x${formatQuantity(selectedQuantity!)}',
            ),
          ),
        FilledButton(
          onPressed: refundable.isEmpty || !hasReason ? null : _submitFullRefund,
          child: Text('${widget.actionLabel} All'),
        ),
      ],
    );
  }
}
