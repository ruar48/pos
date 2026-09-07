import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../pages/pos_home_page.dart';

/// Statutory discount capture (senior citizen / PWD / NAAC / solo parent).
///
/// BIR requires the cardholder's name and ID number to be recorded against the
/// sale, and each discount type to be reported on its own Z-reading line, so
/// both fields are mandatory here. The 20% figure shown is a preview — the
/// server recomputes the discount and the VAT-exempt split at checkout and is
/// the authority on both.
class StatutoryDiscountOption {
  const StatutoryDiscountOption({
    required this.type,
    required this.label,
    required this.idLabel,
  });

  final String type;
  final String label;
  final String idLabel;
}

const statutoryDiscountOptions = <StatutoryDiscountOption>[
  StatutoryDiscountOption(
    type: 'sc',
    label: 'Senior Citizen',
    idLabel: 'OSCA / Senior Citizen ID no.',
  ),
  StatutoryDiscountOption(
    type: 'pwd',
    label: 'PWD',
    idLabel: 'PWD ID no.',
  ),
  StatutoryDiscountOption(
    type: 'naac',
    label: 'National Athlete / Coach',
    idLabel: 'PNSTM ID no.',
  ),
  StatutoryDiscountOption(
    type: 'solo_parent',
    label: 'Solo Parent',
    idLabel: 'Solo Parent ID no.',
  ),
];

String statutoryDiscountLabel(String type) {
  for (final option in statutoryDiscountOptions) {
    if (option.type == type) return option.label;
  }
  return type;
}

Future<void> showStatutoryDiscountDialog(
  BuildContext context,
  PosHomePageState pageState,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => _StatutoryDiscountDialog(pageState: pageState),
  );
}

class _StatutoryDiscountDialog extends StatefulWidget {
  const _StatutoryDiscountDialog({required this.pageState});

  final PosHomePageState pageState;

  @override
  State<_StatutoryDiscountDialog> createState() =>
      _StatutoryDiscountDialogState();
}

class _StatutoryDiscountDialogState extends State<_StatutoryDiscountDialog> {
  late String _type =
      widget.pageState.statutoryDiscountType.isEmpty
          ? 'sc'
          : widget.pageState.statutoryDiscountType;
  late final _nameController =
      TextEditingController(text: widget.pageState.statutoryCustomerName);
  late final _idController =
      TextEditingController(text: widget.pageState.statutoryIdNumber);

  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  StatutoryDiscountOption get _option => statutoryDiscountOptions.firstWhere(
        (option) => option.type == _type,
      );

  void _apply() {
    final name = _nameController.text.trim();
    final id = _idController.text.trim();

    // Both are mandatory: a statutory discount without the cardholder's
    // details on file is not defensible in a BIR audit.
    if (name.isEmpty || id.isEmpty) {
      setState(() {
        _error = 'Cardholder name and ID number are both required.';
      });
      return;
    }

    widget.pageState.applyStatutoryDiscount(
      type: _type,
      idNumber: id,
      customerName: name,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Statutory discount'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<String>(
              groupValue: _type,
              onChanged: (value) => setState(() => _type = value ?? 'sc'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in statutoryDiscountOptions)
                    RadioListTile<String>(
                      value: option.type,
                      title: Text(option.label),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Cardholder name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _idController,
              decoration: InputDecoration(labelText: _option.idLabel),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.caramelSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'The sale becomes VAT-exempt and 20% is deducted. The exact '
                'amount is computed by the server at checkout.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.caramelDeep,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.pageState.hasStatutoryDiscount)
          TextButton(
            onPressed: () {
              widget.pageState.clearStatutoryDiscount();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _apply, child: const Text('Apply')),
      ],
    );
  }
}
