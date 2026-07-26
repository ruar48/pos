import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/layout_utils.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/app_settings.dart';
import '../../../models/app_user.dart';
import '../../../models/branch.dart';
import '../../pos/pages/pos_home_page.dart';
import '../../receipt/receipt_preview_widget.dart';
import '../../receipt/receipt_printer.dart';
import 'management_widgets.dart';

const _currencyOptions = <String, String>{
  '₱': 'Philippine Peso (₱)',
  r'$': r'US Dollar ($)',
  '€': 'Euro (€)',
  'PHP': 'PHP label',
};

class SettingsManagementContent extends StatefulWidget {
  const SettingsManagementContent({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<SettingsManagementContent> createState() =>
      _SettingsManagementContentState();
}

class _SettingsManagementContentState extends State<SettingsManagementContent> {
  late AppSettingsModel settings;
  late ReceiptStoreConfig receiptStore;
  late TextEditingController taxRateController;
  late TextEditingController loyaltyPointsController;
  late TextEditingController loyaltySpendController;
  late TextEditingController loyaltyRedeemController;
  late TextEditingController storeNameController;
  late TextEditingController storeSubtitleController;
  late TextEditingController storeAddressController;
  late TextEditingController storeAddressLine2Controller;
  late TextEditingController logoTextController;
  late TextEditingController tinController;
  late TextEditingController taxStatusController;
  late TextEditingController posTerminalController;
  late TextEditingController atpDateController;
  late TextEditingController seriesRangeController;
  late TextEditingController lowStockRecipientsController;
  String? logoImagePath;
  late int selectedBranchId;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _syncFromPageState();
  }

  void _syncFromPageState() {
    settings = widget.pageState.settings;
    receiptStore = widget.pageState.receiptStore;
    final defaultBranch = settings.defaultBranchId;
    selectedBranchId = defaultBranch != null &&
            defaultBranch > 0 &&
            widget.pageState.branches.any((b) => b.id == defaultBranch)
        ? defaultBranch
        : widget.pageState.activeBranchId;
    taxRateController = TextEditingController(
      text: (settings.taxRate * 100).toStringAsFixed(2),
    );
    loyaltyPointsController = TextEditingController(
      text: '${settings.loyaltyPointsPerUnit}',
    );
    loyaltySpendController = TextEditingController(
      text: settings.loyaltySpendUnit.toStringAsFixed(0),
    );
    loyaltyRedeemController = TextEditingController(
      text: '${settings.loyaltyRedeemPointsPerPeso}',
    );
    storeNameController = TextEditingController(text: receiptStore.storeName);
    storeSubtitleController =
        TextEditingController(text: receiptStore.storeSubtitle);
    storeAddressController =
        TextEditingController(text: receiptStore.addressLine1);
    storeAddressLine2Controller =
        TextEditingController(text: receiptStore.addressLine2);
    logoTextController = TextEditingController(text: receiptStore.logoText);
    tinController = TextEditingController(text: receiptStore.tin);
    taxStatusController = TextEditingController(text: receiptStore.taxStatus);
    posTerminalController =
        TextEditingController(text: receiptStore.posTerminalId);
    atpDateController =
        TextEditingController(text: receiptStore.atpDateIssued);
    seriesRangeController =
        TextEditingController(text: receiptStore.seriesRange);
    lowStockRecipientsController = TextEditingController(
      text: settings.lowStockEmailRecipients,
    );
    logoImagePath = receiptStore.logoImagePath;
  }

  ReceiptStoreConfig _draftReceiptStore() {
    return ReceiptStoreConfig(
      logoText: logoTextController.text.trim(),
      logoImagePath: logoImagePath,
      storeName: storeNameController.text.trim(),
      storeSubtitle: storeSubtitleController.text.trim(),
      addressLine1: storeAddressController.text.trim(),
      addressLine2: storeAddressLine2Controller.text.trim(),
      tin: tinController.text.trim(),
      taxStatus: taxStatusController.text.trim(),
      posTerminalId: posTerminalController.text.trim(),
      ptuNo: receiptStore.ptuNo,
      atpNo: receiptStore.atpNo,
      atpDateIssued: atpDateController.text.trim(),
      seriesRange: seriesRangeController.text.trim(),
    );
  }

  String _printModeLabel() {
    if (!settings.autoPrintReceipt) return 'Manual';
    return settings.doublePrintReceipt ? 'Auto ×2' : 'Auto';
  }

  String _attendanceSummary() {
    return 'Morning: accept ${settings.attendanceMorningAcceptStart}–'
        '${settings.attendanceMorningCutoff} (official '
        '${settings.attendanceMorningOfficialStart}, on time until '
        '${settings.attendanceMorningGraceEnd}, late from '
        '${settings.attendanceMorningLateStart}). Break out '
        '${settings.attendanceBreakOutStart}–${settings.attendanceBreakOutEnd}. '
        'Afternoon: accept ${settings.attendanceAfternoonAcceptStart}–'
        '${settings.attendanceAfternoonCutoff} (on time until '
        '${settings.attendanceAfternoonOnTimeEnd}, late from '
        '${settings.attendanceAfternoonLateStart}). Time-out from '
        '${settings.attendanceTimeoutStart}. After each cutoff, employees '
        'without a session time-in are marked absent for that session.';
  }

  Widget _sessionTimeField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return _TimeSettingField(
      label: label,
      value: value,
      onPick: () => _pickTime(current: value, onChanged: onChanged),
    );
  }

  Widget _attendanceSubheading(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Future<void> _pickTime({
    required String current,
    required ValueChanged<String> onChanged,
  }) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: parts.isNotEmpty ? toInt(parts[0]).clamp(0, 23) : 8,
      minute: parts.length > 1 ? toInt(parts[1]).clamp(0, 59) : 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    onChanged(
      '${picked.hour.toString().padLeft(2, '0')}:'
      '${picked.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final path = await ReceiptStoreConfig.saveLogoImage(bytes);
    if (!mounted) return;
    setState(() => logoImagePath = path);
  }

  Future<void> _removeLogo() async {
    await ReceiptStoreConfig.deleteLogoImage(logoImagePath);
    if (!mounted) return;
    setState(() => logoImagePath = null);
  }

  void _refreshPreview() => setState(() {});

  @override
  void dispose() {
    taxRateController.dispose();
    loyaltyPointsController.dispose();
    loyaltySpendController.dispose();
    loyaltyRedeemController.dispose();
    storeNameController.dispose();
    storeSubtitleController.dispose();
    storeAddressController.dispose();
    storeAddressLine2Controller.dispose();
    logoTextController.dispose();
    tinController.dispose();
    taxStatusController.dispose();
    posTerminalController.dispose();
    atpDateController.dispose();
    seriesRangeController.dispose();
    lowStockRecipientsController.dispose();
    super.dispose();
  }

  Branch? get activeBranch {
    for (final branch in widget.pageState.branches) {
      if (branch.id == selectedBranchId) return branch;
    }
    return widget.pageState.branches.isNotEmpty
        ? widget.pageState.branches.first
        : null;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final updatedSettings = settings.copyWith(
        taxRate: toDouble(taxRateController.text) / 100,
        loyaltyPointsPerUnit: toInt(loyaltyPointsController.text),
        loyaltySpendUnit: toDouble(loyaltySpendController.text),
        loyaltyRedeemPointsPerPeso: toInt(loyaltyRedeemController.text),
        lowStockEmailRecipients: lowStockRecipientsController.text.trim(),
      );
      final updatedReceiptStore = _draftReceiptStore();

      await widget.pageState.updateSettings(
        updatedSettings,
        receiptStore: updatedReceiptStore,
        defaultBranchId: selectedBranchId,
      );
      if (widget.pageState.widget.currentUser.canMonitorAllBranches &&
          widget.pageState.dashboardMonitorBranchId !=
              PosHomePageState.allBranchesMonitorId) {
        await widget.pageState.setDashboardMonitorBranch(
          selectedBranchId,
          syncPosBranch: false,
        );
      }

      if (!mounted) return;
      setState(() {
        settings = widget.pageState.settings;
        receiptStore = widget.pageState.receiptStore;
        lowStockRecipientsController.text = settings.lowStockEmailRecipients;
      });
      showTopSuccess(context, 'Settings saved');
    } catch (error) {
      if (!mounted) return;
      showTopError(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.pageState.widget.currentUser;
    final branch = activeBranch;
    final previewReceipt = sampleReceiptPreview(
      store: _draftReceiptStore(),
      currencySymbol: settings.currencySymbol,
      taxRate: toDouble(taxRateController.text) / 100,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final splitView = constraints.maxWidth >= posSplitBreakpoint;
        final form = _buildSettingsForm(user, branch);
        final previewPanel = _SettingsReceiptPreviewPanel(
          receipt: previewReceipt,
          saving: saving,
          onSave: _save,
        );

        if (splitView) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 8),
                  child: form,
                ),
              ),
              Expanded(flex: 2, child: previewPanel),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(child: form),
            ),
            SizedBox(height: 520, child: previewPanel),
          ],
        );
      },
    );
  }

  Widget _buildSettingsForm(AppUser user, Branch? branch) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final cards = [
              SummaryCard(
                label: 'Tax Rate',
                value: '${(settings.taxRate * 100).toStringAsFixed(2)}%',
                icon: Icons.percent,
                color: AppColors.blue,
              ),
              SummaryCard(
                label: 'Currency',
                value: settings.currencySymbol,
                icon: Icons.payments_outlined,
              ),
              SummaryCard(
                label: 'POS Terminal',
                value: widget.pageState.receiptStore.posTerminalId,
                icon: Icons.store_outlined,
                color: AppColors.darkGreen,
              ),
              SummaryCard(
                label: 'Printing',
                value: _printModeLabel(),
                subtitle: widget.pageState.resolvedPrinter.isConfigured
                    ? widget.pageState.resolvedPrinter.statusLabel
                    : 'Configure printer in My Printer',
                icon: Icons.print_outlined,
                color: settings.autoPrintReceipt ? AppColors.green : AppColors.amber,
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
                  SizedBox(width: 220, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Receipt Template',
          subtitle: 'Customize header and legal text on receipts',
          icon: Icons.receipt_long_outlined,
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: logoImagePath != null && File(logoImagePath!).existsSync()
                      ? Image.file(File(logoImagePath!), fit: BoxFit.contain)
                      : const Icon(Icons.image_outlined, color: AppColors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.upload_outlined, size: 18),
                        label: const Text('Upload logo image'),
                      ),
                      if (logoImagePath != null)
                        TextButton(
                          onPressed: _removeLogo,
                          child: const Text('Remove logo image'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: logoTextController,
              onChanged: (_) => _refreshPreview(),
              decoration: const InputDecoration(
                labelText: 'Logo banner text',
                hintText: '[ Farm & Tractor ]',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: storeNameController,
              onChanged: (_) => _refreshPreview(),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Store Name',
                prefixIcon: Icon(Icons.store),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: storeSubtitleController,
              onChanged: (_) => _refreshPreview(),
              decoration: const InputDecoration(
                labelText: 'Store Subtitle',
                prefixIcon: Icon(Icons.subtitles_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: storeAddressController,
              onChanged: (_) => _refreshPreview(),
              decoration: const InputDecoration(
                labelText: 'Address Line 1',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: storeAddressLine2Controller,
              onChanged: (_) => _refreshPreview(),
              decoration: const InputDecoration(
                labelText: 'Address Line 2',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tinController,
              onChanged: (_) => _refreshPreview(),
              decoration: const InputDecoration(
                labelText: 'TIN',
                prefixIcon: Icon(Icons.numbers_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: taxStatusController,
              onChanged: (_) => _refreshPreview(),
              decoration: const InputDecoration(
                labelText: 'Tax Status',
                hintText: 'NON-VAT REGISTERED',
                prefixIcon: Icon(Icons.gavel_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: posTerminalController,
              onChanged: (_) => _refreshPreview(),
              decoration: const InputDecoration(
                labelText: 'POS Terminal ID',
                prefixIcon: Icon(Icons.point_of_sale_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: atpDateController,
              onChanged: (_) => _refreshPreview(),
              decoration: const InputDecoration(
                labelText: 'ATP Date Issued',
                hintText: '01/15/2026',
                prefixIcon: Icon(Icons.event_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: seriesRangeController,
              onChanged: (_) => _refreshPreview(),
              decoration: const InputDecoration(
                labelText: 'Invoice Series Range',
                hintText: '0000001 - 9999999',
                prefixIcon: Icon(Icons.format_list_numbered_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Tax & Currency',
          subtitle:
              'Set to 0% to disable VAT on all new sales and refunds',
          icon: Icons.calculate_outlined,
          children: [
            TextField(
              controller: taxRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Tax / VAT Rate (%)',
                hintText: '12.00 (use 0 for no tax)',
                prefixIcon: Icon(Icons.percent),
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _currencyOptions.containsKey(settings.currencySymbol)
                  ? settings.currencySymbol
                  : settings.currencySymbol,
              decoration: const InputDecoration(
                labelText: 'Currency Symbol',
                prefixIcon: Icon(Icons.currency_exchange),
              ),
              items: [
                for (final entry in _currencyOptions.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                if (!_currencyOptions.containsKey(settings.currencySymbol))
                  DropdownMenuItem(
                    value: settings.currencySymbol,
                    child: Text(settings.currencySymbol),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(
                  () => settings = settings.copyWith(currencySymbol: value),
                );
              },
            ),
            if (user.canMonitorAllBranches &&
                widget.pageState.branches.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: selectedBranchId,
                decoration: const InputDecoration(
                  labelText: 'Default Branch',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
                items: [
                  for (final branch in widget.pageState.branches
                      .where((item) => item.isActive))
                    DropdownMenuItem(
                      value: branch.id,
                      child: Text(branch.name),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => selectedBranchId = value);
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Receipt Printing',
          subtitle:
              'Store-wide behavior. Each cashier configures their own printer in My Printer.',
          icon: Icons.print_outlined,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.pageState.resolvedPrinter.isConfigured
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    color: widget.pageState.resolvedPrinter.isConfigured
                        ? AppColors.green
                        : AppColors.amber,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'This tablet printer',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          widget.pageState.resolvedPrinter.statusLabel,
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
            ),
            const SizedBox(height: 12),
            _SettingsToggle(
              title: 'Auto Print Receipt',
              subtitle: 'Print automatically after payment on configured tablets',
              icon: Icons.print_disabled_outlined,
              value: settings.autoPrintReceipt,
              onChanged: (value) => setState(
                () => settings = settings.copyWith(autoPrintReceipt: value),
              ),
            ),
            _SettingsToggle(
              title: 'Double Print',
              subtitle: 'Print each receipt twice after payment',
              icon: Icons.copy_outlined,
              value: settings.doublePrintReceipt,
              onChanged: (value) => setState(
                () => settings = settings.copyWith(doublePrintReceipt: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Attendance Schedule',
          subtitle:
              'Configure morning, break, afternoon, and time-out windows. All times are editable.',
          icon: Icons.schedule_outlined,
          children: [
            _attendanceSubheading('Morning session'),
            _sessionTimeField(
              label: 'Time-in acceptance start',
              value: settings.attendanceMorningAcceptStart,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceMorningAcceptStart: value),
              ),
            ),
            const SizedBox(height: 12),
            _sessionTimeField(
              label: 'Official start time',
              value: settings.attendanceMorningOfficialStart,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceMorningOfficialStart: value),
              ),
            ),
            const SizedBox(height: 12),
            _sessionTimeField(
              label: 'Grace period end (on time until)',
              value: settings.attendanceMorningGraceEnd,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceMorningGraceEnd: value),
              ),
            ),
            const SizedBox(height: 12),
            _sessionTimeField(
              label: 'Late period start',
              value: settings.attendanceMorningLateStart,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceMorningLateStart: value),
              ),
            ),
            const SizedBox(height: 12),
            _sessionTimeField(
              label: 'Morning cutoff (no more time-in)',
              value: settings.attendanceMorningCutoff,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceMorningCutoff: value),
              ),
            ),
            const SizedBox(height: 16),
            _attendanceSubheading('Break session'),
            _sessionTimeField(
              label: 'Break time-out start',
              value: settings.attendanceBreakOutStart,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceBreakOutStart: value),
              ),
            ),
            const SizedBox(height: 12),
            _sessionTimeField(
              label: 'Break time-out end',
              value: settings.attendanceBreakOutEnd,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceBreakOutEnd: value),
              ),
            ),
            const SizedBox(height: 16),
            _attendanceSubheading('Afternoon session'),
            _sessionTimeField(
              label: 'Time-in acceptance start',
              value: settings.attendanceAfternoonAcceptStart,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceAfternoonAcceptStart: value),
              ),
            ),
            const SizedBox(height: 12),
            _sessionTimeField(
              label: 'On-time limit',
              value: settings.attendanceAfternoonOnTimeEnd,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceAfternoonOnTimeEnd: value),
              ),
            ),
            const SizedBox(height: 12),
            _sessionTimeField(
              label: 'Late period start',
              value: settings.attendanceAfternoonLateStart,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceAfternoonLateStart: value),
              ),
            ),
            const SizedBox(height: 12),
            _sessionTimeField(
              label: 'Afternoon cutoff (no more time-in)',
              value: settings.attendanceAfternoonCutoff,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceAfternoonCutoff: value),
              ),
            ),
            const SizedBox(height: 16),
            _attendanceSubheading('Time-out'),
            _sessionTimeField(
              label: 'Time-out start',
              value: settings.attendanceTimeoutStart,
              onChanged: (value) => setState(
                () => settings =
                    settings.copyWith(attendanceTimeoutStart: value),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _attendanceSummary(),
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'POS Rules',
          subtitle: 'Checkout and inventory behavior',
          icon: Icons.rule_folder_outlined,
          children: [
            _SettingsToggle(
              title: 'Allow Negative Stock',
              subtitle: 'Sell items even when stock is zero',
              icon: Icons.inventory_2_outlined,
              value: settings.allowNegativeStock,
              onChanged: (value) => setState(
                () => settings = settings.copyWith(allowNegativeStock: value),
              ),
            ),
            const Divider(height: 24),
            _SettingsToggle(
              title: 'Email on low stock',
              subtitle:
                  'Send an alert when item stock reaches its reorder level',
              icon: Icons.mail_outline,
              value: settings.lowStockEmailEnabled,
              onChanged: (value) => setState(
                () => settings = settings.copyWith(lowStockEmailEnabled: value),
              ),
            ),
            if (settings.lowStockEmailEnabled) ...[
              const SizedBox(height: 12),
              TextField(
                controller: lowStockRecipientsController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Low stock alert emails',
                  hintText: user.email.endsWith('.local')
                      ? 'owner@gmail.com'
                      : 'Leave blank to use ${user.email}',
                  prefixIcon: const Icon(Icons.alternate_email_outlined),
                  helperText:
                      'Comma-separated addresses. Uses Gmail sender if blank.',
                ),
              ),
            ],
            const Divider(height: 24),
            _SettingsToggle(
              title: 'Loyalty Program',
              subtitle: 'Let registered customers earn and redeem points',
              icon: Icons.card_giftcard_outlined,
              value: settings.loyaltyEnabled,
              onChanged: (value) => setState(
                () => settings = settings.copyWith(loyaltyEnabled: value),
              ),
            ),
            if (settings.loyaltyEnabled) ...[
              const Divider(height: 24),
              TextField(
                controller: loyaltyPointsController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Points Earned',
                  hintText: '50',
                  prefixIcon: const Icon(Icons.stars_outlined),
                  helperText:
                      'Example: 50 points when a customer spends ${formatMoney(settings.currencySymbol, toDouble(loyaltySpendController.text) > 0 ? toDouble(loyaltySpendController.text) : settings.loyaltySpendUnit)}',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: loyaltySpendController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'Spend Amount For Points',
                  hintText: '1000',
                  prefixText: settings.currencySymbol,
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: loyaltyRedeemController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Points Needed For ${formatMoney(settings.currencySymbol, 1)} Discount',
                  hintText: '10',
                  prefixIcon: const Icon(Icons.redeem_outlined),
                  helperText:
                      '${toInt(loyaltyRedeemController.text) > 0 ? toInt(loyaltyRedeemController.text) : settings.loyaltyRedeemPointsPerPeso} points = ${formatMoney(settings.currencySymbol, 1)} off at checkout',
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Signed In Account',
          subtitle: 'Current tablet session',
          icon: Icons.account_circle_outlined,
          children: [
            _InfoRow(label: 'Name', value: user.fullName),
            _InfoRow(label: 'Email', value: user.email),
            _InfoRow(label: 'Role', value: user.roleLabel),
          ],
        ),
      ],
    );
  }
}

class _SettingsReceiptPreviewPanel extends StatelessWidget {
  const _SettingsReceiptPreviewPanel({
    required this.receipt,
    required this.saving,
    required this.onSave,
  });

  final ReceiptData receipt;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Column(
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
            child: FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 20),
              label: Text(saving ? 'Saving...' : 'Save Settings'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppColors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
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
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.muted, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeSettingField extends StatelessWidget {
  const _TimeSettingField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final String value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.access_time),
          suffixIcon: IconButton(
            icon: const Icon(Icons.schedule),
            onPressed: onPick,
          ),
        ),
        child: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
