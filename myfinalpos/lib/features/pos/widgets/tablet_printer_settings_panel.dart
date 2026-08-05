import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/top_toast.dart';
import '../../../models/printer_settings.dart';
import '../../management/widgets/management_widgets.dart';
import '../../receipt/printer_transport.dart';
import '../pages/pos_home_page.dart';

class TabletPrinterSettingsPanel extends StatefulWidget {
  const TabletPrinterSettingsPanel({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<TabletPrinterSettingsPanel> createState() =>
      _TabletPrinterSettingsPanelState();
}

class _TabletPrinterSettingsPanelState
    extends State<TabletPrinterSettingsPanel> {
  late TextEditingController printerHostController;
  late TextEditingController printerDeviceController;
  late TextEditingController printerPortController;
  PrinterConnectionType printerType = PrinterConnectionType.network;
  int paperWidthChars = kDefaultThermalPaperWidthChars;
  bool saving = false;
  bool bluetoothTesting = false;

  static const _paperWidthOptions = [24, 26, 28, 30, 32, 42, 48];

  @override
  void initState() {
    super.initState();
    _syncFromPageState();
  }

  void _syncFromPageState() {
    final draft = widget.pageState.devicePrinterConfigured
        ? widget.pageState.devicePrinter
        : PrinterConfig.fromSettings(widget.pageState.settings);

    printerType = draft.type;
    paperWidthChars = _paperWidthOptions.contains(draft.paperWidthChars)
        ? draft.paperWidthChars
        : kDefaultThermalPaperWidthChars;
    printerHostController = TextEditingController(text: draft.host);
    printerDeviceController = TextEditingController(text: draft.device);
    printerPortController = TextEditingController(
      text: '${draft.port > 0 ? draft.port : 9100}',
    );
  }

  PrinterConfig get _draftConfig => PrinterConfig(
        type: printerType,
        host: printerHostController.text.trim(),
        port: toInt(printerPortController.text).clamp(1, 65535),
        device: printerType == PrinterConnectionType.bluetooth
            ? PrinterTransport.normalizeMacAddress(
                printerDeviceController.text.trim(),
              )
            : printerDeviceController.text.trim(),
        paperWidthChars: paperWidthChars,
      );

  String get _statusLabel => _draftConfig.statusLabel;

  Future<void> _pickBluetoothPrinter() async {
    final devices = await PrinterTransport.listBluetoothPrinters();
    if (!mounted) return;
    if (devices.isEmpty) {
      showTopWarning(context, 'No paired Bluetooth printers found.');
      return;
    }

    final picked = await showModalBottomSheet<BluetoothInfo>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final device in devices)
                ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(device.name),
                  subtitle: Text(device.macAdress),
                  onTap: () => Navigator.pop(context, device),
                ),
            ],
          ),
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      printerDeviceController.text =
          PrinterTransport.normalizeMacAddress(picked.macAdress);
    });
  }

  Future<void> _testBluetoothPrinter() async {
    final mac = printerDeviceController.text.trim();
    if (!PrinterTransport.isValidMacAddress(mac)) {
      showTopWarning(
        context,
        'Enter or choose a valid Bluetooth MAC address first.',
      );
      return;
    }

    setState(() => bluetoothTesting = true);
    try {
      final result = await PrinterTransport.testBluetoothConnection(
        macAddress: mac,
      );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(
              result.passed ? 'Bluetooth test passed' : 'Bluetooth test failed',
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.summary,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  for (final step in result.steps) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          step.passed
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 18,
                          color: step.passed ? AppColors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                step.message,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      if (result.passed) {
        showTopSuccess(context, result.summary);
      } else {
        showTopError(context, result.summary);
      }
    } catch (error) {
      if (mounted) {
        showTopError(context, 'Bluetooth test failed: $error');
      }
    } finally {
      if (mounted) setState(() => bluetoothTesting = false);
    }
  }

  Future<void> _pickUsbPrinter() async {
    final devices = await PrinterTransport.listUsbPrinterIds();
    if (!mounted) return;
    if (devices.isEmpty) {
      showTopWarning(
          context, 'No USB printers detected. Connect one with OTG.');
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final device in devices)
                ListTile(
                  leading: const Icon(Icons.usb),
                  title: Text(device),
                  onTap: () =>
                      Navigator.pop(context, device.split('·').first.trim()),
                ),
            ],
          ),
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      printerDeviceController.text = picked;
    });
  }

  Future<void> _save() async {
    final config = _draftConfig;
    if (!config.isConfigured) {
      showTopWarning(
        context,
        'Complete the printer details for the selected connection type.',
      );
      return;
    }

    setState(() => saving = true);
    try {
      await widget.pageState.saveDevicePrinter(config);
      if (!mounted) return;
      showTopSuccess(
        context,
        'Printer saved for this tablet only. Other cashiers are not affected.',
      );
    } catch (error) {
      if (mounted) showTopError(context, error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    printerHostController.dispose();
    printerDeviceController.dispose();
    printerPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.pageState.widget.currentUser;
    final activeConfig = widget.pageState.resolvedPrinter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SummaryCard(
          label: 'This tablet',
          value: activeConfig.statusLabel,
          subtitle: widget.pageState.devicePrinterConfigured
              ? 'Saved on this device'
              : 'Using store default until you save here',
          icon: Icons.tablet_android_outlined,
          color: activeConfig.isConfigured ? AppColors.green : AppColors.amber,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Printer setup',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Signed in as ${user.fullName}. This printer applies only to this tablet.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<PrinterConnectionType>(
                value: printerType,
                decoration: const InputDecoration(
                  labelText: 'Connection Type',
                  prefixIcon: Icon(Icons.settings_ethernet_outlined),
                ),
                items: [
                  for (final type in PrinterConnectionType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => printerType = value);
                },
              ),
              const SizedBox(height: 12),
              if (printerType == PrinterConnectionType.network) ...[
                TextField(
                  controller: printerHostController,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'Network Printer IP / Host',
                    hintText: '192.168.1.100',
                    prefixIcon: Icon(Icons.lan_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: printerPortController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '9100',
                    prefixIcon: Icon(Icons.numbers_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use the IP of the printer beside this cashier station.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
              if (printerType == PrinterConnectionType.bluetooth) ...[
                TextField(
                  controller: printerDeviceController,
                  decoration: const InputDecoration(
                    labelText: 'Bluetooth MAC Address',
                    hintText: 'AA:BB:CC:DD:EE:FF',
                    prefixIcon: Icon(Icons.bluetooth_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                if (!kIsWeb && Platform.isAndroid)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _pickBluetoothPrinter,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Choose paired printer'),
                    ),
                  ),
                const SizedBox(height: 8),
                if (!kIsWeb && Platform.isAndroid)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed:
                          bluetoothTesting ? null : _testBluetoothPrinter,
                      icon: bluetoothTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bluetooth_connected, size: 18),
                      label: Text(
                        bluetoothTesting
                            ? 'Testing Bluetooth...'
                            : 'Test Bluetooth printer',
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Pair this tablet to the cashier printer in Android Bluetooth settings first.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
              if (printerType == PrinterConnectionType.usb) ...[
                TextField(
                  controller: printerDeviceController,
                  decoration: const InputDecoration(
                    labelText: 'USB Device ID',
                    hintText: '1234:5678',
                    prefixIcon: Icon(Icons.usb_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                if (!kIsWeb && Platform.isAndroid)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _pickUsbPrinter,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Scan USB printers'),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Connect the thermal printer to this tablet with an OTG cable.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: paperWidthChars,
                decoration: const InputDecoration(
                  labelText: 'Paper Width (characters per line)',
                  prefixIcon: Icon(Icons.straighten_outlined),
                ),
                items: [
                  for (final width in _paperWidthOptions)
                    DropdownMenuItem(
                      value: width,
                      child: Text(
                        width == 48
                            ? '48 columns — 72 mm printer (recommended)'
                            : width == 32
                                ? '32 columns — 58 mm printer'
                                : '$width columns',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => paperWidthChars = value);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Your printer self-test shows 72 mm / 48 characters, so select '
                '48 columns. Use 32 columns only for a 58 mm printer.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.greenBorder),
                ),
                child: Text(
                  'Draft: $_statusLabel',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkGreen,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: saving ? null : _save,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label:
                    Text(saving ? 'Saving...' : 'Save printer for this tablet'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppColors.green,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
