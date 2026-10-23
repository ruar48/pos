import 'dart:async';
import 'dart:io';

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
  TransactionState({
    required this.service,
    required this.actorUserId,
    this.resolvePrinter,
  });

  final TransactionService service;
  final int? actorUserId;

  /// The printer checkout uses (this tablet's own config, else the store
  /// printer from settings). Without it reprints fall back to the local
  /// device config / legacy `printer_host` only.
  final PrinterConfig Function()? resolvePrinter;

  bool isLoading = false;
  bool isRefunding = false;
  String errorMessage = '';
  String query = '';
  TransactionFilterType filter = TransactionFilterType.all;
  TransactionRecord? selectedTransaction;
  List<TransactionRecord> transactions = [];

  /// Orders from before the default window that were fetched one by one
  /// (receipt search). Reloads fetch them again by id so a refund or
  /// Refresh doesn't make them vanish.
  final Set<int> _outOfWindowIds = {};
  int _loadSeq = 0;
  bool _disposed = false;

  /// [silent] keeps the current list on screen instead of the full-page
  /// spinner (used after a refund so the detail pane stays put).
  /// [selectId] picks the order to keep selected (defaults to the current
  /// one).
  Future<void> loadTransactions({bool silent = false, int? selectId}) async {
    final seq = ++_loadSeq;
    if (!silent) {
      isLoading = true;
      errorMessage = '';
      notifyListeners();
    }

    try {
      final selectedId = selectId ?? selectedTransaction?.id;
      final recent = await service.fetchTransactions();
      final older = await _refetchOutOfWindow(recent);
      if (seq != _loadSeq) return;

      transactions = [...recent, ...older];
      errorMessage = '';

      TransactionRecord? refreshed;
      if (selectedId != null) {
        for (final transaction in transactions) {
          if (transaction.id == selectedId) {
            refreshed = transaction;
            break;
          }
        }
      }
      selectedTransaction = refreshed;
      _syncSelectionWithFilter();
    } catch (error) {
      if (seq != _loadSeq) return;
      errorMessage = describeLoadError(error);
    } finally {
      if (seq == _loadSeq) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<List<TransactionRecord>> _refetchOutOfWindow(
    List<TransactionRecord> recent,
  ) async {
    final recentIds = recent.map((t) => t.id).toSet();
    final missing =
        _outOfWindowIds.where((id) => !recentIds.contains(id)).toList();
    if (missing.isEmpty) return const [];

    final previous = {for (final t in transactions) t.id: t};
    final results = await Future.wait(
      missing.map((id) async {
        try {
          return await service.fetchTransactionDetail(id);
        } catch (_) {
          // Keep the copy we had rather than dropping the order the
          // cashier is working on; the server re-checks any refund anyway.
          return previous[id];
        }
      }),
    );
    return results.whereType<TransactionRecord>().toList();
  }

  Future<void> refresh() => loadTransactions();

  @override
  void notifyListeners() {
    // A load or refund can finish after the Orders page has closed.
    if (_disposed) return;
    super.notifyListeners();
  }

  void select(TransactionRecord transaction) {
    selectedTransaction = transaction;
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    _syncSelectionWithFilter();
    notifyListeners();
    _receiptLookupDebounce?.cancel();
    _receiptLookupDebounce = Timer(const Duration(milliseconds: 600), () {
      if (query == value && filteredTransactions.isEmpty) {
        unawaited(_lookUpOlderReceipt(value));
      }
    });
  }

  Timer? _receiptLookupDebounce;
  int? _pendingReceiptLookup;

  @override
  void dispose() {
    _disposed = true;
    _receiptLookupDebounce?.cancel();
    super.dispose();
  }

  /// Only recent orders are loaded, so a receipt number from before that
  /// window (e.g. "INV-004512" or "4512") is fetched on its own.
  Future<void> _lookUpOlderReceipt(String value) async {
    final match = RegExp(r'^(?:INV|RCP)?[\s#-]*0*(\d+)$', caseSensitive: false)
        .firstMatch(value.trim());
    final orderId = match == null ? null : int.tryParse(match.group(1)!);
    if (orderId == null || orderId <= 0) return;
    if (transactions.any((t) => t.id == orderId)) return;
    if (_pendingReceiptLookup == orderId) return;

    _pendingReceiptLookup = orderId;
    try {
      final found = await service.fetchTransactionDetail(orderId);
      if (found == null || query != value) return;
      if (transactions.any((t) => t.id == found.id)) return;
      _outOfWindowIds.add(found.id);
      transactions = [...transactions, found];
      _syncSelectionWithFilter();
      notifyListeners();
    } catch (_) {
      // Lookup is best-effort; the normal "no match" state still shows.
    } finally {
      if (_pendingReceiptLookup == orderId) _pendingReceiptLookup = null;
    }
  }

  void setFilter(TransactionFilterType value) {
    filter = value;
    _syncSelectionWithFilter();
    notifyListeners();
  }

  /// Keeps the detail pane's selected order in sync with the current
  /// search/filter - without this, searching for a different receipt only
  /// narrows the list on the left while the detail pane on the right kept
  /// showing whatever order (often another cashier's most recent, unrelated
  /// sale) was selected before, until the user explicitly tapped a row.
  void _syncSelectionWithFilter() {
    final filtered = filteredTransactions;
    if (selectedTransaction != null && filtered.contains(selectedTransaction)) {
      return;
    }
    selectedTransaction = filtered.isNotEmpty ? filtered.first : null;
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
        TransactionFilterType.refunded => transaction.hasAnyRefund,
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

  /// Refunds [orderId] (default: the selected order). Only one refund runs
  /// at a time, and [isRefunding] stays true until the order has been
  /// reloaded, so the next refund always sees the new remaining quantities.
  Future<TransactionApiResult> refundSelectedTransaction({
    required String reason,
    required String refundType,
    required List<RefundItemRequest> items,
    String? refundPin,
    int? orderId,
  }) async {
    final targetId = orderId ?? selectedTransaction?.id;
    if (targetId == null) {
      return const TransactionApiResult(
        success: false,
        message: 'No transaction selected',
      );
    }
    if (isRefunding) {
      return const TransactionApiResult(
        success: false,
        message: 'A refund is already being processed - please wait.',
      );
    }

    isRefunding = true;
    notifyListeners();

    TransactionApiResult result;
    try {
      result = await service.processRefund(
        orderId: targetId,
        reason: reason,
        refundType: refundType,
        items: items,
        actorUserId: actorUserId,
        refundPin: refundPin,
      );
    } catch (error) {
      result = TransactionApiResult(
        success: false,
        message: 'Refund failed: $error',
      );
    }

    try {
      // Reload whatever the outcome - after a timeout the refund may still
      // have gone through on the server.
      await loadTransactions(silent: true, selectId: targetId);
    } finally {
      isRefunding = false;
      notifyListeners();
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

    final store = await ReceiptStoreConfig.loadFromPrefs();
    final resolver = resolvePrinter;
    if (resolver != null) {
      return service.reprintReceipt(
        transaction: transaction,
        printer: resolver(),
        store: store,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final devicePrinter = await DevicePrinterSettings.load();
    final printerHost = prefs.getString('printer_host') ?? '';
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

/// Plain-language reason a list load failed (the raw exception text, e.g.
/// "TimeoutException after 0:00:12.000000", means nothing to a cashier).
String describeLoadError(Object error) {
  if (error is TimeoutException) {
    return 'The server took too long to answer.';
  }
  if (error is SocketException) {
    return 'Could not reach the server. Check the connection.';
  }
  if (error is HttpException) return error.message;
  if (error is FormatException) {
    return 'The server sent an unexpected reply.';
  }
  return error.toString();
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
      refunding: state.isRefunding,
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
        if (state.isRefunding) return;
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
          orderId: transaction.id,
          reason: result.reason,
          refundType: result.refundType,
          items: result.items,
        );

        await showRefundOutcome(context.mounted ? context : null, apiResult);
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
