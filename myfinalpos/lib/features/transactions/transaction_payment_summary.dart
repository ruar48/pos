import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../models/order_payment.dart';
import 'transaction_model.dart';

class TransactionPaymentSummary extends StatelessWidget {
  const TransactionPaymentSummary({
    super.key,
    required this.transaction,
    this.compact = false,
  });

  final TransactionRecord transaction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!transaction.isSplitPayment) {
      return Text(
        transaction.paymentMethod,
        style: TextStyle(
          fontSize: compact ? 12 : 14,
          fontWeight: FontWeight.w700,
          color: compact ? AppColors.muted : AppColors.text,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Split payment',
          style: TextStyle(
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w800,
            color: AppColors.green,
          ),
        ),
        const SizedBox(height: 4),
        ...transaction.splitPayments.map(
          (payment) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              _paymentLine(payment),
              style: TextStyle(
                fontSize: compact ? 11 : 13,
                fontWeight: FontWeight.w600,
                color: compact ? AppColors.muted : AppColors.text,
                height: 1.35,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _paymentLine(OrderPayment payment) {
    final amount = formatMoney('₱', payment.amount);
    if (payment.reference.trim().isEmpty) {
      return '${payment.paymentMethod} · $amount';
    }
    return '${payment.paymentMethod} · $amount · Ref ${payment.reference.trim()}';
  }
}
