import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/product.dart';
import '../../../models/product_variety.dart';
import '../pages/pos_home_page.dart';

const List<int> kQuantityQuickPicks = [10, 25, 50, 100];

Future<int?> showQuantityEntryDialog(
  BuildContext context, {
  required String productName,
  String? subtitle,
  required int initialQuantity,
  int? maxQuantity,
  String confirmLabel = 'Set quantity',
}) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => QuantityEntryDialog(
      productName: productName,
      subtitle: subtitle,
      initialQuantity: initialQuantity,
      maxQuantity: maxQuantity,
      confirmLabel: confirmLabel,
    ),
  );
}

class QuantityEntryDialog extends StatefulWidget {
  const QuantityEntryDialog({
    super.key,
    required this.productName,
    this.subtitle,
    required this.initialQuantity,
    this.maxQuantity,
    this.confirmLabel = 'Set quantity',
  });

  final String productName;
  final String? subtitle;
  final int initialQuantity;
  final int? maxQuantity;
  final String confirmLabel;

  @override
  State<QuantityEntryDialog> createState() => _QuantityEntryDialogState();
}

class _QuantityEntryDialogState extends State<QuantityEntryDialog> {
  late final TextEditingController controller;
  String? errorText;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuantity > 0 ? widget.initialQuantity : 1;
    controller = TextEditingController(text: '$initial');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  int? _parsedQuantity() {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 1) return null;
    return value;
  }

  void _applyQuickPick(int value) {
    setState(() {
      controller.text = '$value';
      errorText = null;
    });
  }

  void _submit() {
    final quantity = _parsedQuantity();
    if (quantity == null) {
      setState(() => errorText = 'Enter a valid quantity of at least 1');
      return;
    }

    final max = widget.maxQuantity;
    if (max != null && quantity > max) {
      setState(() => errorText = 'Only $max available in stock');
      return;
    }

    Navigator.pop(context, quantity);
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.maxQuantity;

    return AlertDialog(
      title: const Text('Set quantity'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.productName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.subtitle!,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Quantity',
                hintText: 'e.g. 100',
                errorText: errorText,
                suffixIcon: max != null
                    ? Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Align(
                          alignment: Alignment.centerRight,
                          widthFactor: 1,
                          child: Text(
                            'Max $max',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (errorText != null) {
                  setState(() => errorText = null);
                }
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pick in kQuantityQuickPicks)
                  ActionChip(
                    label: Text('$pick'),
                    onPressed: max != null && pick > max
                        ? null
                        : () => _applyQuickPick(pick),
                  ),
              ],
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
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.green),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

String quantityDialogSubtitle({
  required String currencySymbol,
  required double unitPrice,
  int? maxQuantity,
}) {
  final parts = <String>[formatMoney(currencySymbol, unitPrice)];
  if (maxQuantity != null) {
    parts.add('$maxQuantity in stock');
  }
  return parts.join(' • ');
}

Future<void> openPosQuantityEditor(
  BuildContext context,
  PosHomePageState pageState, {
  required Product product,
  ProductVariety? variety,
}) async {
  final liveProduct = pageState.productById(product.id) ?? product;
  final displayName = variety == null
      ? liveProduct.name
      : '${liveProduct.name} - ${variety.name}';
  final unitPrice = variety?.price ?? liveProduct.price;
  final currentQty = pageState.quantityInCart(liveProduct, variety: variety);
  final maxQty = pageState.maxCartQuantity(liveProduct, variety: variety);

  final qty = await showQuantityEntryDialog(
    context,
    productName: displayName,
    subtitle: quantityDialogSubtitle(
      currencySymbol: pageState.settings.currencySymbol,
      unitPrice: unitPrice,
      maxQuantity: maxQty,
    ),
    initialQuantity: currentQty > 0 ? currentQty : 1,
    maxQuantity: maxQty,
    confirmLabel: currentQty > 0 ? 'Update cart' : 'Add to cart',
  );

  if (qty != null && context.mounted) {
    pageState.setCartQuantity(liveProduct, qty, variety: variety);
  }
}
