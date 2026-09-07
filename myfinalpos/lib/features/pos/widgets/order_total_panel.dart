import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../pages/pos_home_page.dart';
import 'statutory_discount_dialog.dart';

class OrderTotalPanel extends StatelessWidget {
  const OrderTotalPanel({
    super.key,
    required this.pageState,
    this.compact = false,
  });

  final PosHomePageState pageState;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final currency = pageState.settings.currencySymbol;
    // Subtotal is shown gross (before per-item discounts) with the item
    // discounts broken out below it, matching the printed receipt - the net
    // subtotal on its own hid how much the cashier had discounted per item.
    // Grand Total is unaffected: gross minus the combined discount reduces
    // to the same net total as before.
    final subtotal = pageState.grossSubtotal;
    final itemDiscount = pageState.itemDiscountTotal;
    final discount = pageState.totalDiscount + itemDiscount;
    final vat = pageState.vatAmount;
    final total = pageState.grandTotal;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 10 : 16,
      ),
      decoration: const BoxDecoration(
        color: AppColors.lightGreen,
        border: Border(
          top: BorderSide(color: AppColors.caramel, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TotalRow(
            label: 'Subtotal',
            value: formatMoney(currency, subtotal),
            compact: compact,
          ),
          if (itemDiscount > 0)
            _TotalRow(
              label: 'Item Discounts',
              value: '-${formatMoney(currency, itemDiscount)}',
              valueColor: AppColors.danger,
              compact: compact,
            ),
          if (pageState.manualDiscount > 0)
            _TotalRow(
              label: 'Manual Discount',
              value: '-${formatMoney(currency, pageState.manualDiscount)}',
              valueColor: AppColors.danger,
              compact: compact,
            ),
          if (pageState.couponDiscount > 0)
            _TotalRow(
              label: 'Coupon (${pageState.appliedCouponCode})',
              value: '-${formatMoney(currency, pageState.couponDiscount)}',
              valueColor: AppColors.danger,
              compact: compact,
            ),
          if (pageState.hasStatutoryDiscount)
            _TotalRow(
              label:
                  '${statutoryDiscountLabel(pageState.statutoryDiscountType)} (20%)',
              value: '-${formatMoney(currency, pageState.statutoryDiscountAmount)}',
              valueColor: AppColors.danger,
              compact: compact,
            ),
          if (pageState.loyaltyDiscountAmount > 0)
            _TotalRow(
              label: 'Loyalty Redeemed',
              value:
                  '-${formatMoney(currency, pageState.loyaltyDiscountAmount)}',
              valueColor: AppColors.danger,
              compact: compact,
            ),
          if (discount > 0)
            _TotalRow(
              label: 'Total Discount',
              value: '-${formatMoney(currency, discount)}',
              valueColor: AppColors.danger,
              compact: compact,
            ),
          if (pageState.settings.taxRate > 0)
            _TotalRow(
              label:
                  'VAT (${(pageState.settings.taxRate * 100).toStringAsFixed(0)}%)',
              value: formatMoney(currency, vat),
              compact: compact,
            ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
            child: const Divider(height: 1, color: AppColors.greenBorder),
          ),
          _TotalRow(
            label: 'Grand Total',
            value: formatMoney(currency, total),
            emphasize: true,
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class SidebarTotalRow extends StatelessWidget {
  const SidebarTotalRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.compact = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool compact;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final labelSize = emphasize
        ? (compact ? 15.0 : 16.0)
        : (compact ? 13.0 : 14.0);
    // The grand total is the one number a cashier must read across the
    // counter, so it gets the largest, heaviest treatment in the panel.
    final valueSize = emphasize
        ? (compact ? 21.0 : 24.0)
        : (compact ? 13.0 : 14.0);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: labelSize,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
              letterSpacing: emphasize ? -0.2 : 0,
              color: emphasize ? AppColors.text : AppColors.muted,
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: valueSize,
                  fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
                  letterSpacing: emphasize ? -0.4 : 0,
                  color: valueColor ??
                      (emphasize ? AppColors.darkGreen : AppColors.text),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.compact = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool compact;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return SidebarTotalRow(
      label: label,
      value: value,
      emphasize: emphasize,
      compact: compact,
      valueColor: valueColor,
    );
  }
}
