import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/agri_admin_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/inventory_report.dart';
import '../../../models/product.dart';
import '../../pos/pages/pos_home_page.dart';
import '../../pos/widgets/product_section.dart';
import 'catalog_table_widgets.dart';

enum _StockFilter { all, low, outOfStock }

enum _InventoryRange { today, yesterday, week, month }

Future<void> showAdjustStockDialog(
  BuildContext context,
  PosHomePageState pageState, {
  required Product product,
  VoidCallback? onSaved,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AdjustStockDialog(
      pageState: pageState,
      product: product,
      onSaved: onSaved,
    ),
  );
}

class InventoryManagementContent extends StatefulWidget {
  const InventoryManagementContent({
    super.key,
    required this.pageState,
    this.onRefresh,
  });

  final PosHomePageState pageState;
  final VoidCallback? onRefresh;

  @override
  State<InventoryManagementContent> createState() =>
      _InventoryManagementContentState();
}

class _InventoryManagementContentState extends State<InventoryManagementContent> {
  final searchController = TextEditingController();
  String selectedCategory = 'All';
  _StockFilter stockFilter = _StockFilter.all;
  _InventoryRange rangeKey = _InventoryRange.today;
  InventoryReport? report;
  bool loadingReport = false;
  String? reportError;

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
    unawaited(_loadReport());
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  ({String start, String end}) _rangeForKey(_InventoryRange key) {
    final today = DateTime.now();
    switch (key) {
      case _InventoryRange.today:
        final iso = _isoDate(today);
        return (start: iso, end: iso);
      case _InventoryRange.yesterday:
        final y = today.subtract(const Duration(days: 1));
        final iso = _isoDate(y);
        return (start: iso, end: iso);
      case _InventoryRange.week:
        final weekday = today.weekday;
        final monday = today.subtract(Duration(days: weekday - 1));
        return (start: _isoDate(monday), end: _isoDate(today));
      case _InventoryRange.month:
        final first = DateTime(today.year, today.month, 1);
        return (start: _isoDate(first), end: _isoDate(today));
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      loadingReport = true;
      reportError = null;
    });
    try {
      final range = _rangeForKey(rangeKey);
      final payload = await widget.pageState.api.fetchInventoryReport(
        start: range.start,
        end: range.end,
      );
      if (!mounted) return;
      setState(() {
        report = payload;
        loadingReport = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        reportError = cleanApiErrorMessage(error.toString());
        loadingReport = false;
      });
    }
  }

  List<InventoryReportRow> get filteredReportRows {
    final query = searchController.text.trim().toLowerCase();
    final rows = report?.rows ?? const <InventoryReportRow>[];
    return rows.where((row) {
      final matchesCategory =
          selectedCategory == 'All' || row.category == selectedCategory;
      final matchesSearch = query.isEmpty ||
          row.name.toLowerCase().contains(query) ||
          (row.sku ?? '').toLowerCase().contains(query) ||
          row.category.toLowerCase().contains(query);
      final matchesFilter = switch (stockFilter) {
        _StockFilter.all => true,
        _StockFilter.low => row.isLowStock && !row.isOutOfStock,
        _StockFilter.outOfStock => row.isOutOfStock,
      };
      return matchesCategory && matchesSearch && matchesFilter;
    }).toList()
      ..sort((a, b) => a.ending.compareTo(b.ending));
  }

  Product? _productForRow(InventoryReportRow row) {
    for (final product in widget.pageState.products) {
      if (product.id == row.productId) return product;
    }
    return null;
  }

  ({int beginning, int added, int deducted, int ending, double valueCost, double valueRetail})
      _totalsForRows(List<InventoryReportRow> rows) {
    var beginning = 0;
    var added = 0;
    var deducted = 0;
    var ending = 0;
    var valueCost = 0.0;
    var valueRetail = 0.0;
    for (final row in rows) {
      beginning += row.beginning;
      added += row.added;
      deducted += row.deducted;
      ending += row.ending;
      valueCost += row.valueCost;
      valueRetail += row.valueRetail;
    }
    return (
      beginning: beginning,
      added: added,
      deducted: deducted,
      ending: ending,
      valueCost: valueCost,
      valueRetail: valueRetail,
    );
  }

  void _exportCsv(List<InventoryReportRow> rows) {
    if (rows.isEmpty) {
      showTopWarning(context, 'Nothing to export');
      return;
    }
    final lines = <String>[
      'Item,SKU,Category,Beginning,Added,Deducted,Current,Stock Value',
    ];
    for (final row in rows) {
      lines.add(
        '"${row.name}","${row.sku ?? ''}","${row.category}",${row.beginning},${row.added},${row.deducted},${row.liveStock},${row.valueRetail.toStringAsFixed(2)}',
      );
    }
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    showAppTopSuccess('Inventory copied to clipboard (${rows.length} items)');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.pageState.catalogRevision,
      builder: (context, _, __) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final currency = widget.pageState.settings.currencySymbol;
    final reportRows = filteredReportRows;
    final totals = report?.totals;
    final filteredTotals = _totalsForRows(reportRows);
    final range = _rangeForKey(rangeKey);
    final categories = [
      'All',
      if (report != null)
        ...{
          for (final row in report!.rows) row.category,
        }.toList()
          ..sort()
      else
        ...widget.pageState.categories.map((item) => item.name),
    ];

    const colNum = 72.0;
    const colValue = 140.0;
    const colAction = 96.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
        AgriPageHeader(
          badge: 'Inventory',
          title: 'Inventory Control',
          description:
              'Track beginning, added, deducted and current stock for any day — with live valuation, low-stock alerts and category roll-ups. One ledger across tablet and web.',
          actions: [
            OutlinedButton.icon(
              onPressed: loadingReport ? null : () => unawaited(_loadReport()),
              icon: loadingReport
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _exportCsv(reportRows),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AgriCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in <(_InventoryRange, String)>[
                    (_InventoryRange.today, 'Today'),
                    (_InventoryRange.yesterday, 'Yesterday'),
                    (_InventoryRange.week, 'This Week'),
                    (_InventoryRange.month, 'This Month'),
                  ])
                    AgriRangePill(
                      label: entry.$2,
                      selected: rangeKey == entry.$1,
                      onTap: () {
                        setState(() => rangeKey = entry.$1);
                        unawaited(_loadReport());
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'From ${range.start}  ·  To ${range.end}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final cards = [
              AgriStatCard(
                label: 'Inventory Value',
                value: formatMoney(currency, totals?.valueRetail ?? 0),
                icon: Icons.warehouse_outlined,
                tone: AgriStatTone.positive,
                hint: report != null
                    ? 'Prices as of ${report!.valuationAsOf} · cost ${formatMoney(currency, totals?.valueCost ?? 0)}'
                    : null,
              ),
              AgriStatCard(
                label: 'Potential Margin',
                value: formatMoney(currency, totals?.valueMargin ?? 0),
                icon: Icons.trending_up,
                tone: AgriStatTone.positive,
                hint: 'Retail value minus cost',
              ),
              AgriStatCard(
                label: 'Units Sold',
                value: '${totals?.sold ?? 0}',
                icon: Icons.payments_outlined,
                tone: AgriStatTone.positive,
                hint: rangeKey == _InventoryRange.today ||
                        rangeKey == _InventoryRange.yesterday
                    ? 'On selected day'
                    : 'In selected range',
              ),
              AgriStatCard(
                label: 'Stock Alerts',
                value: '${(totals?.lowStock ?? 0) + (totals?.outOfStock ?? 0)}',
                icon: Icons.warning_amber_rounded,
                tone: (totals?.outOfStock ?? 0) > 0
                    ? AgriStatTone.danger
                    : (totals?.lowStock ?? 0) > 0
                        ? AgriStatTone.warning
                        : AgriStatTone.neutral,
                hint:
                    '${totals?.lowStock ?? 0} low varieties/items · ${totals?.outOfStock ?? 0} out',
              ),
            ];

            if (isWide) {
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(width: 220, height: 132, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search items, SKU or category...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 200,
                  child: AgriFilterDropdown<String>(
                    value: selectedCategory,
                    width: 200,
                    items: [
                      for (final category in categories)
                        DropdownMenuItem(
                          value: category,
                          child: Text(
                            category == 'All' ? 'All categories' : category,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedCategory = value);
                    },
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: AgriFilterDropdown<_StockFilter>(
                    value: stockFilter,
                    width: 160,
                    items: const [
                      DropdownMenuItem(
                        value: _StockFilter.all,
                        child: Text('All stock'),
                      ),
                      DropdownMenuItem(
                        value: _StockFilter.low,
                        child: Text('Low stock'),
                      ),
                      DropdownMenuItem(
                        value: _StockFilter.outOfStock,
                        child: Text('Out of stock'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => stockFilter = value);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (reportError != null)
          AgriCard(
            padding: const EdgeInsets.all(16),
            child: Text(reportError!, style: const TextStyle(color: AppColors.danger)),
          )
        else
          AgriCatalogTable(
            minWidth: 920,
            loading: loadingReport && report == null,
            header: AgriTableHeaderRow(
              cells: const [
                AgriTableHeaderCell(label: 'Item', flex: true),
                AgriTableHeaderCell(label: 'Beginning', width: colNum, align: TextAlign.right),
                AgriTableHeaderCell(label: 'Added', width: colNum, align: TextAlign.right),
                AgriTableHeaderCell(label: 'Deducted', width: colNum, align: TextAlign.right),
                AgriTableHeaderCell(label: 'Current', width: colNum, align: TextAlign.right),
                AgriTableHeaderCell(label: 'Stock Value', width: colValue, align: TextAlign.right),
                AgriTableHeaderCell(label: '', width: colAction, align: TextAlign.right),
              ],
            ),
            rows: [
              for (final row in reportRows)
                AgriTableDataRow(
                  cells: [
                    AgriTableCell(
                      flex: true,
                      child: Row(
                        children: [
                          _InventoryThumb(row: row, product: _productForRow(row)),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                  ),
                                ),
                                Text(
                                  '${row.category} · ${row.sku ?? 'No SKU'}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AgriTableCell(
                      width: colNum,
                      align: Alignment.centerRight,
                      child: Text('${row.beginning}'),
                    ),
                    AgriTableCell(
                      width: colNum,
                      align: Alignment.centerRight,
                      child: Text(
                        '${row.added}',
                        style: const TextStyle(
                          color: AppColors.green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AgriTableCell(
                      width: colNum,
                      align: Alignment.centerRight,
                      child: Text(
                        row.deducted > 0 ? '-${row.deducted}' : '${row.deducted}',
                        style: const TextStyle(
                          color: AppColors.orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AgriTableCell(
                      width: colNum,
                      align: Alignment.centerRight,
                      child: Text(
                        '${row.liveStock} ${row.unit ?? 'pc'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    AgriTableCell(
                      width: colValue,
                      align: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatMoney(currency, row.valueRetail),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'cost ${formatMoney(currency, row.valueCost)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.muted),
                          ),
                          Text(
                            'tubo ${formatMoney(currency, row.valueMargin)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AgriTableCell(
                      width: colAction,
                      align: Alignment.centerRight,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: const Size(72, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          final product = _productForRow(row);
                          if (product == null) {
                            showTopWarning(context, 'Product not found in catalog');
                            return;
                          }
                          showAdjustStockDialog(
                            context,
                            widget.pageState,
                            product: product,
                            onSaved: () {
                              setState(() {});
                              widget.onRefresh?.call();
                              unawaited(_loadReport());
                            },
                          );
                        },
                        child: const Text(
                          'Adjust',
                          softWrap: false,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
            footer: reportRows.isEmpty
                ? null
                : AgriTableFooterRow(
                    cells: [
                      AgriTableCell(
                        flex: true,
                        child: Text(
                          '${reportRows.length} item${reportRows.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      AgriTableCell(
                        width: colNum,
                        align: Alignment.centerRight,
                        child: Text('${filteredTotals.beginning}'),
                      ),
                      AgriTableCell(
                        width: colNum,
                        align: Alignment.centerRight,
                        child: Text(
                          '${filteredTotals.added}',
                          style: const TextStyle(color: AppColors.green),
                        ),
                      ),
                      AgriTableCell(
                        width: colNum,
                        align: Alignment.centerRight,
                        child: Text(
                          '${filteredTotals.deducted}',
                          style: const TextStyle(color: AppColors.orange),
                        ),
                      ),
                      AgriTableCell(
                        width: colNum,
                        align: Alignment.centerRight,
                        child: Text('${filteredTotals.ending}'),
                      ),
                      AgriTableCell(
                        width: colValue,
                        align: Alignment.centerRight,
                        child: Text(
                          formatMoney(currency, filteredTotals.valueRetail),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const AgriTableCell(width: colAction, child: SizedBox.shrink()),
                    ],
                  ),
            empty: const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 40, color: AppColors.muted),
                  SizedBox(height: 10),
                  Text('No items match your filters'),
                ],
              ),
            ),
          ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InventoryThumb extends StatelessWidget {
  const _InventoryThumb({required this.row, this.product});

  final InventoryReportRow row;
  final Product? product;

  @override
  Widget build(BuildContext context) {
    final imageUrl = resolveProductImageUrl(row.imageUrl ?? product?.imageUrl);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 36,
        height: 36,
        child: ColoredBox(
          color: AppColors.lightGreen,
          child: imageUrl == null
              ? ProductCategoryIconFallback(category: row.category)
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      ProductCategoryIconFallback(category: row.category),
                ),
        ),
      ),
    );
  }
}

class _AdjustStockDialog extends StatefulWidget {
  const _AdjustStockDialog({
    required this.pageState,
    required this.product,
    this.onSaved,
  });

  final PosHomePageState pageState;
  final Product product;
  final VoidCallback? onSaved;

  @override
  State<_AdjustStockDialog> createState() => _AdjustStockDialogState();
}

class _AdjustStockDialogState extends State<_AdjustStockDialog> {
  late final TextEditingController stockController;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    stockController = TextEditingController(
      text: formatQuantity(widget.product.stock ?? 0),
    );
  }

  @override
  void dispose() {
    stockController.dispose();
    super.dispose();
  }

  double get _currentInput => double.tryParse(stockController.text.trim()) ?? 0;

  void _adjustBy(int delta) {
    final next = (_currentInput + delta).clamp(0, 999999);
    stockController.text = formatQuantity(next);
    setState(() {});
  }

  Future<void> _save() async {
    final newStock = double.tryParse(stockController.text.trim());
    if (newStock == null || newStock < 0) {
      showTopWarning(context, 'Enter a valid stock quantity.');
      return;
    }

    setState(() => saving = true);
    try {
      await widget.pageState.updateManagedStock(
        productId: widget.product.id,
        stock: newStock,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved?.call();
      showAppTopSuccess(
        'Stock updated: ${widget.product.name} → $newStock ${widget.product.displayUnit}',
      );
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final unit = product.displayUnit;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.warehouse_outlined, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Adjust Stock',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              product.name,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              product.sku ?? 'No SKU',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: stockController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
              ],
              decoration: InputDecoration(
                labelText: 'Stock Quantity',
                suffixText: unit,
                prefixIcon: const Icon(Icons.inventory_2_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickAdjustChip(label: '-10', onTap: () => _adjustBy(-10)),
                _QuickAdjustChip(label: '-1', onTap: () => _adjustBy(-1)),
                _QuickAdjustChip(label: '+1', onTap: () => _adjustBy(1)),
                _QuickAdjustChip(label: '+10', onTap: () => _adjustBy(10)),
                _QuickAdjustChip(label: '+50', onTap: () => _adjustBy(50)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving...' : 'Update Stock'),
        ),
      ],
    );
  }
}

class _QuickAdjustChip extends StatelessWidget {
  const _QuickAdjustChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: AppColors.lightGreen,
      side: const BorderSide(color: AppColors.greenBorder),
    );
  }
}
