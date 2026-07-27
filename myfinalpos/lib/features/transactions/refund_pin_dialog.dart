import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// Prompts for the shared admin refund PIN. Returns the entered PIN, or
/// null if the user cancelled.
Future<String?> showRefundPinDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _RefundPinDialog(),
  );
}

class _RefundPinDialog extends StatefulWidget {
  const _RefundPinDialog();

  @override
  State<_RefundPinDialog> createState() => _RefundPinDialogState();
}

class _RefundPinDialogState extends State<_RefundPinDialog> {
  final _pinController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  bool get _isValid => RegExp(r'^\d{4,6}$').hasMatch(_pinController.text.trim());

  void _confirm() {
    if (!_isValid) return;
    Navigator.pop(context, _pinController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Admin PIN Required'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ask an admin to enter the refund PIN to approve this refund.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              autofocus: true,
              obscureText: _obscure,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(
                labelText: 'PIN',
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _confirm(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                label: Text(_obscure ? 'Show' : 'Hide'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isValid ? _confirm : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
