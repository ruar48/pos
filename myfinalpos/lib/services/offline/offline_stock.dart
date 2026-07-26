import '../../models/cart_item.dart';
import '../../models/product.dart';
import '../../models/product_variety.dart';

List<Product> applyLocalStockDeduction(
  List<Product> source,
  List<CartItem> items,
) {
  if (items.isEmpty) return source;

  final updated = {for (final product in source) product.id: product};

  for (final item in items) {
    final product = updated[item.product.id];
    if (product == null) continue;

    if (item.variety != null) {
      final varieties = product.varieties.map((variety) {
        if (variety.id != item.variety!.id) return variety;
        final stock = variety.stock;
        if (stock == null) return variety;
        return ProductVariety(
          id: variety.id,
          productId: variety.productId,
          name: variety.name,
          price: variety.price,
          unit: variety.unit,
          sku: variety.sku,
          barcode: variety.barcode,
          costPrice: variety.costPrice,
          deal: variety.deal,
          stock: (stock - item.quantity).clamp(0, 999999),
          reorderLevel: variety.reorderLevel,
          imageUrl: variety.imageUrl,
        );
      }).toList();

      updated[product.id] = Product(
        id: product.id,
        categoryId: product.categoryId,
        name: product.name,
        price: product.price,
        category: product.category,
        description: product.description,
        option: product.option,
        sku: product.sku,
        barcode: product.barcode,
        unit: product.unit,
        stock: product.stock,
        reorderLevel: product.reorderLevel,
        costPrice: product.costPrice,
        deal: product.deal,
        imageUrl: product.imageUrl,
        updatedAt: product.updatedAt,
        varieties: varieties,
      );
      continue;
    }

    final stock = product.stock;
    if (stock == null) continue;

    updated[product.id] = Product(
      id: product.id,
      categoryId: product.categoryId,
      name: product.name,
      price: product.price,
      category: product.category,
      description: product.description,
      option: product.option,
      sku: product.sku,
      barcode: product.barcode,
      unit: product.unit,
      stock: (stock - item.quantity).clamp(0, 999999),
      reorderLevel: product.reorderLevel,
      costPrice: product.costPrice,
      deal: product.deal,
      imageUrl: product.imageUrl,
      updatedAt: product.updatedAt,
      varieties: product.varieties,
    );
  }

  return updated.values.toList();
}
