import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/agri_admin_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/responsive_monitor_layout.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/live_wall_sales.dart';
import '../../../models/pos_monitor.dart';
import '../../pos/pages/pos_home_page.dart';
import '../../pos/widgets/app_drawer_section.dart';
import 'management_widgets.dart';

class LivePosMonitorPage extends StatefulWidget {
  const LivePosMonitorPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<LivePosMonitorPage> createState() => _LivePosMonitorPageState();
}

class _LivePosMonitorPageState extends State<LivePosMonitorPage> {
  PosMonitorLive? live;
  LiveWallSalesReport? salesReport;
  String? errorMessage;
  String? revision;
  bool _watchActive = false;

  @override
  void initState() {
    super.initState();
    unawaited(_startMonitoring());
  }

  @override
  void dispose() {
    _watchActive = false;
    unawaited(
      widget.pageState.api.unsubscribeMonitorLive(
        actorUserId: widget.pageState.widget.currentUser.id,
      ),
    );
    super.dispose();
  }

  Future<void> _startMonitoring() async {
    _watchActive = true;
    await _refresh(subscribe: true);
    await _refreshSales();
    unawaited(_runWatchLoop());
  }

  Future<void> _runWatchLoop() async {
    while (_watchActive && mounted) {
      try {
        final watchResult = await widget.pageState.api.watchMonitorLive(
          revision: revision,
          actorUserId: widget.pageState.widget.currentUser.id,
        );
        if (!_watchActive || !mounted) return;

        if (watchResult.changed) {
          await _refresh();
          unawaited(_refreshSales());
        }
        revision = watchResult.revision;
      } catch (_) {
        if (!_watchActive || !mounted) return;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _refreshSales() async {
    try {
      final payload = await widget.pageState.api.fetchMonitorSalesReport();
      if (!mounted) return;
      setState(() => salesReport = payload);
    } catch (_) {
      /* keep last snapshot */
    }
  }

  Future<void> _refresh({bool subscribe = false}) async {
    try {
      final result = subscribe
          ? await widget.pageState.api.subscribeMonitorLive(
              actorUserId: widget.pageState.widget.currentUser.id,
              revision: revision,
            )
          : await widget.pageState.api.fetchMonitorLive(revision: revision);
      if (!mounted) return;
      setState(() {
        live = live?.mergeFrom(result) ?? result.live;
        revision = result.revision;
        errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = cleanApiErrorMessage(error.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.pageState.settings.currencySymbol;

    return ManagementPageShell(
      pageState: widget.pageState,
      activeSection: AppDrawerSection.livePosMonitor,
      title: 'Live POS Monitor',
      scrollBody: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = MonitorLayoutMetrics.forWidth(constraints.maxWidth);
            final terminals = (live?.terminals ?? [])
                .where((terminal) => terminal.online)
                .toList();
            final isHealthy = errorMessage == null && (live?.watching ?? false);

            return SizedBox(
              height: constraints.maxHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AgriPageHeader(
                    badge: 'Live Wall',
                    title: 'Live POS Monitor',
                    description:
                        'Works on phone, tablet, PC, and TV — every active register updates live while this page stays open.',
                  ),
                  const SizedBox(height: 16),
                  AgriCard(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        AgriIconBox(
                          icon: live == null
                              ? Icons.hourglass_top
                              : Icons.monitor_heart_outlined,
                          tone: isHealthy
                              ? AgriStatTone.positive
                              : AgriStatTone.danger,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'System Health',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                live == null
                                    ? 'Checking API connection...'
                                    : isHealthy
                                        ? 'All systems operational'
                                        : 'Connection issue detected',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (live != null)
                          AgriStatusBadge(
                            ok: isHealthy,
                            label: isHealthy ? 'Connected' : 'Disconnected',
                          ),
                        IconButton(
                          onPressed: () => _refresh(subscribe: true),
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh',
                        ),
                      ],
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    AgriCard(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SummaryChip(
                        label: '${live?.onlineCount ?? 0} online',
                        icon: Icons.circle,
                        fontSize: layout.chipSize,
                      ),
                      _SummaryChip(
                        label: '${live?.activeCount ?? 0} in sale',
                        icon: Icons.point_of_sale,
                        fontSize: layout.chipSize,
                      ),
                      _SummaryChip(
                        label:
                            'Today ${formatMoney(currency, salesReport?.netSales ?? 0)}',
                        icon: Icons.trending_up,
                        fontSize: layout.chipSize,
                        emphasized: true,
                      ),
                    ],
                  ),
                  if (salesReport != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: AgriCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'TOTAL SALES TODAY',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: AppColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  formatMoney(currency, salesReport!.netSales),
                                  style: TextStyle(
                                    fontSize: layout.density ==
                                            MonitorLayoutDensity.phone
                                        ? 28
                                        : 32,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AgriCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ORDERS TODAY',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: AppColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${salesReport!.orderCount}',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.text,
                                  ),
                                ),
                                Text(
                                  'Avg ${formatMoney(currency, salesReport!.averageOrderValue)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: AgriCard(
                      clipBehavior: Clip.antiAlias,
                      padding: EdgeInsets.zero,
                      child: terminals.isEmpty
                          ? _EmptyMonitorState(
                              watching: live?.watching ?? false,
                              layout: layout,
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: layout.crossAxisCount,
                                crossAxisSpacing: layout.gridSpacing,
                                mainAxisSpacing: layout.gridSpacing,
                                childAspectRatio: layout.childAspectRatio,
                              ),
                              itemCount: terminals.length,
                              itemBuilder: (context, index) {
                                final terminal = terminals[index];
                                final state =
                                    live?.terminalStates[terminal.terminalId];
                                return _LiveTerminalCard(
                                  terminal: terminal,
                                  state: state,
                                  currency: currency,
                                  layout: layout,
                                );
                              },
                            ),
                    ),
                  ),
                  if (layout.density != MonitorLayoutDensity.phone) ...[
                    const SizedBox(height: 12),
                    AgriCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.wifi,
                            size: 18,
                            color: AppColors.green,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: AppColors.muted,
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'Display tip: ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  const TextSpan(
                                    text:
                                        'Use TV display for a full-screen wall on a smart TV or projector. On phones, tap a register card to expand the full cart.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.icon,
    this.fontSize = 12,
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final double fontSize;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: emphasized
            ? AppColors.green.withValues(alpha: 0.14)
            : AppColors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasized ? AppColors.green : AppColors.greenBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fontSize + 2, color: AppColors.green),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppColors.green,
              fontSize: fontSize,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMonitorState extends StatelessWidget {
  const _EmptyMonitorState({
    required this.watching,
    required this.layout,
  });

  final bool watching;
  final MonitorLayoutMetrics layout;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_other_outlined,
              size: layout.density == MonitorLayoutDensity.phone ? 48 : 56,
              color: AppColors.muted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No active POS registers',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: layout.titleSize + 2,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              watching
                  ? 'Open POS Sales on a phone or tablet and start ringing items. Each register will appear here as its own live card.'
                  : 'Waiting for the live monitor connection…',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                height: 1.4,
                fontSize: layout.chipSize + 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveTerminalCard extends StatelessWidget {
  const _LiveTerminalCard({
    required this.terminal,
    required this.state,
    required this.currency,
    required this.layout,
  });

  final PosMonitorTerminal terminal;
  final PosMonitorState? state;
  final String currency;
  final MonitorLayoutMetrics layout;

  Color _headerColor() {
    if (!terminal.online) return AppColors.muted;
    switch (state?.status ?? terminal.status) {
      case 'success':
        return AppColors.green;
      case 'payment':
        return AppColors.orange;
      case 'cart':
        return const Color(0xFF0284C7);
      default:
        return AppColors.darkGreen;
    }
  }

  String _statusLabel() {
    if (!terminal.online) return 'Offline';
    switch (state?.status ?? terminal.status) {
      case 'success':
        return 'Order done';
      case 'payment':
        return 'Payment';
      case 'cart':
        return 'Adding items';
      default:
        return 'Waiting';
    }
  }

  String _phaseLabel() {
    switch (state?.status ?? terminal.status) {
      case 'success':
        return 'Complete';
      case 'payment':
        return 'Checkout';
      case 'cart':
        return 'Serving';
      default:
        return 'Ready';
    }
  }

  String get _cashierName {
    final fromState = state?.cashierName.trim();
    if (fromState != null && fromState.isNotEmpty) return fromState;
    final fromTerminal = terminal.cashierName.trim();
    if (fromTerminal.isNotEmpty) return fromTerminal;
    return state?.terminalLabel ?? terminal.terminalLabel;
  }

  String get _cashierUsername {
    final fromState = state?.cashierUsername?.trim();
    if (fromState != null && fromState.isNotEmpty) return fromState;
    final fromTerminal = terminal.cashierUsername?.trim();
    if (fromTerminal != null && fromTerminal.isNotEmpty) return fromTerminal;
    return _cashierName;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = state;
    final items = resolved?.items ?? const <PosMonitorItem>[];
    final success = resolved?.success;
    final total = success?.total ?? resolved?.total ?? terminal.total;
    final previewItems = items.take(3).toList();
    final hiddenCount = items.length - previewItems.length;

    return Container(
      decoration: AgriAdminTheme.cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.all(layout.headerPadding),
            color: _headerColor(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: layout.density == MonitorLayoutDensity.phone
                          ? 8
                          : 10,
                      height: layout.density == MonitorLayoutDensity.phone
                          ? 8
                          : 10,
                      decoration: BoxDecoration(
                        color: terminal.online ? Colors.white : Colors.white38,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _cashierName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: layout.titleSize,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: layout.chipSize,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _cashierUsername,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: layout.chipSize + 1,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      icon: Icons.point_of_sale_outlined,
                      label: _phaseLabel(),
                    ),
                    _MetaChip(
                      icon: Icons.person_outline,
                      label: resolved?.customerName.isNotEmpty == true
                          ? resolved!.customerName
                          : 'Walk-in',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(layout.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!terminal.online)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Register offline',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else if ((resolved?.status ?? terminal.status) == 'success')
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle, color: AppColors.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Order complete · ${success?.paymentMethod ?? 'Cash'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Ready for the next order',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...previewItems.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '${formatQuantity(item.quantity)}× ${item.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (previewItems.isEmpty &&
                      (resolved?.status ?? terminal.status) == 'idle')
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Waiting for the next order',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else if (previewItems.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Cart open — items appear live',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Column(
                        children: [
                          if (resolved?.isPaymentMode == true)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Payment screen',
                                style: TextStyle(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ...previewItems.map(
                            (item) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.softSurface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${formatQuantity(item.quantity)}× ${item.name}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatMoney(currency, item.total),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (hiddenCount > 0)
                            Text(
                              '+$hiddenCount more item${hiddenCount == 1 ? '' : 's'}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Live total',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              formatMoney(currency, total),
                              style: TextStyle(
                                fontSize: layout.totalSize,
                                fontWeight: FontWeight.w900,
                                color: AppColors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
