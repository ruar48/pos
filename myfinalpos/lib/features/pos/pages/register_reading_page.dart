import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/register_reading.dart';
import '../../../services/pos_api.dart';
import '../../management/widgets/management_widgets.dart';
import '../widgets/app_drawer_section.dart';
import 'pos_home_page.dart';

/// X reading / Z reading for this register.
///
/// X is safe to run repeatedly. Z closes the shift, increments the terminal's
/// Z counter and rolls the shift into the accumulated grand total — it cannot
/// be undone, so it is confirmed and PIN-gated.
class RegisterReadingPage extends StatefulWidget {
  const RegisterReadingPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<RegisterReadingPage> createState() => _RegisterReadingPageState();
}

class _RegisterReadingPageState extends State<RegisterReadingPage> {
  static const _api = PosApi();

  RegisterSessionStatus? _status;
  RegisterReading? _reading;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _terminalId => widget.pageState.registerTerminalId;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _api.fetchRegisterStatus(_terminalId);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = cleanApiErrorMessage(e.toString());
        _loading = false;
      });
    }
  }

  Future<void> _openShift() async {
    setState(() => _busy = true);
    try {
      await _api.openRegisterSession(
        terminalId: _terminalId,
        cashierUserId: widget.pageState.widget.currentUser.id,
      );
      if (!mounted) return;
      showTopSuccess(context, 'Shift opened on $_terminalId');
      await _loadStatus();
    } catch (e) {
      if (!mounted) return;
      showTopError(context, cleanApiErrorMessage(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takeX() async {
    setState(() => _busy = true);
    try {
      final reading = await _api.takeXReading(
        terminalId: _terminalId,
        takenByUserId: widget.pageState.widget.currentUser.id,
      );
      if (!mounted) return;
      setState(() => _reading = reading);
      showTopSuccess(context, 'X reading taken');
      await _loadStatus();
    } catch (e) {
      if (!mounted) return;
      showTopError(context, cleanApiErrorMessage(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takeZ() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close shift with a Z reading?'),
        content: const Text(
          'This closes the current shift, increases the Z counter and adds '
          'the shift to the accumulated grand total.\n\n'
          'It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final pin = await _promptForPin();
    if (pin == null || pin.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final reading = await _api.takeZReading(
        terminalId: _terminalId,
        cashDrawerPin: pin,
        takenByUserId: widget.pageState.widget.currentUser.id,
      );
      if (!mounted) return;
      setState(() => _reading = reading);
      showTopSuccess(context, 'Z reading #${reading.zCounter} — shift closed');
      await _loadStatus();
    } catch (e) {
      if (!mounted) return;
      showTopError(context, cleanApiErrorMessage(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptForPin() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cash drawer PIN'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Enter PIN'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Confirm Z reading'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: widget.pageState,
      activeSection: AppDrawerSection.registerReading,
      title: 'X / Z Reading',
      subtitle: 'Shift totals for this register ($_terminalId).',
      child: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) _ErrorBanner(message: _error!),
                _ShiftCard(
                  status: _status,
                  busy: _busy,
                  onOpen: _openShift,
                  onX: _takeX,
                  onZ: _takeZ,
                ),
                if (_reading != null) ...[
                  const SizedBox(height: 16),
                  _ReadingCard(reading: _reading!),
                ],
              ],
            ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.status,
    required this.busy,
    required this.onOpen,
    required this.onX,
    required this.onZ,
  });

  final RegisterSessionStatus? status;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onX;
  final VoidCallback onZ;

  @override
  Widget build(BuildContext context) {
    final open = status?.isOpen ?? false;

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
          Row(
            children: [
              Icon(
                open ? Icons.play_circle_outline : Icons.pause_circle_outline,
                color: open ? AppColors.success : AppColors.muted,
              ),
              const SizedBox(width: 10),
              Text(
                open ? 'Shift is open' : 'No shift open',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 14),
            _CounterRow(
              label: 'Accumulated grand total',
              value: formatMoney('₱', status!.grandTotalAccumulated),
            ),
            _CounterRow(label: 'Z counter', value: '${status!.zCounter}'),
            _CounterRow(
              label: 'Reset counter',
              value: '${status!.resetCounter}',
            ),
            if (open && status!.openedAt != null)
              _CounterRow(label: 'Opened at', value: status!.openedAt!),
          ],
          const SizedBox(height: 16),
          if (!open)
            FilledButton.icon(
              onPressed: busy ? null : onOpen,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Open shift'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onX,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('X reading'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onZ,
                    icon: const Icon(Icons.lock_clock),
                    label: const Text('Z reading'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.reading});

  final RegisterReading reading;

  @override
  Widget build(BuildContext context) {
    final isZ = reading.isZ;

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
            isZ ? 'Z READING #${reading.zCounter}' : 'X READING',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: AppColors.text,
            ),
          ),
          Text(
            '${reading.terminalId} · ${reading.businessDate}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const Divider(height: 24),

          _line('Beginning OR', reading.beginningOr ?? '—'),
          _line('Ending OR', reading.endingOr ?? '—'),
          _line('Transactions', '${reading.transactionCount}'),
          const Divider(height: 24),

          _line('Gross sales', formatMoney('₱', reading.grossSales)),
          _line('Discounts', '-${formatMoney('₱', reading.discountTotal)}'),
          _line('Refunds', '-${formatMoney('₱', reading.refundAmount)}'),
          _line(
            'Voids',
            '${reading.voidCount} · ${formatMoney('₱', reading.voidAmount)}',
          ),
          _line('NET SALES', formatMoney('₱', reading.netSales), bold: true),
          const Divider(height: 24),

          _line('VATable sales', formatMoney('₱', reading.vatableSales)),
          _line('VAT amount', formatMoney('₱', reading.vatAmount)),
          _uncapturedOr(
            'VAT-exempt sales',
            'vat_exempt_sales',
            reading.vatExemptSales,
          ),
          _uncapturedOr(
            'Zero-rated sales',
            'zero_rated_sales',
            reading.zeroRatedSales,
          ),
          const Divider(height: 24),

          _uncapturedOr('SC discount', 'sc_discount', reading.scDiscount),
          _uncapturedOr('PWD discount', 'pwd_discount', reading.pwdDiscount),
          _uncapturedOr('NAAC discount', 'naac_discount', reading.naacDiscount),
          _uncapturedOr(
            'Solo parent discount',
            'solo_parent_discount',
            reading.soloParentDiscount,
          ),
          _line('Other discounts', formatMoney('₱', reading.otherDiscount)),
          const Divider(height: 24),

          _line(
            'Old grand total',
            formatMoney('₱', reading.beginningGrandTotal),
          ),
          _line(
            'New grand total',
            formatMoney('₱', reading.endingGrandTotal),
            bold: true,
          ),

          if (reading.paymentBreakdown.isNotEmpty) ...[
            const Divider(height: 24),
            const Text(
              'PAYMENTS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            for (final entry in reading.paymentBreakdown.entries)
              _line(entry.key, formatMoney('₱', entry.value)),
          ],

          if (reading.uncapturedFields.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ComplianceNotice(count: reading.uncapturedFields.length),
          ],
        ],
      ),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: bold ? AppColors.text : AppColors.muted,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              color: bold ? AppColors.darkGreen : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  /// Statutory figures the POS cannot source are shown as "not captured", not
  /// as 0.00 — a zero would claim no such sales happened.
  Widget _uncapturedOr(String label, String field, double value) {
    if (!reading.isUncaptured(field)) {
      return _line(label, formatMoney('₱', value));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const Text(
            'not captured',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
              color: AppColors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComplianceNotice extends StatelessWidget {
  const _ComplianceNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.caramelSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.caramel.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.caramelDeep,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count BIR field(s) are not captured at the point of sale yet, '
              'so this reading is not BIR-valid. Senior citizen / PWD '
              'discounts and the VAT-exempt split must be recorded during '
              'checkout before this can be filed.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.caramelDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
