import '../core/utils/format_utils.dart';

class ProductVariety {
  static const int defaultReorderLevel = 5;

  const ProductVariety({
    required this.id,
    required this.productId,
    required this.name,
    required this.price,
    this.unit,
    this.sku,
    this.barcode,
    this.costPrice,
    this.deal,
    this.stock,
    this.reorderLevel = defaultReorderLevel,
    this.imageUrl,
  });

  final int id;
  final int productId;
  final String name;
  final double price;
  final String? unit;
  final String? sku;
  final String? barcode;
  final double? costPrice;
  final String? deal;
  final int? stock;
  final int reorderLevel;
  final String? imageUrl;

  int get effectiveReorderLevel =>
      reorderLevel > 0 ? reorderLevel : defaultReorderLevel;

  factory ProductVariety.fromJson(Map<String, dynamic> json) {
    return ProductVariety(
      id: toInt(json['id']),
      productId: toInt(json['product_id']),
      name: (json['name'] ?? '').toString(),
      price: toDouble(json['price']),
      unit: json['unit']?.toString(),
      sku: json['sku']?.toString(),
      barcode: json['barcode']?.toString(),
      costPrice: json['cost_price'] == null
          ? null
          : toDouble(json['cost_price']),
      deal: json['deal']?.toString(),
      stock: json['stock'] == null ? null : toInt(json['stock']),
      reorderLevel: json['reorder_level'] == null
          ? defaultReorderLevel
          : toInt(json['reorder_level']),
      imageUrl: json['image_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id > 0) 'id': id,
        'name': name,
        'price': price,
        if (unit != null && unit!.isNotEmpty) 'unit': unit,
        if (sku != null && sku!.isNotEmpty) 'sku': sku,
        if (barcode != null && barcode!.isNotEmpty) 'barcode': barcode,
        'cost_price': costPrice,
        if (deal != null && deal!.isNotEmpty) 'deal': deal,
        'stock': stock ?? 0,
        'reorder_level': reorderLevel,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
      };
}
