import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/refund_item_request.dart';
import 'transaction_model.dart';

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
  int selectedQuantity = 1;
  String? selectedReasonTemplate;
  final TextEditingController reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final refundable = refundableItems;
    if (refundable.isNotEmpty) {
      selectedOrderItemId = refundable.first.orderItemId;
      selectedQuantity =
          refundable.first.quantity - refundable.first.refundedQuantity;
    }
    selectedReasonTemplate = _refundReasonTemplates.first;
    reasonController.text = selectedReasonTemplate!;
    reasonController.addListener(_onReasonChanged);
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

  int get maxQuantity {
    final item = selectedItem;
    if (item == null) return 1;
    return item.quantity - item.refundedQuantity;
  }

  void _submitFullRefund() {
    if (reasonController.text.trim().isEmpty) return;
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
    if (item == null || reasonController.text.trim().isEmpty) return;

    Navigator.pop(
      context,
      RefundDialogResult(
        items: [
          RefundItemRequest(
            orderItemId: item.orderItemId,
            quantity: selectedQuantity,
          ),
        ],
        refundType: 'items',
        reason: reasonController.text.trim(),
      ),
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
                value: selectedOrderItemId,
                decoration: const InputDecoration(labelText: 'Item'),
                items: [
                  for (final item in refundable)
                    DropdownMenuItem(
                      value: item.orderItemId,
                      child: Text('${item.productName} x${item.quantity}'),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    selectedOrderItemId = value;
                    selectedQuantity = maxQuantity;
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Quantity'),
                  const Spacer(),
                  IconButton(
                    onPressed: selectedQuantity > 1
                        ? () => setState(() => selectedQuantity--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$selectedQuantity'),
                  IconButton(
                    onPressed: selectedQuantity < maxQuantity
                        ? () => setState(() => selectedQuantity++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
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
            onPressed: hasReason ? _submitItemRefund : null,
            child: Text('${widget.actionLabel} Item'),
          ),
        FilledButton(
          onPressed: refundable.isEmpty || !hasReason ? null : _submitFullRefund,
          child: Text('${widget.actionLabel} All'),
        ),
      ],
    );
  }
}
