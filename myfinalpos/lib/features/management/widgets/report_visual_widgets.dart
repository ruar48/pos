import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/agri_admin_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/sales_history_record.dart';
import '../../../services/analytics_engine.dart';

const _sliceColors = [
  Color(0xFF0F766E),
  Color(0xFF14B8A6),
  Color(0xFF2DD4BF),
  Color(0xFF5EEAD4),
  Color(0xFF059669),
  Color(0xFF34D399),
  Color(0xFFF97316),
  Color(0xFFFB923C),
  Color(0xFFFDBA74),
  Color(0xFF64748B),
];

class ReportDonutChartCard extends StatelessWidget {
  const ReportDonutChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.slices,
    required this.currencySymbol,
    this.valueFormatter,
    this.maxLegendItems = 6,
  });

  final String title;
  final String subtitle;
  final List<AnalyticsNamedValue> slices;
  final String currencySymbol;
  final String Function(AnalyticsNamedValue slice)? valueFormatter;
  final int maxLegendItems;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);

    return AgriCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.darkGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          if (total <= 0)
            const Text(
              'No data for this period.',
              style: TextStyle(color: AppColors.muted),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  height: 132,
                  child: CustomPaint(
                    painter: _DonutChartPainter(
                      values: slices.map((slice) => slice.value).toList(),
                      colors: _sliceColors,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < slices.length && i < maxLegendItems; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _sliceColors[i % _sliceColors.length],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  slices[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                valueFormatter?.call(slices[i]) ??
                                    formatMoney(currencySymbol, slices[i].value),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (slices.length > maxLegendItems)
                        Text(
                          '+${slices.length - maxLegendItems} more',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({
    required this.values,
    required this.colors,
  });

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final stroke = radius * 0.34;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * math.pi * 2;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }

    canvas.drawCircle(center, radius - stroke - 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

enum ReportHeatmapMode { units, price }

class ReportHourlyHeatmapCard extends StatefulWidget {
  const ReportHourlyHeatmapCard({
    super.key,
    required this.grid,
    required this.rangeLabel,
  });

  final AnalyticsHourlyGrid grid;
  final String rangeLabel;

  @override
  State<ReportHourlyHeatmapCard> createState() =>
      _ReportHourlyHeatmapCardState();
}

class _ReportHourlyHeatmapCardState extends State<ReportHourlyHeatmapCard> {
  ReportHeatmapMode mode = ReportHeatmapMode.units;

  double _cellValue(AnalyticsHourlyCell cell) =>
      mode == ReportHeatmapMode.units ? cell.units : cell.amount;

  String _formatValue(double value) {
    if (value <= 0) return '0';
    if (mode == ReportHeatmapMode.price) {
      return value.round().toString();
    }
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  Color _heatColor(double ratio) {
    if (ratio <= 0) return const Color(0xFF475569);
    if (ratio < 0.2) return const Color(0xFFFDBA74);
    if (ratio < 0.4) return const Color(0xFFFB923C);
    if (ratio < 0.6) return const Color(0xFFF59E0B);
    if (ratio < 0.8) return const Color(0xFF34D399);
    return const Color(0xFF0F766E);
  }

  @override
  Widget build(BuildContext context) {
    final maxValue = widget.grid.cells.fold<double>(
      0,
      (max, cell) => math.max(max, _cellValue(cell)),
    );
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;

    AnalyticsHourlyCell? cellFor(DateTime day, int hour) {
      for (final cell in widget.grid.cells) {
        if (cell.date.year == day.year &&
            cell.date.month == day.month &&
            cell.date.day == day.day &&
            cell.hour == hour) {
          return cell;
        }
      }
      return null;
    }

    return AgriCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Units Sold by Hour',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkGreen,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.rangeLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              SegmentedButton<ReportHeatmapMode>(
                segments: const [
                  ButtonSegment(
                    value: ReportHeatmapMode.units,
                    label: Text('Unit'),
                  ),
                  ButtonSegment(
                    value: ReportHeatmapMode.price,
                    label: Text('Price'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (value) =>
                    setState(() => mode = value.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 52),
                    for (var hour = 0; hour < 24; hour++)
                      SizedBox(
                        width: 34,
                        child: Text(
                          AnalyticsEngine.hourLabel(hour),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final day in widget.grid.days) ...[
                  Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          AnalyticsEngine.dayLabel(day),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (var hour = 0; hour < 24; hour++) ...[
                        Builder(
                          builder: (context) {
                            final cell = cellFor(day, hour);
                            final value = cell == null ? 0.0 : _cellValue(cell);
                            final ratio = value / safeMax;
                            return Container(
                              width: 30,
                              height: 30,
                              margin: const EdgeInsets.all(2),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _heatColor(ratio),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                _formatValue(value),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Low', style: TextStyle(fontSize: 10, color: AppColors.muted)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    children: const [
                      Expanded(child: ColoredBox(color: Color(0xFF475569))),
                      Expanded(child: ColoredBox(color: Color(0xFFFDBA74))),
                      Expanded(child: ColoredBox(color: Color(0xFFFB923C))),
                      Expanded(child: ColoredBox(color: Color(0xFFF59E0B))),
                      Expanded(child: ColoredBox(color: Color(0xFF34D399))),
                      Expanded(child: ColoredBox(color: Color(0xFF0F766E))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text('High', style: TextStyle(fontSize: 10, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class ReportVisualsSection extends StatelessWidget {
  const ReportVisualsSection({
    super.key,
    required this.periodLabel,
    required this.range,
    required this.records,
    required this.currency,
  });

  final String periodLabel;
  final AnalyticsDateRange range;
  final List<SalesHistoryRecord> records;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final cashiers = AnalyticsEngine.salesByCashier(records);
    final payments = AnalyticsEngine.paymentBreakdown(records);
    final customers = AnalyticsEngine.customerTypeBreakdown(records);
    final hourly = AnalyticsEngine.hourlySalesGrid(
      records: records,
      range: range,
    );
    final customerTotal =
        customers.fold<double>(0, (sum, row) => sum + row.value);

    final rangeLabel =
        '${AnalyticsEngine.dayLabel(range.start)}, 12:00am – '
        '${AnalyticsEngine.dayLabel(range.end)}, 11:59pm';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        final isMedium = constraints.maxWidth >= 640;

        Widget donutRow(List<Widget> cards) {
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          }
          if (isMedium) {
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 16),
                    Expanded(child: cards[1]),
                  ],
                ),
                const SizedBox(height: 16),
                cards[2],
              ],
            );
          }
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                cards[i],
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            donutRow([
              ReportDonutChartCard(
                title: 'Sales by Cashier',
                subtitle: periodLabel,
                slices: cashiers,
                currencySymbol: currency,
              ),
              ReportDonutChartCard(
                title: 'Sales by Payment',
                subtitle: periodLabel,
                slices: payments,
                currencySymbol: currency,
              ),
              ReportDonutChartCard(
                title: 'Sales by Customer Activity',
                subtitle: periodLabel,
                slices: customers,
                currencySymbol: currency,
                valueFormatter: (slice) {
                  if (customerTotal <= 0) return formatMoney(currency, 0);
                  final share = (slice.value / customerTotal) * 100;
                  return '${share.toStringAsFixed(share == share.roundToDouble() ? 0 : 1)}%';
                },
              ),
            ]),
            const SizedBox(height: 16),
            ReportHourlyHeatmapCard(
              grid: hourly,
              rangeLabel: rangeLabel,
            ),
          ],
        );
      },
    );
  }
}
