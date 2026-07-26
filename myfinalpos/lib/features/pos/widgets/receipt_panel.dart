import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../receipt/receipt_preview_widget.dart';
import '../../receipt/receipt_printer.dart';
import '../pages/pos_home_page.dart';

class ReceiptPanel extends StatefulWidget {
  const ReceiptPanel({
    super.key,
    required this.pageState,
    required this.receipt,
  });

  final PosHomePageState pageState;
  final ReceiptData receipt;

  @override
  State<ReceiptPanel> createState() => _ReceiptPanelState();
}

class _ReceiptPanelState extends State<ReceiptPanel> {
  bool printing = false;
  bool downloading = false;

  Future<void> _print() async {
    final pageState = widget.pageState;
    if (!pageState.isPrinterConfigured) {
      if (!mounted) return;
      showTopWarning(context, pageState.missingPrinterMessage(
        canManageSettings: pageState.widget.currentUser.canManageSettings,
      ));
      return;
    }

    setState(() => printing = true);
    try {
      await PosReceiptService.printReceipt(
        receipt: widget.receipt,
        printer: pageState.resolvedPrinter,
        openDrawer: widget.receipt.includesCashPayment,
      );
      if (mounted) {
        showTopSuccess(context, 'Receipt sent to printer');
      }
    } on ReceiptPrintException catch (error) {
      if (mounted) showTopError(context, error.message);
    } catch (error) {
      if (mounted) showTopError(context, error.toString());
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  Future<void> _download() async {
    setState(() => downloading = true);
    try {
      await PosReceiptService.downloadReceipt(widget.receipt);
      if (mounted) {
        showTopSuccess(context, 'Receipt ready to save or share');
      }
    } catch (error) {
      if (mounted) showTopError(context, error.toString());
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final currency = receipt.currencySymbol;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.08),
              border: Border(
                bottom: BorderSide(color: AppColors.green.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payment complete',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        receipt.invoiceNumber,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatMoney(currency, receipt.total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkGreen,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Receipt preview',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ThermalReceiptPreview(
                    receipt: receipt,
                    compact: true,
                    fitToContent: true,
                    fillAvailableWidth: true,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: printing ? null : _print,
                        icon: printing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print_outlined, size: 20),
                        label: const Text('Print'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: AppColors.green,
                          side: const BorderSide(color: AppColors.greenBorder),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: downloading ? null : _download,
                        icon: downloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_outlined, size: 20),
                        label: const Text('Download'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: widget.pageState.dismissCompletedReceipt,
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                  label: const Text('New order'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: AppColors.green,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: widget.pageState.dismissCompletedReceipt,
                  child: const Text('Back to cart'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
