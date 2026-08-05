import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/product.dart';
import '../../../models/product_variety.dart';
import '../pages/pos_home_page.dart';

Future<void> showProductVarietyPicker(
  BuildContext context,
  PosHomePageState pageState,
  Product product,
) {
  final currency = pageState.settings.currencySymbol;
  final allowNegative = pageState.settings.allowNegativeStock;
  final productId = product.id;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return ValueListenableBuilder<int>(
        valueListenable: pageState.catalogRevision,
        builder: (context, _, __) {
          final liveProduct = pageState.productById(productId) ?? product;
          final varieties = liveProduct.varieties;

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Text(
                    liveProduct.name,
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
                    'Choose a variety to add to the cart',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: varieties.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final variety = varieties[index];
                      final stock = variety.stock;
                      final isOut =
                          !allowNegative && stock != null && stock <= 0;
                      final stockLabel = stock == null
                          ? ''
                          : isOut
                              ? 'Out of stock'
                              : '${formatQuantity(stock)} in stock';
                      final deal = variety.deal?.trim();
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
                            variety.name,
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
                            formatMoney(currency, variety.price),
                            style: const TextStyle(
                              color: AppColors.darkGreen,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          onTap: isOut
                              ? null
                              : () {
                                  Navigator.pop(sheetContext);
                                  final current =
                                      pageState.productById(productId) ??
                                          liveProduct;
                                  ProductVariety? liveVariety;
                                  for (final v in current.varieties) {
                                    if (v.id == variety.id) {
                                      liveVariety = v;
                                      break;
                                    }
                                  }
                                  pageState.addToCart(
                                    current,
                                    variety: liveVariety ?? variety,
                                  );
                                },
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
