import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/product.dart';
import '../pages/pos_home_page.dart';

/// Shown when a tapped product name matches more than one catalog entry
/// (e.g. the same chemical listed separately per bottle size), so the
/// cashier can pick the exact size before it's added to the cart.
///
/// Returns the picked [Product], or null if the sheet was dismissed without
/// a selection - the caller is responsible for actually adding it to the
/// cart (see [PosHomePageState.promptAddProductGroupToCart]), since it's
/// still holding the in-flight tap guard for the duration of this sheet.
Future<Product?> showProductSizePicker(
  BuildContext context,
  PosHomePageState pageState,
  List<Product> group,
) {
  final currency = pageState.settings.currencySymbol;
  final allowNegative = pageState.settings.allowNegativeStock;
  final ids = group.map((product) => product.id).toList();
  final name = group.first.name;

  return showModalBottomSheet<Product?>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return ValueListenableBuilder<int>(
        valueListenable: pageState.catalogRevision,
        builder: (context, _, __) {
          final liveItems = ids
              .map((id) => pageState.productById(id))
              .whereType<Product>()
              .toList();
          final items = liveItems.isEmpty ? group : liveItems;

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Choose a size to add to the cart',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final stock = item.catalogStock;
                      final isOut =
                          !allowNegative && stock != null && stock <= 0;
                      final stockLabel = stock == null
                          ? ''
                          : isOut
                              ? 'Out of stock'
                              : '${formatQuantity(stock)} in stock';
                      final sizeLabel = item.displayOption ?? item.displayUnit;
                      final deal = item.catalogDeal?.trim();
                      final subtitleParts = <String>[];
                      if (stockLabel.isNotEmpty) {
                        subtitleParts.add(stockLabel);
                      }
                      if (deal != null && deal.isNotEmpty) {
                        subtitleParts.add(deal);
                      }
                      return Material(
                        color: AppColors.lightGreen.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          enabled: !isOut,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          title: Text(
                            sizeLabel.isEmpty ? item.name : sizeLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          subtitle: subtitleParts.isEmpty
                              ? null
                              : Text(
                                  subtitleParts.join(' • '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isOut
                                        ? AppColors.danger
                                        : AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                          trailing: Text(
                            formatMoney(currency, item.price),
                            style: const TextStyle(
                              color: AppColors.darkGreen,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          onTap: isOut
                              ? null
                              : () => Navigator.pop(sheetContext, item),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
