import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/nfc_customer_lookup.dart';

typedef RfidUidSubmitted = void Function(String uid);

class RfidUidCaptureField extends StatefulWidget {
  const RfidUidCaptureField({
    super.key,
    required this.onSubmitted,
    this.enabled = true,
    this.hintText = 'Tap here, then scan the card on your OTG reader',
    this.labelText = 'Step 3: Scan card here (UID appears automatically)',
    this.helperText =
        'The reader types the card number like a keyboard. If nothing appears, tap this box and scan again.',
  });

  final RfidUidSubmitted onSubmitted;
  final bool enabled;
  final String hintText;
  final String labelText;
  final String helperText;

  @override
  State<RfidUidCaptureField> createState() => _RfidUidCaptureFieldState();
}

class _RfidUidCaptureFieldState extends State<RfidUidCaptureField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.enabled && mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void submit([String? raw]) {
    if (!widget.enabled) return;
    final uid = normalizeNfcUid(raw ?? _controller.text);
    if (uid.length < 4) return;
    widget.onSubmitted(uid);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      autofocus: true,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        helperText: widget.helperText,
        helperMaxLines: 3,
        prefixIcon: const Icon(Icons.sensors, color: AppColors.green),
        filled: true,
        fillColor: AppColors.lightGreen,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.greenBorder),
        ),
      ),
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      onSubmitted: submit,
      onChanged: (value) {
        if (value.contains('\n') || value.contains('\r')) {
          submit(value);
        }
      },
    );
  }
}

class RfidScanSteps extends StatelessWidget {
  const RfidScanSteps({
    super.key,
    required this.customerLabel,
    this.isUpdate = false,
  });

  final String customerLabel;
  final bool isUpdate;

  @override
  Widget build(BuildContext context) {
    final action = isUpdate ? 'replace the old card for' : 'link this card to';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isUpdate
              ? 'Update RFID card for $customerLabel'
              : 'Link RFID card to $customerLabel',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        const _StepLine(
          number: '1',
          text: 'Plug the OTG RFID reader into the tablet USB port.',
        ),
        const _StepLine(
          number: '2',
          text: 'Tap the scan box below so the cursor is blinking.',
        ),
        _StepLine(
          number: '3',
          text:
              'Hold the loyalty card on the reader to $action $customerLabel.',
        ),
        const _StepLine(
          number: '4',
          text:
              'When the UID appears, press Enter on the reader or tap Link RFID card.',
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.greenBorder),
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.green,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
