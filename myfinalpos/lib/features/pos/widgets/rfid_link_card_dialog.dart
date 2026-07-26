import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/top_toast.dart';
import '../pages/pos_home_page.dart';
import 'rfid_uid_capture.dart';

Future<bool> showRfidLinkCardDialog(
  BuildContext context, {
  required PosHomePageState pageState,
  required int customerId,
  required String customerName,
  String? currentRfidUid,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => RfidLinkCardDialog(
      pageState: pageState,
      customerId: customerId,
      customerName: customerName,
      currentRfidUid: currentRfidUid,
    ),
  );
  return result == true;
}

class RfidLinkCardDialog extends StatefulWidget {
  const RfidLinkCardDialog({
    super.key,
    required this.pageState,
    required this.customerId,
    required this.customerName,
    this.currentRfidUid,
  });

  final PosHomePageState pageState;
  final int customerId;
  final String customerName;
  final String? currentRfidUid;

  @override
  State<RfidLinkCardDialog> createState() => _RfidLinkCardDialogState();
}

class _RfidLinkCardDialogState extends State<RfidLinkCardDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _saveUid(String uid) async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.pageState.linkRfidCardForCustomer(widget.customerId, uid);
      if (!mounted) return;
      showAppTopSuccess('RFID card linked to ${widget.customerName}');
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUpdate = widget.currentRfidUid != null &&
        widget.currentRfidUid!.trim().isNotEmpty;

    return AlertDialog(
      title: Text(isUpdate ? 'Update RFID card' : 'Link RFID card'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RfidScanSteps(
              customerLabel: widget.customerName,
              isUpdate: isUpdate,
            ),
            if (isUpdate) ...[
              const SizedBox(height: 10),
              Text(
                'Current card UID: ${widget.currentRfidUid}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppColors.darkGreen,
                ),
              ),
            ],
            const SizedBox(height: 12),
            RfidUidCaptureField(
              enabled: !_saving,
              onSubmitted: _saveUid,
              labelText: isUpdate
                  ? 'Scan the new card here'
                  : 'Scan box — UID must appear here',
            ),
            if (_saving) ...[
              const SizedBox(height: 12),
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
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
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
