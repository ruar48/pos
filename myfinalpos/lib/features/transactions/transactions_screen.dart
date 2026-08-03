import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_printer_settings.dart';
import '../../models/printer_settings.dart';
import '../../models/refund_item_request.dart';
import '../../core/utils/top_toast.dart';
import '../receipt/receipt_printer.dart';
import 'refund_dialog.dart';
import 'transaction_details_widget.dart';
import 'transaction_model.dart';
import 'transaction_service.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        title: const Text('Orders'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<TransactionState>().refresh(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<TransactionState>(
        builder: (context, state, child) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 1100;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isDesktop)
                    SizedBox(
                      width: constraints.maxWidth * 0.32,
                      child: _TransactionSidebar(state: state),
                    ),
                  Expanded(
                    child: _TransactionDetailArea(
                      state: state,
                      isDesktop: isDesktop,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class TransactionState extends ChangeNotifier {
  TransactionState({required this.service, required this.actorUserId});

  final TransactionService service;
  final int? actorUserId;

  bool isLoading = false;
  String errorMessage = '';
  String query = '';
  TransactionFilterType filter = TransactionFilterType.all;
  TransactionRecord? selectedTransaction;
  List<TransactionRecord> transactions = [];

  Future<void> loadTransactions() async {
    isLoading = true;
    errorMessage = '';
    notifyListeners();

    try {
      final selectedId = selectedTransaction?.id;
      transactions = await service.fetchTransactions();

      if (selectedId != null) {
        TransactionRecord? refreshed;
        for (final transaction in transactions) {
          if (transaction.id == selectedId) {
            refreshed = transaction;
            break;
          }
        }
        selectedTransaction = refreshed ??
            (transactions.isNotEmpty ? transactions.first : null);
      } else {
        selectedTransaction =
            transactions.isNotEmpty ? transactions.first : null;
      }
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadTransactions();

  void select(TransactionRecord transaction) {
    selectedTransaction = transaction;
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void setFilter(TransactionFilterType value) {
    filter = value;
    notifyListeners();
  }

  List<TransactionRecord> get filteredTransactions {
    return transactions.where((transaction) {
      final matchesQuery = query.isEmpty ||
          transaction.customerName.toLowerCase().contains(query.toLowerCase()) ||
          transaction.receiptNumber.toLowerCase().contains(query.toLowerCase());
      final matchesFilter = switch (filter) {
        TransactionFilterType.all => true,
        TransactionFilterType.today => transaction.isToday,
        TransactionFilterType.cash =>
          transaction.paymentMethod.toLowerCase() == 'cash',
        TransactionFilterType.card =>
          transaction.paymentMethod.toLowerCase().contains('card'),
        TransactionFilterType.refunded => transaction.refundedAmount > 0,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  List<TransactionGroup> get groupedTransactions {
    final grouped = <String, List<TransactionRecord>>{};
    for (final transaction in filteredTransactions) {
      grouped.putIfAbsent(transaction.displayDate, () => []).add(transaction);
    }

    return grouped.entries
        .map(
          (entry) => TransactionGroup(
            label: entry.value.first.displayGroupLabel,
            transactions: entry.value,
          ),
        )
        .toList();
  }

  Future<TransactionApiResult> refundSelectedTransaction({
    required String reason,
    required String refundType,
    required List<RefundItemRequest> items,
    String? refundPin,
  }) async {
    final transaction = selectedTransaction;
    if (transaction == null) {
      return const TransactionApiResult(
        success: false,
        message: 'No transaction selected',
      );
    }

    final result = await service.processRefund(
      orderId: transaction.id,
      reason: reason,
      refundType: refundType,
      items: items,
      actorUserId: actorUserId,
      refundPin: refundPin,
    );

    if (result.success) {
      await refresh();
    }
    return result;
  }

  Future<TransactionApiResult> reprintSelectedTransaction() async {
    final transaction = selectedTransaction;
    if (transaction == null) {
      return const TransactionApiResult(
        success: false,
        message: 'No transaction selected',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final devicePrinter = await DevicePrinterSettings.load();
    final printerHost = prefs.getString('printer_host') ?? '';
    final store = await ReceiptStoreConfig.loadFromPrefs();
    final printer = devicePrinter.hasLocalConfig
        ? devicePrinter.config
        : (printerHost.trim().isNotEmpty
            ? PrinterConfig(host: printerHost.trim())
            : null);

    return service.reprintReceipt(
      transaction: transaction,
      printer: printer,
      printerHost: printer == null ? printerHost : null,
      store: store,
    );
  }
}

class _TransactionSidebar extends StatelessWidget {
  const _TransactionSidebar({required this.state});

  final TransactionState state;

  @override
  Widget build(BuildContext context) {
    final groups = state.groupedTransactions;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: groups.isEmpty
          ? const Center(child: Text('No orders found.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        group.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    for (final transaction in group.transactions)
                      ListTile(
                        selected:
                            state.selectedTransaction?.id == transaction.id,
                        title: Text(transaction.displayTime),
                        subtitle: Text(transaction.paymentMethod),
                        trailing: Text(
                          '₱${transaction.grandTotal.toStringAsFixed(2)}',
                        ),
                        onTap: () => state.select(transaction),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _TransactionDetailArea extends StatelessWidget {
  const _TransactionDetailArea({
    required this.state,
    required this.isDesktop,
  });

  final TransactionState state;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final transaction = state.selectedTransaction;

    if (transaction == null) {
      return const Center(
        child: Text('Select an order to view details.'),
      );
    }

    return TransactionDetailsWidget(
      transaction: transaction,
      onPrint: () {},
      onReprint: () async {
        final result = await state.reprintSelectedTransaction();
        if (context.mounted) {
          if (result.success) {
            showTopSuccess(context, result.message);
          } else {
            showTopError(context, result.message);
          }
        }
      },
      onRefund: () async {
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

        final apiResult = await state.refundSelectedTransaction(
          reason: result.reason,
          refundType: result.refundType,
          items: result.items,
        );

        if (context.mounted) {
          if (apiResult.success) {
            showTopSuccess(context, apiResult.message);
          } else {
            showTopError(context, apiResult.message);
          }
        }
      },
      onVoid: () {},
      onDownloadPdf: () async {
        await state.service.shareReceiptPdf(transaction);
      },
      onShare: () async {
        await state.service.shareReceiptPdf(transaction);
      },
    );
  }
}
