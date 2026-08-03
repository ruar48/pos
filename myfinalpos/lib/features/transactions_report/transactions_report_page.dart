import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/top_toast.dart';
import '../management/widgets/management_widgets.dart';
import '../pos/pages/pos_home_page.dart';
import '../pos/widgets/app_drawer_section.dart';
import '../transactions/refund_dialog.dart';
import '../transactions/refund_pin_dialog.dart';
import '../transactions/transaction_model.dart';
import '../transactions/transaction_service.dart';
import 'transactions_report_models.dart';
import 'transactions_report_service.dart';

class TransactionsReportPage extends StatelessWidget {
  const TransactionsReportPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.transactionReports,
      title: 'Transactions',
      subtitle: 'Sales breakdown by receipt, hour, day, or month',
      scrollBody: false,
      child: TransactionsReportContent(pageState: pageState),
    );
  }
}

class TransactionsReportContent extends StatefulWidget {
  const TransactionsReportContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<TransactionsReportContent> createState() =>
      _TransactionsReportContentState();
}

class _TransactionsReportContentState extends State<TransactionsReportContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TransactionReportService _service;
  late final TransactionService _refundService;
  late DateTime _startDate;
  late DateTime _endDate;

  final _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  TransactionReportResponse? _response;
  int _expandedOrderId = -1;
  int _rowsPerPage = 25;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    _service = TransactionReportService(apiBaseUrl);
    _refundService = TransactionService(apiBaseUrl);
    final now = DateTime.now();
    _endDate = DateTime(now.year, now.month, now.day);
    _startDate = _endDate;
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  TransactionReportTab get _activeTab =>
      TransactionReportTab.values[_tabController.index];

  String get _currency => widget.pageState.settings.currencySymbol;

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _load(page: 1);
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _service.fetch(
        tab: _activeTab,
        start: _startDate,
        end: _endDate,
        page: page,
        perPage: _rowsPerPage,
        search: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _response = response;
        _loading = false;
        _expandedOrderId = -1;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = DateTime(picked.year, picked.month, picked.day);
      } else {
        _endDate = DateTime(picked.year, picked.month, picked.day);
      }
    });
  }

  Future<void> _copyCsv() async {
    final response = _response;
    if (response == null) return;

    final buffer = StringBuffer();
    if (_activeTab == TransactionReportTab.details ||
        _activeTab == TransactionReportTab.transactions) {
      buffer.writeln(
        'Receipt,Date,Time,Cashier,Customer,Payment,Total,Refunded,Discount,Costs,Profits,Items,Status',
      );
      for (final row in response.orderRows) {
        final totalLabel = formatReportMoney(
          _currency,
          row.total,
          status: row.status,
        );
        final costsLabel = formatReportMoney(
          _currency,
          row.costs,
          status: row.status,
        );
        buffer.writeln(
          '${row.receiptNumber},${row.date},${row.time},'
          '"${row.cashierName}","${row.customerName}",${row.paymentMethod},'
          '$totalLabel,${formatRefundColumn(_currency, row.refundedAmount)},${row.discount},$costsLabel,${row.profits},'
          '${row.itemsCount},${row.status}',
        );
      }
    } else {
      buffer.writeln(
        'Period,Gross Sales,Refunded,Net Total,Transactions,Refunded Txns,Items,Discount,Costs,Expenses,Profits,Bank Transfer,Best Seller',
      );
      for (final row in response.periodRows) {
        final currency = _currency;
        buffer.writeln(
          '"${row.label}",'
          '${formatMoney(currency, row.grossTotal)},'
          '${formatRefundColumn(currency, row.refundedAmount)},'
          '${formatReportMoney(currency, row.total, status: row.status)},'
          '${row.transactions},${row.refundedTransactions},${row.items},'
          '${formatReportMoney(currency, row.discount, status: row.status)},'
          '${formatReportMoney(currency, row.costs, status: row.status)},'
          '${formatReportMoney(currency, row.expenses, status: row.status)},'
          '${formatReportMoney(currency, row.profits, status: row.status)},'
          '${formatReportMoney(currency, row.bankTransfer, status: row.status)},'
          '"${row.bestSeller}"',
        );
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    showTopSuccess(context, 'Report copied — paste into Excel or Sheets');
  }

  Future<void> _refundOrder(TransactionReportOrderRow row) async {
    final items = row.items
        .map(
          (item) => TransactionItem(
            id: item.orderItemId,
            orderId: row.id,
            orderItemId: item.orderItemId,
            productId: item.productId,
            productName: item.displayName,
            sku: 'SKU-${item.productId}',
            varietyName: item.varietyName,
            quantity: item.quantity,
            refundedQuantity: item.refundedQuantity,
            unitPrice: item.price,
            discount: 0,
            subtotal: item.total,
            imageUrl: null,
          ),
        )
        .toList();

    final result = await showDialog<RefundDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RefundDialog(
        title: 'Refund Order',
        transactionId: row.id,
        actionLabel: 'Refund',
        items: items,
      ),
    );
    if (result == null) return;
    if (!mounted) return;

    String? refundPin;
    if (widget.pageState.settings.hasRefundPin) {
      refundPin = await showRefundPinDialog(context);
      if (refundPin == null) return;
      if (!mounted) return;
    }

    final apiResult = await _refundService.processRefund(
      orderId: row.id,
      reason: result.reason,
      refundType: result.refundType,
      items: result.items,
      actorUserId: widget.pageState.widget.currentUser.id,
      refundPin: refundPin,
    );

    if (!mounted) return;
    if (apiResult.success) {
      await widget.pageState.refreshProductCatalog();
      if (!mounted) return;
      showTopSuccess(context, apiResult.message);
      await _load(page: _response?.pagination.page ?? 1);
    } else {
      showTopError(context, apiResult.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar(
          startDate: _startDate,
          endDate: _endDate,
          searchController: _searchController,
          showSearch: _activeTab == TransactionReportTab.details ||
              _activeTab == TransactionReportTab.transactions,
          onPickStart: () => _pickDate(isStart: true),
          onPickEnd: () => _pickDate(isStart: false),
          onGo: () => _load(page: 1),
          onDownload: _copyCsv,
          loading: _loading,
        ),
        Material(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppColors.darkGreen,
            unselectedLabelColor: AppColors.muted,
            indicatorColor: AppColors.green,
            tabs: [
              for (final tab in TransactionReportTab.values)
                Tab(text: tab.label),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _load(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final response = _response;
    if (response == null) {
      return const Center(child: Text('No data'));
    }

    return Column(
      children: [
        _PaginationBar(
          pagination: response.pagination,
          rowsPerPage: _rowsPerPage,
          onRowsPerPageChanged: (value) {
            setState(() => _rowsPerPage = value);
            _load(page: 1);
          },
          onPrevious: response.pagination.page > 1
              ? () => _load(page: response.pagination.page - 1)
              : null,
          onNext: response.pagination.page < response.pagination.totalPages
              ? () => _load(page: response.pagination.page + 1)
              : null,
        ),
        Expanded(
          child: switch (_activeTab) {
            TransactionReportTab.details => _DetailsTable(
                rows: response.orderRows,
                currency: _currency,
                expandedOrderId: _expandedOrderId,
                onToggle: (id) => setState(
                  () => _expandedOrderId = _expandedOrderId == id ? -1 : id,
                ),
                onRefund: _refundOrder,
              ),
            TransactionReportTab.transactions => _TransactionsTable(
                rows: response.orderRows,
                currency: _currency,
              ),
            _ => _PeriodTable(
                rows: response.periodRows,
                currency: _currency,
                periodLabel: switch (_activeTab) {
                  TransactionReportTab.hourly => 'Hour',
                  TransactionReportTab.daily => 'Day',
                  TransactionReportTab.monthly => 'Month',
                  _ => 'Period',
                },
                showBestSeller: _activeTab == TransactionReportTab.hourly,
              ),
          },
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.startDate,
    required this.endDate,
    required this.searchController,
    required this.showSearch,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onGo,
    required this.onDownload,
    required this.loading,
  });

  final DateTime startDate;
  final DateTime endDate;
  final TextEditingController searchController;
  final bool showSearch;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onGo;
  final VoidCallback onDownload;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    String formatDate(DateTime date) {
      final d = date.day.toString().padLeft(2, '0');
      final m = date.month.toString().padLeft(2, '0');
      return '$d/$m/${date.year}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DateChip(label: 'From', value: formatDate(startDate), onTap: onPickStart),
              _DateChip(label: 'To', value: formatDate(endDate), onTap: onPickEnd),
              FilledButton(
                onPressed: loading ? null : onGo,
                child: const Text('Go'),
              ),
              OutlinedButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download'),
              ),
              if (showSearch)
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Search receipt, cashier, customer…',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                    onSubmitted: (_) => onGo(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Transactions can be viewed for a maximum 2-month date range.',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
          color: AppColors.softSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label ',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pagination,
    required this.rowsPerPage,
    required this.onRowsPerPageChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final TransactionReportPagination pagination;
  final int rowsPerPage;
  final ValueChanged<int> onRowsPerPageChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.lightGreen.withValues(alpha: 0.35),
      child: Row(
        children: [
          Text(
            'Page ${pagination.page} of ${pagination.totalPages == 0 ? 1 : pagination.totalPages}'
            ' • ${pagination.total} records',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.darkGreen,
            ),
          ),
          const Spacer(),
          DropdownButton<int>(
            value: rowsPerPage,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 10, child: Text('10 rows')),
              DropdownMenuItem(value: 25, child: Text('25 rows')),
              DropdownMenuItem(value: 50, child: Text('50 rows')),
            ],
            onChanged: (value) {
              if (value != null) onRowsPerPageChanged(value);
            },
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onPrevious, child: const Text('Previous')),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: onNext, child: const Text('Next')),
        ],
      ),
    );
  }
}

class _ReportTableShell extends StatelessWidget {
  const _ReportTableShell({required this.headers, required this.rows});

  final List<String> headers;
  final List<TableRow> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: {
                for (var i = 0; i < headers.length; i++)
                  i: const IntrinsicColumnWidth(),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.12),
                  ),
                  children: [
                    for (final header in headers)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          header,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: AppColors.darkGreen,
                          ),
                        ),
                      ),
                  ],
                ),
                ...rows,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TableCell _cell(
  String text, {
  Color? color,
  FontWeight weight = FontWeight.w500,
  int maxLines = 2,
}) {
  return TableCell(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: weight,
          color: color ?? AppColors.text,
        ),
      ),
    ),
  );
}

TableCell _moneyCell(
  String currency,
  double value, {
  Color? color,
  String status = 'completed',
}) {
  final refunded = shouldShowRefundedAmount(status, value);
  return _cell(
    formatReportMoney(currency, value, status: status),
    color: refunded ? AppColors.muted : color,
    weight: FontWeight.w700,
  );
}

class _DetailsTable extends StatelessWidget {
  const _DetailsTable({
    required this.rows,
    required this.currency,
    required this.expandedOrderId,
    required this.onToggle,
    required this.onRefund,
  });

  final List<TransactionReportOrderRow> rows;
  final String currency;
  final int expandedOrderId;
  final ValueChanged<int> onToggle;
  final Future<void> Function(TransactionReportOrderRow) onRefund;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('No transactions in this date range.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        final expanded = expandedOrderId == row.id;
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onToggle(row.id),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: expanded ? AppColors.green : AppColors.border,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Row(
                      children: [
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.receiptNumber,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${row.date} • ${row.time} • ${row.cashierName}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatReportMoney(currency, row.total, status: row.status),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: row.status == 'refunded'
                                ? AppColors.muted
                                : AppColors.darkGreen,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (row.canRefund)
                          FilledButton.tonal(
                            onPressed: () => onRefund(row),
                            child: const Text('Refund'),
                          ),
                      ],
                    ),
                  ),
                  if (expanded) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.customerName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            row.itemsSummary,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: [
                              _meta('Payment', row.paymentMethod),
                              _meta('Discount', formatMoney(currency, row.discount)),
                              _meta('Costs', formatMoney(currency, row.costs)),
                              _meta('Profit', formatMoney(currency, row.profits)),
                              _meta('Items', '${row.itemsCount}'),
                              _meta('Status', row.status),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _meta(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionsTable extends StatelessWidget {
  const _TransactionsTable({required this.rows, required this.currency});

  final List<TransactionReportOrderRow> rows;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('No transactions in this date range.'));
    }

    return _ReportTableShell(
      headers: const [
        'Date',
        'Time',
        'Receipt',
        'Cashier',
        'Items',
        'Total',
        'Refunded',
        'Costs',
      ],
      rows: [
        for (final row in rows)
          TableRow(
            decoration: BoxDecoration(
              color: rows.indexOf(row).isEven
                  ? AppColors.softSurface
                  : AppColors.surface,
            ),
            children: [
              _cell(row.date),
              _cell(row.time),
              _cell(row.receiptNumber, weight: FontWeight.w800),
              _cell(row.cashierName),
              _cell(row.itemsSummary, maxLines: 4),
              _moneyCell(currency, row.total, status: row.status),
              _cell(
                formatRefundColumn(currency, row.refundedAmount),
                color: row.refundedAmount > 0 ? AppColors.amber : AppColors.muted,
                weight: FontWeight.w700,
              ),
              _moneyCell(currency, row.costs, status: row.status),
            ],
          ),
      ],
    );
  }
}

class _PeriodTable extends StatelessWidget {
  const _PeriodTable({
    required this.rows,
    required this.currency,
    required this.periodLabel,
    required this.showBestSeller,
  });

  final List<TransactionReportPeriodRow> rows;
  final String currency;
  final String periodLabel;
  final bool showBestSeller;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('No data in this date range.'));
    }

    final headers = [
      periodLabel,
      'Gross',
      'Refunded',
      'Net',
      'Transactions',
      'Refunded Txns',
      'Items',
      'Discount',
      'Costs',
      'Expenses',
      'Profits',
      'Bank Transfer',
      if (showBestSeller) 'Best Seller',
    ];

    return _ReportTableShell(
      headers: headers,
      rows: [
        for (final row in rows)
          TableRow(
            decoration: BoxDecoration(
              color: rows.indexOf(row).isEven
                  ? AppColors.softSurface
                  : AppColors.surface,
            ),
            children: [
              _cell(row.label, weight: FontWeight.w800),
              _moneyCell(currency, row.grossTotal),
              _cell(
                formatRefundColumn(currency, row.refundedAmount),
                color: row.refundedAmount > 0 ? AppColors.amber : AppColors.muted,
                weight: FontWeight.w700,
              ),
              _moneyCell(currency, row.total, status: row.status),
              _cell('${row.transactions}'),
              _cell(
                row.refundedTransactions > 0 ? '${row.refundedTransactions}' : '—',
                color: row.refundedTransactions > 0 ? AppColors.amber : AppColors.muted,
              ),
              _cell(row.items.toStringAsFixed(1)),
              _moneyCell(currency, row.discount, status: row.status),
              _moneyCell(currency, row.costs, status: row.status),
              _moneyCell(currency, row.expenses, status: row.status),
              _moneyCell(
                currency,
                row.profits,
                status: row.status,
                color: row.profits >= 0 ? AppColors.green : AppColors.danger,
              ),
              _moneyCell(currency, row.bankTransfer, status: row.status),
              if (showBestSeller) _cell(row.bestSeller, maxLines: 2),
            ],
          ),
      ],
    );
  }
}
