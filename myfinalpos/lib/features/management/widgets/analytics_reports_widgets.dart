import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/branch.dart';
import '../../../models/product.dart';
import '../../../models/sales_history_record.dart';
import '../../../services/analytics_engine.dart';
import '../../pos/pages/pos_home_page.dart';
import 'management_widgets.dart';

class AnalyticsReportsContent extends StatefulWidget {
  const AnalyticsReportsContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<AnalyticsReportsContent> createState() =>
      _AnalyticsReportsContentState();
}

class _AnalyticsReportsContentState extends State<AnalyticsReportsContent> {
  AnalyticsReportType reportType = AnalyticsReportType.salesSummary;
  AnalyticsPeriodPreset periodPreset = AnalyticsPeriodPreset.thisMonth;
  AnalyticsPeriodPreset comparePresetA = AnalyticsPeriodPreset.today;
  AnalyticsPeriodPreset comparePresetB = AnalyticsPeriodPreset.yesterday;
  AnalyticsTrendGranularity granularity = AnalyticsTrendGranularity.day;
  DateTime? customStart;
  DateTime? customEnd;
  DateTime? compareCustomStartA;
  DateTime? compareCustomEndA;
  DateTime? compareCustomStartB;
  DateTime? compareCustomEndB;
  final Set<int> selectedBranchIds = {};
  int? compareBranchIdA;
  int? compareBranchIdB;
  bool bestSellersByRevenue = false;
  bool reportGenerated = false;
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    _ensureBranchCompareDefaults();
  }

  void _ensureBranchCompareDefaults() {
    final branches = widget.pageState.branches;
    if (branches.isEmpty) return;
    compareBranchIdA ??= branches.first.id;
    compareBranchIdB ??=
        branches.length > 1 ? branches[1].id : branches.first.id;
  }

  String get currency => widget.pageState.settings.currencySymbol;

  Map<int, String> get branchNames => {
        for (final branch in widget.pageState.branches) branch.id: branch.name,
      };

  Set<int>? get activeBranchFilter =>
      selectedBranchIds.isEmpty ? null : Set<int>.from(selectedBranchIds);

  AnalyticsDateRange get primaryRange => AnalyticsEngine.rangeForPreset(
        periodPreset,
        customStart: customStart,
        customEnd: customEnd,
      );

  Future<void> _refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.pageState.reloadAnalyticsData();
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> _pickDate({
    required bool isStart,
    required bool isCompareA,
    bool compareB = false,
  }) async {
    final initial = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (reportType == AnalyticsReportType.periodComparison) {
        if (compareB) {
          if (isStart) {
            compareCustomStartB = picked;
          } else {
            compareCustomEndB = picked;
          }
        } else {
          if (isStart) {
            compareCustomStartA = picked;
          } else {
            compareCustomEndA = picked;
          }
        }
      } else {
        if (isStart) {
          customStart = picked;
        } else {
          customEnd = picked;
        }
        periodPreset = AnalyticsPeriodPreset.custom;
      }
    });
  }

  bool _canGenerateReport() {
    if (reportType == AnalyticsReportType.periodComparison) {
      if (comparePresetA == AnalyticsPeriodPreset.custom &&
          (compareCustomStartA == null || compareCustomEndA == null)) {
        return false;
      }
      if (comparePresetB == AnalyticsPeriodPreset.custom &&
          (compareCustomStartB == null || compareCustomEndB == null)) {
        return false;
      }
    } else if (periodPreset == AnalyticsPeriodPreset.custom &&
        (customStart == null || customEnd == null)) {
      return false;
    }

    if (reportType == AnalyticsReportType.branchComparison) {
      _ensureBranchCompareDefaults();
      return compareBranchIdA != null &&
          compareBranchIdB != null &&
          widget.pageState.branches.isNotEmpty;
    }

    return true;
  }

  void _generateReport() {
    if (!_canGenerateReport()) {
      showTopWarning(
        context,
        'Pick a complete custom date range (From and To), or select both branches.',
      );
      return;
    }
    setState(() => reportGenerated = true);
  }

  void _applyQuickComparison(String mode) {
    setState(() {
      switch (mode) {
        case 'day':
          comparePresetA = AnalyticsPeriodPreset.today;
          comparePresetB = AnalyticsPeriodPreset.yesterday;
        case 'week':
          comparePresetA = AnalyticsPeriodPreset.thisWeek;
          comparePresetB = AnalyticsPeriodPreset.lastWeek;
        case 'month':
          comparePresetA = AnalyticsPeriodPreset.thisMonth;
          comparePresetB = AnalyticsPeriodPreset.lastMonth;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportBuilderPanel(
          reportType: reportType,
          periodPreset: periodPreset,
          comparePresetA: comparePresetA,
          comparePresetB: comparePresetB,
          granularity: granularity,
          customStart: customStart,
          customEnd: customEnd,
          compareCustomStartA: compareCustomStartA,
          compareCustomEndA: compareCustomEndA,
          compareCustomStartB: compareCustomStartB,
          compareCustomEndB: compareCustomEndB,
          branches: widget.pageState.branches,
          selectedBranchIds: selectedBranchIds,
          bestSellersByRevenue: bestSellersByRevenue,
          refreshing: refreshing,
          compareBranchIdA: compareBranchIdA,
          compareBranchIdB: compareBranchIdB,
          records: widget.pageState.salesHistory,
          currency: currency,
          primaryRange: primaryRange,
          branchFilter: activeBranchFilter,
          branchNames: branchNames,
          onReportTypeChanged: (value) => setState(() {
            reportType = value;
            reportGenerated = false;
            if (value == AnalyticsReportType.branchComparison) {
              _ensureBranchCompareDefaults();
            }
          }),
          onCompareBranchAChanged: (value) =>
              setState(() => compareBranchIdA = value),
          onCompareBranchBChanged: (value) =>
              setState(() => compareBranchIdB = value),
          onPeriodChanged: (value) => setState(() {
            periodPreset = value;
            reportGenerated = false;
          }),
          onCompareAChanged: (value) => setState(() => comparePresetA = value),
          onCompareBChanged: (value) => setState(() => comparePresetB = value),
          onGranularityChanged: (value) => setState(() => granularity = value),
          onBranchToggled: (branchId) => setState(() {
            if (branchId < 0) {
              selectedBranchIds.clear();
            } else if (selectedBranchIds.contains(branchId)) {
              selectedBranchIds.remove(branchId);
            } else {
              selectedBranchIds.add(branchId);
            }
            reportGenerated = false;
          }),
          onBestSellerMetricChanged: (value) =>
              setState(() => bestSellersByRevenue = value),
          onQuickComparison: _applyQuickComparison,
          onPickDate: _pickDate,
          onRefresh: _refresh,
          onGenerate: _generateReport,
        ),
        if (reportGenerated) ...[
          const SizedBox(height: 16),
          _ReportResults(
            reportType: reportType,
            currency: currency,
            records: widget.pageState.salesHistory,
            products: widget.pageState.products,
            branchNames: branchNames,
            branchFilter: activeBranchFilter,
            compareBranchIdA: compareBranchIdA,
            compareBranchIdB: compareBranchIdB,
            primaryRange: primaryRange,
            periodPreset: periodPreset,
            comparePresetA: comparePresetA,
            comparePresetB: comparePresetB,
            compareCustomStartA: compareCustomStartA,
            compareCustomEndA: compareCustomEndA,
            compareCustomStartB: compareCustomStartB,
            compareCustomEndB: compareCustomEndB,
            granularity: granularity,
            bestSellersByRevenue: bestSellersByRevenue,
          ),
        ],
      ],
    );
  }
}

class _ReportBuilderPanel extends StatelessWidget {
  const _ReportBuilderPanel({
    required this.reportType,
    required this.periodPreset,
    required this.comparePresetA,
    required this.comparePresetB,
    required this.granularity,
    required this.customStart,
    required this.customEnd,
    required this.compareCustomStartA,
    required this.compareCustomEndA,
    required this.compareCustomStartB,
    required this.compareCustomEndB,
    required this.branches,
    required this.selectedBranchIds,
    required this.compareBranchIdA,
    required this.compareBranchIdB,
    required this.records,
    required this.currency,
    required this.primaryRange,
    required this.branchFilter,
    required this.branchNames,
    required this.bestSellersByRevenue,
    required this.refreshing,
    required this.onReportTypeChanged,
    required this.onCompareBranchAChanged,
    required this.onCompareBranchBChanged,
    required this.onPeriodChanged,
    required this.onCompareAChanged,
    required this.onCompareBChanged,
    required this.onGranularityChanged,
    required this.onBranchToggled,
    required this.onBestSellerMetricChanged,
    required this.onQuickComparison,
    required this.onPickDate,
    required this.onRefresh,
    required this.onGenerate,
  });

  final AnalyticsReportType reportType;
  final AnalyticsPeriodPreset periodPreset;
  final AnalyticsPeriodPreset comparePresetA;
  final AnalyticsPeriodPreset comparePresetB;
  final AnalyticsTrendGranularity granularity;
  final DateTime? customStart;
  final DateTime? customEnd;
  final DateTime? compareCustomStartA;
  final DateTime? compareCustomEndA;
  final DateTime? compareCustomStartB;
  final DateTime? compareCustomEndB;
  final List<Branch> branches;
  final Set<int> selectedBranchIds;
  final int? compareBranchIdA;
  final int? compareBranchIdB;
  final List<SalesHistoryRecord> records;
  final String currency;
  final AnalyticsDateRange primaryRange;
  final Set<int>? branchFilter;
  final Map<int, String> branchNames;
  final bool bestSellersByRevenue;
  final bool refreshing;
  final ValueChanged<AnalyticsReportType> onReportTypeChanged;
  final ValueChanged<int?> onCompareBranchAChanged;
  final ValueChanged<int?> onCompareBranchBChanged;
  final ValueChanged<AnalyticsPeriodPreset> onPeriodChanged;
  final ValueChanged<AnalyticsPeriodPreset> onCompareAChanged;
  final ValueChanged<AnalyticsPeriodPreset> onCompareBChanged;
  final ValueChanged<AnalyticsTrendGranularity> onGranularityChanged;
  final ValueChanged<int> onBranchToggled;
  final ValueChanged<bool> onBestSellerMetricChanged;
  final ValueChanged<String> onQuickComparison;
  final Future<void> Function({
    required bool isStart,
    required bool isCompareA,
    bool compareB,
  }) onPickDate;
  final VoidCallback onRefresh;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sales Numbers',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Set your dates and filters. Your sales totals appear below before you view the full report.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.lightGreen,
                  foregroundColor: AppColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: AnalyticsReportType.values.map((type) {
              final meta = _reportMeta(type);
              final selected = reportType == type;
              return ChoiceChip(
                label: Text(meta.label),
                avatar: Icon(
                  meta.icon,
                  size: 18,
                  color: selected ? AppColors.green : AppColors.muted,
                ),
                selected: selected,
                onSelected: (_) => onReportTypeChanged(type),
                selectedColor: AppColors.lightGreen,
                side: BorderSide(
                  color: selected ? AppColors.green : AppColors.border,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (reportType == AnalyticsReportType.periodComparison) ...[
            const Text(
              'Quick Compare',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Day vs Day'),
                  onPressed: () => onQuickComparison('day'),
                ),
                ActionChip(
                  label: const Text('Week vs Week'),
                  onPressed: () => onQuickComparison('week'),
                ),
                ActionChip(
                  label: const Text('Month vs Month'),
                  onPressed: () => onQuickComparison('month'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<AnalyticsPeriodPreset>(
                    value: comparePresetA,
                    decoration: const InputDecoration(
                      labelText: 'Period A',
                      prefixIcon: Icon(Icons.filter_1_outlined),
                    ),
                    items: _periodItems(),
                    onChanged: (value) {
                      if (value != null) onCompareAChanged(value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<AnalyticsPeriodPreset>(
                    value: comparePresetB,
                    decoration: const InputDecoration(
                      labelText: 'Period B',
                      prefixIcon: Icon(Icons.filter_2_outlined),
                    ),
                    items: _periodItems(),
                    onChanged: (value) {
                      if (value != null) onCompareBChanged(value);
                    },
                  ),
                ),
              ],
            ),
            if (comparePresetA == AnalyticsPeriodPreset.custom ||
                comparePresetB == AnalyticsPeriodPreset.custom) ...[
              const SizedBox(height: 12),
              if (comparePresetA == AnalyticsPeriodPreset.custom)
                _CustomDateRangeRow(
                  title: 'Period A custom dates',
                  start: compareCustomStartA,
                  end: compareCustomEndA,
                  onPickStart: () =>
                      onPickDate(isStart: true, isCompareA: true),
                  onPickEnd: () =>
                      onPickDate(isStart: false, isCompareA: true),
                ),
              if (comparePresetB == AnalyticsPeriodPreset.custom) ...[
                const SizedBox(height: 8),
                _CustomDateRangeRow(
                  title: 'Period B custom dates',
                  start: compareCustomStartB,
                  end: compareCustomEndB,
                  onPickStart: () =>
                      onPickDate(isStart: true, isCompareA: true, compareB: true),
                  onPickEnd: () =>
                      onPickDate(isStart: false, isCompareA: true, compareB: true),
                ),
              ],
            ],
          ] else ...[
            const Text(
              'Date Range',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in [
                  AnalyticsPeriodPreset.today,
                  AnalyticsPeriodPreset.yesterday,
                  AnalyticsPeriodPreset.thisWeek,
                  AnalyticsPeriodPreset.lastWeek,
                  AnalyticsPeriodPreset.thisMonth,
                  AnalyticsPeriodPreset.lastMonth,
                ])
                  FilterChip(
                    label: Text(_presetLabel(preset)),
                    selected: periodPreset == preset,
                    onSelected: (_) => onPeriodChanged(preset),
                    selectedColor: AppColors.lightGreen,
                    checkmarkColor: AppColors.green,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _CustomDateRangeRow(
              title: 'Custom date range',
              start: customStart,
              end: customEnd,
              highlighted: periodPreset == AnalyticsPeriodPreset.custom,
              onPickStart: () => onPickDate(isStart: true, isCompareA: false),
              onPickEnd: () => onPickDate(isStart: false, isCompareA: false),
            ),
          ],
          if (reportType == AnalyticsReportType.salesTrend) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<AnalyticsTrendGranularity>(
              value: granularity,
              decoration: const InputDecoration(
                labelText: 'Group By',
                prefixIcon: Icon(Icons.timeline_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: AnalyticsTrendGranularity.day,
                  child: Text('By Day'),
                ),
                DropdownMenuItem(
                  value: AnalyticsTrendGranularity.week,
                  child: Text('By Week'),
                ),
                DropdownMenuItem(
                  value: AnalyticsTrendGranularity.month,
                  child: Text('By Month'),
                ),
              ],
              onChanged: (value) {
                if (value != null) onGranularityChanged(value);
              },
            ),
          ],
          if (reportType == AnalyticsReportType.bestSellers) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rank by revenue instead of quantity'),
              value: bestSellersByRevenue,
              onChanged: onBestSellerMetricChanged,
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Filter by Branch (optional)',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('All Branches'),
                selected: selectedBranchIds.isEmpty,
                onSelected: (_) => onBranchToggled(-1),
                selectedColor: AppColors.lightGreen,
              ),
              for (final branch in branches)
                FilterChip(
                  label: Text(branch.name),
                  selected: selectedBranchIds.contains(branch.id),
                  onSelected: (_) => onBranchToggled(branch.id),
                  selectedColor: AppColors.lightGreen,
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Compare Branch Sales',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            reportType == AnalyticsReportType.branchComparison
                ? 'Pick two branches to compare sales side by side for the selected date range.'
                : 'Optional: pick two branches to include a sales comparison below your report.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (branches.isEmpty)
            const Text(
              'No branches configured yet. Add branches in Settings to compare sales.',
              style: TextStyle(color: AppColors.orange),
            )
          else if (branches.length < 2)
            const Text(
              'Add at least two branches in Settings to compare sales.',
              style: TextStyle(color: AppColors.orange),
            )
          else
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: compareBranchIdA,
                    decoration: const InputDecoration(
                      labelText: 'Branch 1',
                      prefixIcon: Icon(Icons.store_outlined),
                    ),
                    items: [
                      for (final branch in branches)
                        DropdownMenuItem(
                          value: branch.id,
                          child: Text(branch.name),
                        ),
                    ],
                    onChanged: onCompareBranchAChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: compareBranchIdB,
                    decoration: const InputDecoration(
                      labelText: 'Branch 2',
                      prefixIcon: Icon(Icons.store_outlined),
                    ),
                    items: [
                      for (final branch in branches)
                        DropdownMenuItem(
                          value: branch.id,
                          child: Text(branch.name),
                        ),
                    ],
                    onChanged: onCompareBranchBChanged,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          _BuilderNumbersPreview(
            reportType: reportType,
            records: records,
            currency: currency,
            primaryRange: primaryRange,
            branchFilter: branchFilter,
            branchNames: branchNames,
            compareBranchIdA: compareBranchIdA,
            compareBranchIdB: compareBranchIdB,
            comparePresetA: comparePresetA,
            comparePresetB: comparePresetB,
            compareCustomStartA: compareCustomStartA,
            compareCustomEndA: compareCustomEndA,
            compareCustomStartB: compareCustomStartB,
            compareCustomEndB: compareCustomEndB,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGenerate,
            icon: const Icon(Icons.numbers_outlined),
            label: const Text('View Sales Numbers'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ),
      ),
    );
  }

  String _presetLabel(AnalyticsPeriodPreset preset) {
    switch (preset) {
      case AnalyticsPeriodPreset.today:
        return 'Today';
      case AnalyticsPeriodPreset.yesterday:
        return 'Yesterday';
      case AnalyticsPeriodPreset.thisWeek:
        return 'This Week';
      case AnalyticsPeriodPreset.lastWeek:
        return 'Last Week';
      case AnalyticsPeriodPreset.thisMonth:
        return 'This Month';
      case AnalyticsPeriodPreset.lastMonth:
        return 'Last Month';
      case AnalyticsPeriodPreset.custom:
        return 'Custom';
    }
  }

  List<DropdownMenuItem<AnalyticsPeriodPreset>> _periodItems() {
    return const [
      DropdownMenuItem(value: AnalyticsPeriodPreset.today, child: Text('Today')),
      DropdownMenuItem(
        value: AnalyticsPeriodPreset.yesterday,
        child: Text('Yesterday'),
      ),
      DropdownMenuItem(
        value: AnalyticsPeriodPreset.thisWeek,
        child: Text('This Week'),
      ),
      DropdownMenuItem(
        value: AnalyticsPeriodPreset.lastWeek,
        child: Text('Last Week'),
      ),
      DropdownMenuItem(
        value: AnalyticsPeriodPreset.thisMonth,
        child: Text('This Month'),
      ),
      DropdownMenuItem(
        value: AnalyticsPeriodPreset.lastMonth,
        child: Text('Last Month'),
      ),
      DropdownMenuItem(
        value: AnalyticsPeriodPreset.custom,
        child: Text('Custom Range'),
      ),
    ];
  }
}

class _CustomDateRangeRow extends StatelessWidget {
  const _CustomDateRangeRow({
    required this.title,
    required this.start,
    required this.end,
    required this.onPickStart,
    required this.onPickEnd,
    this.highlighted = false,
  });

  final String title;
  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.lightGreen : AppColors.softSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? AppColors.green : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickStart,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    start == null ? 'From date' : _formatShortDate(start!),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickEnd,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    end == null ? 'To date' : _formatShortDate(end!),
                  ),
                ),
              ),
            ],
          ),
          if (start != null && end != null) ...[
            const SizedBox(height: 8),
            Text(
              '${_formatShortDate(start!)} → ${_formatShortDate(end!)}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportResults extends StatelessWidget {
  const _ReportResults({
    required this.reportType,
    required this.currency,
    required this.records,
    required this.products,
    required this.branchNames,
    required this.branchFilter,
    required this.compareBranchIdA,
    required this.compareBranchIdB,
    required this.primaryRange,
    required this.periodPreset,
    required this.comparePresetA,
    required this.comparePresetB,
    required this.compareCustomStartA,
    required this.compareCustomEndA,
    required this.compareCustomStartB,
    required this.compareCustomEndB,
    required this.granularity,
    required this.bestSellersByRevenue,
  });

  final AnalyticsReportType reportType;
  final String currency;
  final List<SalesHistoryRecord> records;
  final List<Product> products;
  final Map<int, String> branchNames;
  final Set<int>? branchFilter;
  final int? compareBranchIdA;
  final int? compareBranchIdB;
  final AnalyticsDateRange primaryRange;
  final AnalyticsPeriodPreset periodPreset;
  final AnalyticsPeriodPreset comparePresetA;
  final AnalyticsPeriodPreset comparePresetB;
  final DateTime? compareCustomStartA;
  final DateTime? compareCustomEndA;
  final DateTime? compareCustomStartB;
  final DateTime? compareCustomEndB;
  final AnalyticsTrendGranularity granularity;
  final bool bestSellersByRevenue;

  @override
  Widget build(BuildContext context) {
    final mainReport = switch (reportType) {
      AnalyticsReportType.salesSummary => _buildSummary(context),
      AnalyticsReportType.categoryComparison => _buildCategory(context),
      AnalyticsReportType.bestSellers => _buildBestSellers(context),
      AnalyticsReportType.salesTrend => _buildTrend(context),
      AnalyticsReportType.periodComparison => _buildPeriodComparison(context),
      AnalyticsReportType.branchComparison => _buildBranchComparison(context),
      AnalyticsReportType.paymentBreakdown => _buildPayments(context),
      AnalyticsReportType.customerType => _buildCustomerType(context),
    };

    if (reportType == AnalyticsReportType.branchComparison ||
        !_shouldAppendBranchComparison) {
      return mainReport;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        mainReport,
        const SizedBox(height: 16),
        _buildBranchComparison(context),
      ],
    );
  }

  bool get _shouldAppendBranchComparison {
    if (compareBranchIdA == null || compareBranchIdB == null) return false;
    if (compareBranchIdA == compareBranchIdB) return false;
    return branchNames.containsKey(compareBranchIdA) &&
        branchNames.containsKey(compareBranchIdB);
  }

  List<SalesHistoryRecord> _filtered() => AnalyticsEngine.filterRecords(
        records: records,
        range: primaryRange,
        branchIds: branchFilter,
      );

  Widget _numbersReport({
    required String title,
    required String periodLabel,
    required List<SalesHistoryRecord> filtered,
    required Widget details,
  }) {
    final summary = AnalyticsEngine.summarize(filtered);
    final totalVat =
        filtered.fold<double>(0, (sum, record) => sum + record.vat);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SalesNumbersHero(
          title: title,
          periodLabel: periodLabel,
          currency: currency,
          summary: summary,
        ),
        const SizedBox(height: 16),
        _AnalyticsKpiGrid(
          currency: currency,
          summary: summary,
          totalVat: totalVat,
        ),
        const SizedBox(height: 16),
        details,
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final filtered = _filtered();

    return _numbersReport(
      title: 'Sales Summary',
      periodLabel: AnalyticsEngine.rangeDescription(primaryRange),
      filtered: filtered,
      details: _AutoRangeSalesChart(
        records: filtered,
        range: primaryRange,
        periodPreset: periodPreset,
        currencySymbol: currency,
      ),
    );
  }

  Widget _autoRangeChart(List<SalesHistoryRecord> filtered) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _AutoRangeSalesChart(
        records: filtered,
        range: primaryRange,
        periodPreset: periodPreset,
        currencySymbol: currency,
      ),
    );
  }

  Widget _buildCategory(BuildContext context) {
    final filtered = _filtered();
    final data = AnalyticsEngine.salesByCategory(
      records: filtered,
      products: products,
    );

    return _numbersReport(
      title: 'Category Sales',
      periodLabel: primaryRange.label ?? 'Selected range',
      filtered: filtered,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnalyticsBarChart(
            title: 'Sales by Category',
            labels: data.map((item) => item.label).toList(),
            values: data.map((item) => item.value).toList(),
            currencySymbol: currency,
          ),
          const SizedBox(height: 12),
          TableCard(
            title: 'Category Totals',
            columns: const ['Category', 'Sales'],
            rows: data
                .map(
                  (item) => [item.label, formatMoney(currency, item.value)],
                )
                .toList(),
            emptyMessage: 'No category sales for this range.',
          ),
          _autoRangeChart(filtered),
        ],
      ),
    );
  }

  Widget _buildBestSellers(BuildContext context) {
    final filtered = _filtered();
    final data = AnalyticsEngine.bestSellers(
      records: filtered,
      byRevenue: bestSellersByRevenue,
    );
    final revenueData = bestSellersByRevenue
        ? data
        : AnalyticsEngine.bestSellers(
            records: filtered,
            byRevenue: true,
            limit: 10,
          );
    final revenueByName = {
      for (final item in revenueData) item.label: item.value,
    };

    return _numbersReport(
      title: 'Best Sellers',
      periodLabel: bestSellersByRevenue
          ? 'Ranked by revenue • ${primaryRange.label ?? 'Selected range'}'
          : 'Ranked by quantity • ${primaryRange.label ?? 'Selected range'}',
      filtered: filtered,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnalyticsBarChart(
            title: 'Top Products',
            labels: data.map((item) => item.label).toList(),
            values: data.map((item) => item.value).toList(),
            currencySymbol: bestSellersByRevenue ? currency : '',
            barColor: AppColors.amber,
          ),
          const SizedBox(height: 12),
          TableCard(
            title: 'Product Ranking',
            columns: bestSellersByRevenue
                ? const ['Product', 'Qty', 'Sales']
                : const ['Product', 'Qty Sold', 'Sales'],
            rows: data
                .map(
                  (item) => [
                    item.label,
                    formatQuantity(
                        bestSellersByRevenue ? (item.secondary ?? 0) : item.value),
                    formatMoney(
                      currency,
                      bestSellersByRevenue
                          ? item.value
                          : (revenueByName[item.label] ?? 0),
                    ),
                  ],
                )
                .toList(),
            emptyMessage: 'No product sales for this range.',
          ),
          _autoRangeChart(filtered),
        ],
      ),
    );
  }

  Widget _buildTrend(BuildContext context) {
    final filtered = _filtered();
    final chartGranularity = AnalyticsEngine.granularityForRange(
      primaryRange,
      preset: periodPreset,
    );
    final data = AnalyticsEngine.salesTrend(
      records: filtered,
      granularity: chartGranularity,
      range: primaryRange,
    );

    return _numbersReport(
      title: 'Sales Trend',
      periodLabel:
          '${AnalyticsEngine.rangeDescription(primaryRange)} • ${_granularityLabel(chartGranularity)}',
      filtered: filtered,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnalyticsBarChart(
            title: AnalyticsEngine.chartTitleForGranularity(chartGranularity),
            labels: data.map((item) => item.label).toList(),
            values: data.map((item) => item.value).toList(),
            currencySymbol: currency,
            barColor: AppColors.green,
          ),
          const SizedBox(height: 12),
          TableCard(
            title: 'Period Totals',
            columns: const ['Period', 'Sales'],
            rows: data
                .map(
                  (item) => [item.label, formatMoney(currency, item.value)],
                )
                .toList(),
            emptyMessage: 'No sales trend data for this range.',
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodComparison(BuildContext context) {
    final rangeA = AnalyticsEngine.rangeForPreset(
      comparePresetA,
      customStart: compareCustomStartA,
      customEnd: compareCustomEndA,
    );
    final rangeB = AnalyticsEngine.rangeForPreset(
      comparePresetB,
      customStart: compareCustomStartB,
      customEnd: compareCustomEndB,
    );
    final comparison = AnalyticsEngine.comparePeriods(
      records: records,
      rangeA: rangeA,
      rangeB: rangeB,
      branchIds: branchFilter,
    );

    final trendA = AnalyticsEngine.salesTrend(
      records: AnalyticsEngine.filterRecords(
        records: records,
        range: rangeA,
        branchIds: branchFilter,
      ),
      granularity: AnalyticsTrendGranularity.day,
      range: rangeA,
    );
    final trendB = AnalyticsEngine.salesTrend(
      records: AnalyticsEngine.filterRecords(
        records: records,
        range: rangeB,
        branchIds: branchFilter,
      ),
      granularity: AnalyticsTrendGranularity.day,
      range: rangeB,
    );
    final labels = trendA.map((item) => item.label).toList();
    final valuesA = trendA.map((item) => item.value).toList();
    final valuesB = trendB.map((item) => item.value).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComparisonNumbersHero(
          title: 'Period Comparison',
          subtitle: '${comparison.labelA} vs ${comparison.labelB}',
          currency: currency,
          comparison: comparison,
        ),
        const SizedBox(height: 16),
        _ComparisonKpiGrid(currency: currency, comparison: comparison),
        const SizedBox(height: 16),
        _ComparisonChart(
          title: 'Daily Sales Comparison',
          labels: labels,
          valuesA: valuesA,
          valuesB: valuesB,
          labelA: comparison.labelA,
          labelB: comparison.labelB,
          currencySymbol: currency,
        ),
        const SizedBox(height: 12),
        TableCard(
          title: 'Number Comparison',
          columns: const ['Metric', 'Period A', 'Period B'],
          rows: [
            [
              'Orders',
              '${comparison.summaryA.orderCount}',
              '${comparison.summaryB.orderCount}',
            ],
            [
              'Items Sold',
              '${comparison.summaryA.itemCount}',
              '${comparison.summaryB.itemCount}',
            ],
            [
              'Avg Ticket',
              formatMoney(currency, comparison.summaryA.averageTicket),
              formatMoney(currency, comparison.summaryB.averageTicket),
            ],
            [
              'Discounts',
              formatMoney(currency, comparison.summaryA.totalDiscount),
              formatMoney(currency, comparison.summaryB.totalDiscount),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildBranchComparison(BuildContext context) {
    final branchA = compareBranchIdA ?? 1;
    final branchB = compareBranchIdB ?? branchA;
    final nameA = branchNames[branchA] ?? 'Branch $branchA';
    final nameB = branchNames[branchB] ?? 'Branch $branchB';
    final comparison = AnalyticsEngine.compareBranches(
      records: records,
      range: primaryRange,
      branchIdA: branchA,
      branchIdB: branchB,
      branchNameA: nameA,
      branchNameB: nameB,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComparisonNumbersHero(
          title: 'Branch Sales Comparison',
          subtitle:
              '$nameA vs $nameB • ${primaryRange.label ?? 'Selected range'}',
          currency: currency,
          comparison: comparison,
        ),
        const SizedBox(height: 16),
        _ComparisonKpiGrid(currency: currency, comparison: comparison),
        const SizedBox(height: 16),
        AnalyticsBarChart(
          title: 'Sales by Branch',
          labels: [nameA, nameB],
          values: [
            comparison.summaryA.totalSales,
            comparison.summaryB.totalSales,
          ],
          currencySymbol: currency,
          barColor: AppColors.darkGreen,
        ),
        const SizedBox(height: 12),
        TableCard(
          title: 'Branch Numbers',
          columns: ['Metric', nameA, nameB],
          rows: [
            [
              'Orders',
              '${comparison.summaryA.orderCount}',
              '${comparison.summaryB.orderCount}',
            ],
            [
              'Items Sold',
              '${comparison.summaryA.itemCount}',
              '${comparison.summaryB.itemCount}',
            ],
            [
              'Avg Ticket',
              formatMoney(currency, comparison.summaryA.averageTicket),
              formatMoney(currency, comparison.summaryB.averageTicket),
            ],
            [
              'Total Sales',
              formatMoney(currency, comparison.summaryA.totalSales),
              formatMoney(currency, comparison.summaryB.totalSales),
            ],
          ],
        ),
        _AutoRangeSalesChart(
          records: AnalyticsEngine.filterRecords(
            records: records,
            range: primaryRange,
            branchIds: {branchA, branchB},
          ),
          range: primaryRange,
          periodPreset: periodPreset,
          currencySymbol: currency,
        ),
      ],
    );
  }

  Widget _buildPayments(BuildContext context) {
    final filtered = _filtered();
    final data = AnalyticsEngine.paymentBreakdown(filtered);
    final orderCounts = _paymentOrderCounts(filtered);

    return _numbersReport(
      title: 'Payment Sales',
      periodLabel: primaryRange.label ?? 'Selected range',
      filtered: filtered,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnalyticsBarChart(
            title: 'Sales by Payment Method',
            labels: data.map((item) => item.label).toList(),
            values: data.map((item) => item.value).toList(),
            currencySymbol: currency,
            barColor: AppColors.blue,
          ),
          const SizedBox(height: 12),
          TableCard(
            title: 'Payment Totals',
            columns: const ['Method', 'Orders', 'Sales'],
            rows: data
                .map(
                  (item) => [
                    item.label,
                    '${orderCounts[item.label] ?? 0}',
                    formatMoney(currency, item.value),
                  ],
                )
                .toList(),
            emptyMessage: 'No payment sales for this range.',
          ),
          _autoRangeChart(filtered),
        ],
      ),
    );
  }

  Map<String, int> _paymentOrderCounts(List<SalesHistoryRecord> filtered) {
    final counts = <String, int>{};
    for (final record in filtered) {
      final method =
          record.paymentMethod.trim().isEmpty ? 'Cash' : record.paymentMethod;
      counts[method] = (counts[method] ?? 0) + 1;
    }
    return counts;
  }

  Widget _buildCustomerType(BuildContext context) {
    final filtered = _filtered();
    final data = AnalyticsEngine.customerTypeBreakdown(filtered);
    final summary = AnalyticsEngine.summarize(filtered);

    return _numbersReport(
      title: 'Customer Sales',
      periodLabel: primaryRange.label ?? 'Selected range',
      filtered: filtered,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnalyticsBarChart(
            title: 'Sales by Customer Type',
            labels: data.map((item) => item.label).toList(),
            values: data.map((item) => item.value).toList(),
            currencySymbol: currency,
          ),
          const SizedBox(height: 12),
          TableCard(
            title: 'Customer Totals',
            columns: const ['Type', 'Orders', 'Sales'],
            rows: [
              [
                'Walk-In',
                '${summary.walkInOrders}',
                formatMoney(currency, data.first.value),
              ],
              [
                'Registered',
                '${summary.registeredOrders}',
                formatMoney(currency, data.last.value),
              ],
            ],
          ),
          _autoRangeChart(filtered),
        ],
      ),
    );
  }

  String _granularityLabel(AnalyticsTrendGranularity value) {
    switch (value) {
      case AnalyticsTrendGranularity.day:
        return 'Grouped by day';
      case AnalyticsTrendGranularity.week:
        return 'Grouped by week';
      case AnalyticsTrendGranularity.month:
        return 'Grouped by month';
    }
  }
}

class _BuilderNumbersPreview extends StatelessWidget {
  const _BuilderNumbersPreview({
    required this.reportType,
    required this.records,
    required this.currency,
    required this.primaryRange,
    required this.branchFilter,
    required this.branchNames,
    required this.compareBranchIdA,
    required this.compareBranchIdB,
    required this.comparePresetA,
    required this.comparePresetB,
    required this.compareCustomStartA,
    required this.compareCustomEndA,
    required this.compareCustomStartB,
    required this.compareCustomEndB,
  });

  final AnalyticsReportType reportType;
  final List<SalesHistoryRecord> records;
  final String currency;
  final AnalyticsDateRange primaryRange;
  final Set<int>? branchFilter;
  final Map<int, String> branchNames;
  final int? compareBranchIdA;
  final int? compareBranchIdB;
  final AnalyticsPeriodPreset comparePresetA;
  final AnalyticsPeriodPreset comparePresetB;
  final DateTime? compareCustomStartA;
  final DateTime? compareCustomEndA;
  final DateTime? compareCustomStartB;
  final DateTime? compareCustomEndB;

  @override
  Widget build(BuildContext context) {
    if (reportType == AnalyticsReportType.periodComparison) {
      final rangeA = AnalyticsEngine.rangeForPreset(
        comparePresetA,
        customStart: compareCustomStartA,
        customEnd: compareCustomEndA,
      );
      final rangeB = AnalyticsEngine.rangeForPreset(
        comparePresetB,
        customStart: compareCustomStartB,
        customEnd: compareCustomEndB,
      );
      final comparison = AnalyticsEngine.comparePeriods(
        records: records,
        rangeA: rangeA,
        rangeB: rangeB,
        branchIds: branchFilter,
      );
      return _PreviewBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Preview',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PreviewNumber(
                    label: comparison.labelA,
                    value: formatMoney(currency, comparison.summaryA.totalSales),
                    subtitle: '${comparison.summaryA.orderCount} orders',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PreviewNumber(
                    label: comparison.labelB,
                    value: formatMoney(currency, comparison.summaryB.totalSales),
                    subtitle: '${comparison.summaryB.orderCount} orders',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PreviewNumber(
                    label: 'Change',
                    value:
                        '${comparison.changePercent >= 0 ? '+' : ''}${comparison.changePercent.toStringAsFixed(1)}%',
                    subtitle: 'Sales difference',
                    highlight: comparison.changePercent >= 0
                        ? AppColors.green
                        : AppColors.danger,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (reportType == AnalyticsReportType.branchComparison &&
        compareBranchIdA != null &&
        compareBranchIdB != null) {
      final nameA =
          branchNames[compareBranchIdA!] ?? 'Branch $compareBranchIdA';
      final nameB =
          branchNames[compareBranchIdB!] ?? 'Branch $compareBranchIdB';
      final comparison = AnalyticsEngine.compareBranches(
        records: records,
        range: primaryRange,
        branchIdA: compareBranchIdA!,
        branchIdB: compareBranchIdB!,
        branchNameA: nameA,
        branchNameB: nameB,
      );
      return _PreviewBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Preview',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PreviewNumber(
                    label: nameA,
                    value: formatMoney(currency, comparison.summaryA.totalSales),
                    subtitle: '${comparison.summaryA.orderCount} orders',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PreviewNumber(
                    label: nameB,
                    value: formatMoney(currency, comparison.summaryB.totalSales),
                    subtitle: '${comparison.summaryB.orderCount} orders',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PreviewNumber(
                    label: 'Difference',
                    value:
                        '${comparison.changePercent >= 0 ? '+' : ''}${comparison.changePercent.toStringAsFixed(1)}%',
                    subtitle: 'Branch gap',
                    highlight: comparison.changePercent >= 0
                        ? AppColors.green
                        : AppColors.danger,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final filtered = AnalyticsEngine.filterRecords(
      records: records,
      range: primaryRange,
      branchIds: branchFilter,
    );
    final summary = AnalyticsEngine.summarize(filtered);

    return _PreviewBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preview',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatMoney(currency, summary.totalSales),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${summary.orderCount} orders • Avg ${formatMoney(currency, summary.averageTicket)} • ${primaryRange.label ?? 'Selected range'}',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _PreviewNumber extends StatelessWidget {
  const _PreviewNumber({
    required this.label,
    required this.value,
    required this.subtitle,
    this.highlight = AppColors.text,
  });

  final String label;
  final String value;
  final String subtitle;
  final Color highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: highlight,
            ),
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _SalesNumbersHero extends StatelessWidget {
  const _SalesNumbersHero({
    required this.title,
    required this.periodLabel,
    required this.currency,
    required this.summary,
  });

  final String title;
  final String periodLabel;
  final String currency;
  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            periodLabel,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          const Text(
            'Total Sales',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(currency, summary.totalSales),
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroStatChip(
                label: 'Orders',
                value: '${summary.orderCount}',
              ),
              _HeroStatChip(
                label: 'Avg Sale',
                value: formatMoney(currency, summary.averageTicket),
              ),
              _HeroStatChip(
                label: 'Items',
                value: '${summary.itemCount}',
              ),
              _HeroStatChip(
                label: 'Discounts',
                value: formatMoney(currency, summary.totalDiscount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComparisonNumbersHero extends StatelessWidget {
  const _ComparisonNumbersHero({
    required this.title,
    required this.subtitle,
    required this.currency,
    required this.comparison,
  });

  final String title;
  final String subtitle;
  final String currency;
  final AnalyticsComparisonResult comparison;

  @override
  Widget build(BuildContext context) {
    final change = comparison.changePercent;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ComparisonHeroNumber(
                  label: comparison.labelA,
                  value: formatMoney(currency, comparison.summaryA.totalSales),
                  subtitle: '${comparison.summaryA.orderCount} orders',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ComparisonHeroNumber(
                  label: comparison.labelB,
                  value: formatMoney(currency, comparison.summaryB.totalSales),
                  subtitle: '${comparison.summaryB.orderCount} orders',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ComparisonHeroNumber(
                  label: 'Change',
                  value:
                      '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                  subtitle: 'Sales difference',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComparisonHeroNumber extends StatelessWidget {
  const _ComparisonHeroNumber({
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}

class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsKpiGrid extends StatelessWidget {
  const _AnalyticsKpiGrid({
    required this.currency,
    required this.summary,
    required this.totalVat,
  });

  final String currency;
  final AnalyticsSummary summary;
  final double totalVat;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        const minCardWidth = 196.0;
        final columns =
            (constraints.maxWidth / (minCardWidth + spacing)).floor().clamp(1, 3);
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        final cards = [
          SummaryCard(
            label: 'Total Sales',
            value: formatMoney(currency, summary.totalSales),
            icon: Icons.payments_outlined,
          ),
          SummaryCard(
            label: 'Orders',
            value: '${summary.orderCount}',
            icon: Icons.receipt_long_outlined,
            color: AppColors.darkGreen,
            subtitle: '${summary.itemCount} items',
          ),
          SummaryCard(
            label: 'Avg Sale',
            value: formatMoney(currency, summary.averageTicket),
            icon: Icons.trending_up,
            color: AppColors.blue,
            subtitle: 'Per order',
          ),
          SummaryCard(
            label: 'VAT',
            value: formatMoney(currency, totalVat),
            icon: Icons.receipt_outlined,
            color: AppColors.blue,
            subtitle: '${summary.orderCount} orders',
          ),
          SummaryCard(
            label: 'Discounts',
            value: formatMoney(currency, summary.totalDiscount),
            icon: Icons.percent,
            color: AppColors.orange,
            subtitle: summary.totalDiscount > 0 ? 'Given to customers' : 'None',
          ),
          SummaryCard(
            label: 'Customers',
            value: '${summary.registeredOrders} reg.',
            icon: Icons.people_outline,
            color: AppColors.amber,
            subtitle: '${summary.walkInOrders} walk-in',
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

class _ComparisonKpiGrid extends StatelessWidget {
  const _ComparisonKpiGrid({
    required this.currency,
    required this.comparison,
  });

  final String currency;
  final AnalyticsComparisonResult comparison;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: SummaryCard(
                label: '${comparison.labelA} Sales',
                value: formatMoney(currency, comparison.summaryA.totalSales),
                icon: Icons.filter_1_outlined,
                color: AppColors.green,
                subtitle: '${comparison.summaryA.orderCount} orders',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: SummaryCard(
                label: '${comparison.labelB} Sales',
                value: formatMoney(currency, comparison.summaryB.totalSales),
                icon: Icons.filter_2_outlined,
                color: AppColors.blue,
                subtitle: '${comparison.summaryB.orderCount} orders',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: SummaryCard(
                label: 'Sales Change',
                value:
                    '${comparison.changePercent >= 0 ? '+' : ''}${comparison.changePercent.toStringAsFixed(1)}%',
                icon: Icons.compare_arrows,
                color: comparison.changePercent >= 0
                    ? AppColors.green
                    : AppColors.danger,
                subtitle: 'Period difference',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ComparisonChart extends StatelessWidget {
  const _ComparisonChart({
    required this.title,
    required this.labels,
    required this.valuesA,
    required this.valuesB,
    required this.labelA,
    required this.labelB,
    required this.currencySymbol,
  });

  final String title;
  final List<String> labels;
  final List<double> valuesA;
  final List<double> valuesB;
  final String labelA;
  final String labelB;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return const _AnalyticsEmptyCard();
    }

    final maxValue = [
      ...valuesA,
      ...valuesB,
    ].fold<double>(0, (max, value) => value > max ? value : max);
    const trackHeight = 96.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _LegendDot(color: AppColors.green, label: labelA),
              const SizedBox(width: 16),
              _LegendDot(color: AppColors.blue, label: labelB),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: _MiniBar(
                                  height: maxValue == 0
                                      ? 0
                                      : (valuesA[i] / maxValue) * trackHeight,
                                  color: AppColors.green,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: _MiniBar(
                                  height: maxValue == 0
                                      ? 0
                                      : (valuesB[i] / maxValue) * trackHeight,
                                  color: AppColors.blue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _AnalyticsEmptyCard extends StatelessWidget {
  const _AnalyticsEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'No comparison data for the selected periods.',
        style: TextStyle(color: AppColors.muted),
      ),
    );
  }
}

class _AutoRangeSalesChart extends StatelessWidget {
  const _AutoRangeSalesChart({
    required this.records,
    required this.range,
    required this.periodPreset,
    required this.currencySymbol,
  });

  final List<SalesHistoryRecord> records;
  final AnalyticsDateRange range;
  final AnalyticsPeriodPreset periodPreset;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final granularity = AnalyticsEngine.granularityForRange(
      range,
      preset: periodPreset,
    );
    final trend = AnalyticsEngine.salesTrend(
      records: records,
      granularity: granularity,
      range: range,
    );
    final chartTitle = AnalyticsEngine.chartTitleForGranularity(granularity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnalyticsBarChart(
          title: chartTitle,
          labels: trend.map((item) => item.label).toList(),
          values: trend.map((item) => item.value).toList(),
          currencySymbol: currencySymbol,
          barColor: AppColors.green,
        ),
        const SizedBox(height: 12),
        TableCard(
          title: chartTitle,
          columns: const ['Period', 'Sales'],
          rows: trend
              .map(
                (item) => [
                  item.label,
                  formatMoney(currencySymbol, item.value),
                ],
              )
              .toList(),
          emptyMessage: 'No periods in selected range.',
        ),
      ],
    );
  }
}

class _ReportMeta {
  const _ReportMeta(this.label, this.icon);

  final String label;
  final IconData icon;
}

_ReportMeta _reportMeta(AnalyticsReportType type) {
  switch (type) {
    case AnalyticsReportType.salesSummary:
      return const _ReportMeta('Total Sales', Icons.payments_outlined);
    case AnalyticsReportType.categoryComparison:
      return const _ReportMeta('Categories', Icons.category_outlined);
    case AnalyticsReportType.bestSellers:
      return const _ReportMeta('Top Products', Icons.star_outline);
    case AnalyticsReportType.salesTrend:
      return const _ReportMeta('Sales Trend', Icons.show_chart);
    case AnalyticsReportType.periodComparison:
      return const _ReportMeta('Compare Dates', Icons.compare_arrows);
    case AnalyticsReportType.branchComparison:
      return const _ReportMeta('Compare Branches', Icons.store_outlined);
    case AnalyticsReportType.paymentBreakdown:
      return const _ReportMeta('Payments', Icons.payments_outlined);
    case AnalyticsReportType.customerType:
      return const _ReportMeta('Customers', Icons.people_outline);
  }
}

String _formatShortDate(DateTime value) {
  return '${value.month}/${value.day}/${value.year}';
}
