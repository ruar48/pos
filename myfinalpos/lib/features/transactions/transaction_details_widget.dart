import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import 'transaction_model.dart';
import 'transaction_payment_summary.dart';

class TransactionDetailsWidget extends StatelessWidget {
  const TransactionDetailsWidget({
    required this.transaction,
    required this.onPrint,
    required this.onReprint,
    required this.onRefund,
    required this.onVoid,
    required this.onDownloadPdf,
    required this.onShare,
    super.key,
  });

  final TransactionRecord transaction;
  final VoidCallback onPrint;
  final VoidCallback onReprint;
  final VoidCallback onRefund;
  final VoidCallback onVoid;
  final VoidCallback onDownloadPdf;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.text : AppColors.surface;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order Details',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _DetailStatCard(
                      label: 'Cashier',
                      value: transaction.cashierName,
                      icon: Icons.person,
                      color: AppColors.green,
                    ),
                    _DetailStatCard(
                      label: 'Receipt',
                      value: transaction.receiptNumber,
                      icon: Icons.receipt_long,
                      color: AppColors.green,
                    ),
                    _DetailStatCard(
                      label: 'Payment',
                      value: transaction.paymentSummaryLabel,
                      icon: Icons.payment,
                      color: AppColors.green,
                    ),
                    _DetailStatCard(
                      label: 'Customer',
                      value: transaction.customerName,
                      icon: Icons.people,
                      color: AppColors.darkGreen,
                    ),
                  ],
                ),
                if (transaction.isSplitPayment) ...[
                  const SizedBox(height: 16),
                  TransactionPaymentSummary(transaction: transaction),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Purchased Items',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                for (final item in transaction.items) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.productName} x${formatQuantity(item.quantity)}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              item.sku,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₱${item.subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const Divider(),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Grand Total'),
                    Text(
                      '₱${transaction.grandTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onReprint,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Reprint'),
              ),
              FilledButton.icon(
                onPressed: onRefund,
                icon: const Icon(Icons.undo),
                label: const Text('Refund'),
              ),
              OutlinedButton.icon(
                onPressed: onDownloadPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
              OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailStatCard extends StatelessWidget {
  const _DetailStatCard({
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
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
