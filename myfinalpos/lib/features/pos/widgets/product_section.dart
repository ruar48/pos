import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/product.dart';
import '../pages/pos_home_page.dart';

export '../../../core/utils/category_icons.dart' show categoryIcon;

class ProductSection extends StatelessWidget {
  const ProductSection({
    super.key,
    required this.pageState,
    this.showMenuButton = false,
  });

  final PosHomePageState pageState;
  final bool showMenuButton;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: pageState.catalogRevision,
      builder: (context, _, __) {
        final categories = [
          'All',
          ...pageState.categories.map((item) => item.name),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  if (showMenuButton)
                    IconButton(
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu),
                      tooltip: 'Menu',
                    ),
                  Expanded(
                    child: TextField(
                      controller: pageState.searchController,
                      onChanged: (_) => pageState.refreshView(),
                      decoration: InputDecoration(
                        hintText: 'Search products...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: pageState.searchController.text.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  pageState.searchController.clear();
                                  pageState.refreshView();
                                },
                                icon: const Icon(Icons.close),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CatalogSyncButton(pageState: pageState),
                  const SizedBox(width: 12),
                  _OrderTypeToggle(pageState: pageState),
                  if (pageState.heldTransactions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _HoldScrollButton(pageState: pageState),
                  ],
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final selected = pageState.selectedCategory == category;
                  ProductCategory? categoryMeta;
                  if (category != 'All') {
                    for (final item in pageState.categories) {
                      if (item.name == category) {
                        categoryMeta = item;
                        break;
                      }
                    }
                  }
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (category != 'All') ...[
                          Icon(
                            resolveCategoryIcon(
                              iconKey: categoryMeta?.icon,
                              categoryName: category,
                            ),
                            size: 16,
                            color: selected ? Colors.white : AppColors.green,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(category),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) => pageState.selectCategory(category),
                    selectedColor: AppColors.green,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ),
            if (pageState.isPaymentMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Material(
                  color: AppColors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.shopping_cart_outlined,
                          color: AppColors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Payment in progress — tap any product to return to cart.',
                            style: TextStyle(
                              color: AppColors.text.withValues(alpha: 0.85),
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (pageState.loadError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Material(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            pageState.loadError!,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: pageState.isLoadingProducts
                  ? const Center(child: CircularProgressIndicator())
                  : ProductGrid(
                      products: pageState.filteredProducts,
                      currencySymbol: pageState.settings.currencySymbol,
                      onTap: (product) =>
                          pageState.promptAddProductToCart(context, product),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CatalogSyncButton extends StatelessWidget {
  const _CatalogSyncButton({required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    final syncing = pageState.isSyncingCatalog;
    return IconButton(
      onPressed:
          syncing ? null : () => pageState.syncProductCatalog(context),
      tooltip: 'Sync products from owner updates',
      icon: syncing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
    );
  }
}

class _OrderTypeToggle extends StatelessWidget {
  const _OrderTypeToggle({required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'Retail', label: Text('Retail')),
        ButtonSegment(value: 'Wholesale', label: Text('Wholesale')),
      ],
      selected: {pageState.orderType},
      onSelectionChanged: (value) => pageState.setOrderType(value.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _HoldScrollButton extends StatelessWidget {
  const _HoldScrollButton({required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return Badge(
      label: Text('${pageState.heldTransactions.length}'),
      child: FilledButton.tonalIcon(
        onPressed: () => _showHeldTransactionsDialog(context),
        icon: const Icon(Icons.pause_circle_outline),
        label: const Text('Held'),
      ),
    );
  }

  void _showHeldTransactionsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Held Transactions'),
        content: SizedBox(
          width: 420,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: pageState.heldTransactions.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final hold = pageState.heldTransactions[index];
              return ListTile(
                title: Text(hold.label),
                subtitle: Text(
                  '${hold.items.length} items • ${hold.orderType}',
                ),
                trailing: FilledButton(
                  onPressed: () {
                    pageState.resumeHeldTransaction(hold);
                    Navigator.pop(context);
                  },
                  child: const Text('Resume'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.products,
    required this.currencySymbol,
    required this.onTap,
  });

  final List<Product> products;
  final String currencySymbol;
  final void Function(Product product) onTap;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No products in the catalog.\nAdd products in Products & Inventory.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.4),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 900
            ? 4
            : width >= 620
                ? 3
                : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(22),
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 1.48,
          ),
          itemBuilder: (context, index) {
            final product = products[index];
            return ProductCard(
              key: ValueKey('pos-product-${product.id}'),
              product: product,
              currencySymbol: currencySymbol,
              onTap: () => onTap(product),
            );
          },
        );
      },
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.currencySymbol,
    required this.onTap,
  });

  final Product product;
  final String currencySymbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deal = product.catalogDeal;
    final option = product.displayOption;
    final stock = product.catalogStock;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _ProductCategoryChip(label: product.category),
                        ),
                      ),
                      if (stock != null) ...[
                        const SizedBox(width: 6),
                        _ProductStockBadge(
                          stock: stock,
                          reorderLevel: product.effectiveReorderLevel,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              if (option != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  option,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (deal != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.amber.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            deal,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.amber.withValues(alpha: 0.98),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (product.hasVarieties)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 2),
                              child: Text(
                                'FROM',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  height: 1,
                                ),
                              ),
                            ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatMoney(currencySymbol, product.price),
                              maxLines: 1,
                              style: const TextStyle(
                                color: AppColors.darkGreen,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (product.hasVarieties) ...[
                      const SizedBox(width: 6),
                      _ProductMetaChip(label: product.catalogMetaLabel),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCategoryChip extends StatelessWidget {
  const _ProductCategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.lightGreen.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.greenBorder),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.green,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _ProductStockBadge extends StatelessWidget {
  const _ProductStockBadge({
    required this.stock,
    required this.reorderLevel,
  });

  final int stock;
  final int reorderLevel;

  @override
  Widget build(BuildContext context) {
    final isOut = stock <= 0;
    final isLow = !isOut && stock <= reorderLevel;
    final color = isOut
        ? AppColors.danger
        : isLow
            ? AppColors.orange
            : AppColors.green;
    final label = isOut
        ? (stock < 0 ? '$stock in stock' : 'Out of stock')
        : isLow
            ? '$stock left'
            : '$stock in stock';

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _ProductMetaChip extends StatelessWidget {
  const _ProductMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      constraints: const BoxConstraints(minWidth: 42),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.lightGreen.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.greenBorder),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.green,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class ProductCategoryIconFallback extends StatelessWidget {
  const ProductCategoryIconFallback({
    super.key,
    required this.category,
    this.iconKey,
    this.size = 36,
  });

  final String category;
  final String? iconKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        resolveCategoryIcon(iconKey: iconKey, categoryName: category),
        size: size,
        color: AppColors.green,
      ),
    );
  }
}
