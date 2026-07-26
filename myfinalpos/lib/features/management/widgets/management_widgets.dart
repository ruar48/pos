import 'package:flutter/material.dart';

import '../../../core/theme/agri_admin_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../pos/pages/pos_home_page.dart';
import '../../pos/widgets/app_drawer_section.dart';
import '../../pos/widgets/app_shell_scaffold.dart';

class ManagementPageShell extends StatelessWidget {
  const ManagementPageShell({
    super.key,
    required this.pageState,
    required this.activeSection,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.scrollBody = true,
  });

  final PosHomePageState pageState;
  final AppDrawerSection activeSection;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final bool scrollBody;

  @override
  Widget build(BuildContext context) {
    return AppShellScaffold(
      pageState: pageState,
      activeSection: activeSection,
      title: title,
      subtitle: subtitle,
      actions: actions,
      scrollBody: scrollBody,
      body: child,
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.green,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AgriAdminTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AgriIconBox(icon: icon, size: 40, iconSize: 22, tone: _toneForColor(color)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 16,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                subtitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: subtitle == null
                      ? Colors.transparent
                      : AppColors.muted,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

AgriStatTone _toneForColor(Color color) {
  if (color == AppColors.orange || color == AppColors.amber) {
    return AgriStatTone.warning;
  }
  if (color == AppColors.danger) return AgriStatTone.danger;
  if (color == AppColors.muted) return AgriStatTone.neutral;
  return AgriStatTone.positive;
}

class TableCard extends StatelessWidget {
  const TableCard({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'No records available.',
  });

  final String title;
  final List<String> columns;
  final List<List<String>> rows;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return AgriCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.softSurface),
                columns: [
                  for (final column in columns)
                    DataColumn(
                      label: Text(
                        column,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        for (final cell in row) DataCell(Text(cell)),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ModuleOverviewCard extends StatelessWidget {
  const ModuleOverviewCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AgriAdminTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AgriAdminTheme.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: AgriAdminTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: AppColors.green),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnalyticsBarChart extends StatelessWidget {
  const AnalyticsBarChart({
    super.key,
    required this.labels,
    required this.values,
    this.title = 'Sales by Category',
    this.currencySymbol = '\u20B1',
    this.barColor = AppColors.green,
  });

  final List<String> labels;
  final List<double> values;
  final String title;
  final String currencySymbol;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty || values.isEmpty) {
      return const _AnalyticsEmptyState();
    }

    final maxValue = values.reduce((a, b) => a > b ? a : b);
    const chartHeight = 180.0;
    const barTrackHeight = 96.0;

    return AgriCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < labels.length; index++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _AnalyticsBarColumn(
                        label: labels[index],
                        valueLabel: formatMoney(currencySymbol, values[index]),
                        barHeight: maxValue == 0
                            ? 0
                            : (values[index] / maxValue) * barTrackHeight,
                        barColor: barColor,
                        trackHeight: barTrackHeight,
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

class _AnalyticsBarColumn extends StatelessWidget {
  const _AnalyticsBarColumn({
    required this.label,
    required this.valueLabel,
    required this.barHeight,
    required this.barColor,
    required this.trackHeight,
  });

  final String label;
  final String valueLabel;
  final double barHeight;
  final Color barColor;
  final double trackHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          valueLabel,
          style: const TextStyle(fontSize: 10, color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: trackHeight,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              height: barHeight,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: barColor.withValues(alpha: 0.85),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class AnalyticsTrendChart extends StatelessWidget {
  const AnalyticsTrendChart({
    super.key,
    required this.labels,
    required this.values,
    this.title = 'Sales Trend',
    this.subtitle,
    this.lineColor = AppColors.blue,
  });

  final List<String> labels;
  final List<double> values;
  final String title;
  final String? subtitle;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty || values.isEmpty) {
      return const _AnalyticsEmptyState(message: 'No trend data available.');
    }

    final maxValue = values.fold<double>(0, (a, b) => a > b ? a : b);
    final chartMax = maxValue <= 0 ? 1.0 : maxValue;

    return AgriCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _TrendLinePainter(
                values: values,
                maxValue: chartMax,
                color: lineColor,
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final label in labels)
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendLinePainter extends CustomPainter {
  _TrendLinePainter({
    required this.values,
    required this.maxValue,
    required this.color,
  });

  final List<double> values;
  final double maxValue;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || maxValue == 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = (size.width / (values.length - 1)) * index;
      final y = size.height - ((values[index] / maxValue) * (size.height - 20));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.color != color;
  }
}

class _AnalyticsEmptyState extends StatelessWidget {
  const _AnalyticsEmptyState({this.message = 'No analytics data available.'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AgriCard(
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: Center(
          child: Text(message, style: const TextStyle(color: AppColors.muted)),
        ),
      ),
    );
  }
}
