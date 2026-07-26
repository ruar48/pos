import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

const _receiptNoteTemplates = <String>[
  'Thank you — come again!',
  'For pickup later',
  'Deliver to back entrance',
  'Paid on account',
  'Handle with care',
];

/// Shows optional receipt note dialog. Returns empty string when skipped,
/// note text when confirmed, or `null` when cancelled.
Future<String?> showReceiptNoteDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _ReceiptNoteDialog(),
  );
}

class _ReceiptNoteDialog extends StatefulWidget {
  const _ReceiptNoteDialog();

  @override
  State<_ReceiptNoteDialog> createState() => _ReceiptNoteDialogState();
}

class _ReceiptNoteDialogState extends State<_ReceiptNoteDialog> {
  final noteController = TextEditingController();

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  void _applyTemplate(String template) {
    setState(() {
      noteController.text = template;
      noteController.selection = TextSelection.collapsed(
        offset: noteController.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Receipt note'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Optional — add a note to print on the receipt, or skip.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick templates',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final template in _receiptNoteTemplates)
                    ActionChip(
                      label: Text(template),
                      onPressed: () => _applyTemplate(template),
                      backgroundColor: AppColors.lightGreen,
                      side: const BorderSide(color: AppColors.greenBorder),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                maxLength: 240,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'e.g. Deliver to back entrance',
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(noteController.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: AppColors.green),
          child: const Text('Complete'),
        ),
      ],
    );
  }
}
