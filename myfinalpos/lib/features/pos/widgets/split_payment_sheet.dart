import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/pos_payment_methods.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/order_payment.dart';
import '../pages/pos_home_page.dart';

class SplitPaymentResult {
  const SplitPaymentResult({required this.payments});

  final List<OrderPayment> payments;
}

Future<SplitPaymentResult?> showSplitPaymentSheet(
  BuildContext context, {
  required PosHomePageState pageState,
}) {
  return showDialog<SplitPaymentResult>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _SplitPaymentDialog(pageState: pageState),
  );
}

class _SplitPaymentRow {
  _SplitPaymentRow({
    required this.method,
    required this.amountController,
    required this.referenceController,
  });

  String method;
  final TextEditingController amountController;
  final TextEditingController referenceController;
}

class _SplitPaymentDialog extends StatefulWidget {
  const _SplitPaymentDialog({required this.pageState});

  final PosHomePageState pageState;

  @override
  State<_SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<_SplitPaymentDialog> {
  late final List<_SplitPaymentRow> rows;
  bool processing = false;

  static const _fieldPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  double get total => widget.pageState.grandTotal;

  double get allocated => rows.fold(
        0,
        (sum, row) => sum + toDouble(row.amountController.text),
      );

  double get remaining => (total - allocated).clamp(-double.infinity, total);

  List<_SplitPaymentRow> get activeRows => rows
      .where((row) => toDouble(row.amountController.text) > 0)
      .toList();

  bool get amountsBalanced => remaining.abs() < 0.01;

  bool get referencesComplete => activeRows.every(
        (row) =>
            !PosPaymentMethods.requiresReference(row.method) ||
            row.referenceController.text.trim().isNotEmpty,
      );

  String? get chargeBlockerMessage {
    if (activeRows.length < 2) {
      return 'Add at least two payment amounts';
    }
    if (!amountsBalanced) {
      if (remaining > 0) {
        return 'Allocate the remaining ${formatMoney(widget.pageState.settings.currencySymbol, remaining)}';
      }
      return 'Payment amounts exceed the order total';
    }
    if (!referencesComplete) {
      final missing = activeRows
          .where(
            (row) =>
                PosPaymentMethods.requiresReference(row.method) &&
                row.referenceController.text.trim().isEmpty,
          )
          .map((row) => PosPaymentMethods.referenceLabel(row.method))
          .toList();
      return 'Enter ${missing.join(' and ')} to continue';
    }
    return null;
  }

  bool get canCharge =>
      !processing && activeRows.length >= 2 && referencesComplete && amountsBalanced;

  InputDecoration _inputDecoration({
    String? label,
    String? hint,
    String? prefix,
    String? error,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.border),
    );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      contentPadding: _fieldPadding,
      errorText: error,
      errorStyle: const TextStyle(fontSize: 12, height: 1.2),
      labelStyle: const TextStyle(fontSize: 13),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.green, width: 1.5),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.orange),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final half = (total / 2);
    final first = half.floorToDouble() == half
        ? half
        : double.parse(half.toStringAsFixed(2));
    final second = double.parse((total - first).toStringAsFixed(2));

    rows = [
      _SplitPaymentRow(
        method: 'Cash',
        amountController: TextEditingController(text: first.toStringAsFixed(2)),
        referenceController: TextEditingController(),
      ),
      _SplitPaymentRow(
        method: 'GCash',
        amountController: TextEditingController(text: second.toStringAsFixed(2)),
        referenceController: TextEditingController(),
      ),
    ];
  }

  @override
  void dispose() {
    for (final row in rows) {
      row.amountController.dispose();
      row.referenceController.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      rows.add(
        _SplitPaymentRow(
          method: 'Cash',
          amountController: TextEditingController(),
          referenceController: TextEditingController(),
        ),
      );
    });
  }

  void _removeRow(int index) {
    if (rows.length <= 2) return;
    setState(() {
      final row = rows.removeAt(index);
      row.amountController.dispose();
      row.referenceController.dispose();
    });
  }

  void _fillRemaining(int index) {
    final otherTotal = rows
        .asMap()
        .entries
        .where((entry) => entry.key != index)
        .fold(
          0.0,
          (sum, entry) => sum + toDouble(entry.value.amountController.text),
        );
    final fill = (total - otherTotal).clamp(0, double.infinity);
    setState(() {
      rows[index].amountController.text = fill.toStringAsFixed(2);
    });
  }

  void _submit() {
    if (!canCharge) return;

    final payments = <OrderPayment>[];
    for (final row in rows) {
      final amount = toDouble(row.amountController.text);
      if (amount <= 0) continue;

      if (PosPaymentMethods.requiresReference(row.method) &&
          row.referenceController.text.trim().isEmpty) {
        showTopWarning(
          context,
          'Enter ${PosPaymentMethods.referenceLabel(row.method).toLowerCase()}',
        );
        return;
      }

      payments.add(
        OrderPayment(
          paymentMethod: row.method,
          amount: amount,
          reference: row.referenceController.text.trim(),
        ),
      );
    }

    if (payments.length < 2) {
      showTopWarning(context, 'Add at least two payment methods');
      return;
    }

    final sum = payments.fold(0.0, (a, p) => a + p.amount);
    if ((sum - total).abs() > 0.01) {
      showTopWarning(context, 'Payment amounts must equal the order total');
      return;
    }

    Navigator.pop(
      context,
      SplitPaymentResult(payments: payments),
    );
  }

  Widget _buildPaymentRow(int i, String currency, double remainingValue) {
    final needsReference = PosPaymentMethods.requiresReference(rows[i].method);
    final hasAmount = toDouble(rows[i].amountController.text) > 0;
    final missingReference = amountsBalanced &&
        hasAmount &&
        needsReference &&
        rows[i].referenceController.text.trim().isEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 6 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 148,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: rows[i].method,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                  decoration: _inputDecoration(label: 'Method'),
                  items: [
                    for (final method in PosPaymentMethods.all)
                      DropdownMenuItem(
                        value: method,
                        child: Text(
                          method,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                  ],
                  onChanged: processing
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            rows[i].method = value;
                            if (!PosPaymentMethods.requiresReference(value)) {
                              rows[i].referenceController.clear();
                            }
                          });
                        },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: rows[i].amountController,
                  enabled: !processing,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: _inputDecoration(
                    label: 'Amount',
                    prefix: currency,
                  ).copyWith(
                    suffixIcon: remainingValue > 0
                        ? IconButton(
                            tooltip: 'Fill remaining',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                processing ? null : () => _fillRemaining(i),
                            icon: const Icon(Icons.north, size: 18),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (rows.length > 2) ...[
                const SizedBox(width: 2),
                SizedBox(
                  width: 44,
                  height: 48,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: processing ? null : () => _removeRow(i),
                    icon: const Icon(
                      Icons.close,
                      size: 22,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (needsReference) ...[
            const SizedBox(height: 8),
            TextField(
              controller: rows[i].referenceController,
              enabled: !processing,
              style: const TextStyle(fontSize: 14),
              decoration: _inputDecoration(
                label: PosPaymentMethods.referenceLabel(rows[i].method),
                hint: PosPaymentMethods.referenceHint(rows[i].method),
                error: missingReference ? 'Required' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.pageState.settings.currencySymbol;
    final remainingValue = remaining.abs() < 0.01 ? 0.0 : remaining;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(480, MediaQuery.sizeOf(context).width * 0.52),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Split Payment',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: processing ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 22),
                    tooltip: 'Close',
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        _buildPaymentRow(i, currency, remainingValue),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: processing ? null : _addRow,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add payment'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.greenBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(fontSize: 14, height: 1.35),
                          children: [
                            const TextSpan(
                              text: 'Total ',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: formatMoney(currency, total),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 14, height: 1.35),
                        children: [
                          const TextSpan(
                            text: 'Remaining ',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: formatMoney(currency, remainingValue),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: remainingValue.abs() < 0.01
                                  ? AppColors.green
                                  : AppColors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (chargeBlockerMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  chargeBlockerMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.orange,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: canCharge ? _submit : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: AppColors.amber,
                  foregroundColor: AppColors.text,
                  disabledBackgroundColor: AppColors.border,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: processing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Charge ${formatMoney(currency, total)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
