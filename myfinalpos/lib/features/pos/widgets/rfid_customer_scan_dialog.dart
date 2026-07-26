import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../pages/pos_home_page.dart';
import 'rfid_uid_capture.dart';

Future<bool> showRfidCustomerScanDialog(
  BuildContext context,
  PosHomePageState pageState,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => RfidCustomerScanDialog(pageState: pageState),
  );
  return result == true;
}

@Deprecated('Use showRfidCustomerScanDialog')
Future<bool> showNfcCustomerScanDialog(
  BuildContext context,
  PosHomePageState pageState,
) =>
    showRfidCustomerScanDialog(context, pageState);

class RfidCustomerScanDialog extends StatefulWidget {
  const RfidCustomerScanDialog({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  State<RfidCustomerScanDialog> createState() => _RfidCustomerScanDialogState();
}

class _RfidCustomerScanDialogState extends State<RfidCustomerScanDialog> {
  String _phase = 'ready';
  String? _error;
  bool _busy = false;

  Future<void> _handleUid(String uid) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _phase = 'linking';
      _error = null;
    });

    final ok = await widget.pageState.selectCustomerByRfidUid(uid);
    if (!mounted) return;

    if (ok) {
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _busy = false;
      _phase = 'error';
      _error =
          'No customer is registered for this RFID card. Open Customers → select the farmer → Link RFID card, scan the same card there, then try checkout again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan RFID at checkout'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RfidScanSteps(
              customerLabel: 'the loyalty member',
              isUpdate: false,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sensors,
                    color: _phase == 'linking'
                        ? AppColors.muted
                        : AppColors.green,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _phase == 'linking'
                          ? 'Looking up customer for this RFID card…'
                          : 'Ready — tap the box below, then scan the card.',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (_phase == 'linking')
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            RfidUidCaptureField(
              enabled: !_busy,
              onSubmitted: _handleUid,
              labelText: 'Scan box — UID must appear here',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
