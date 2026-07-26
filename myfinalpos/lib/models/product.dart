import '../core/utils/format_utils.dart';
import '../core/utils/product_units.dart';
import 'product_variety.dart';

class Product {
  static const int defaultReorderLevel = 5;

  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    required this.category,
    this.description,
    this.option,
    this.sku,
    this.barcode,
    this.unit,
    this.stock,
    this.reorderLevel = defaultReorderLevel,
    this.costPrice,
    this.deal,
    this.imageUrl,
    this.updatedAt,
    this.varieties = const [],
  });

  final int id;
  final int categoryId;
  final String name;
  final double price;
  final String category;
  final String? description;
  final String? option;
  final String? sku;
  final String? barcode;
  final String? unit;
  final int? stock;
  final int reorderLevel;
  final double? costPrice;
  final String? deal;
  final String? imageUrl;
  final DateTime? updatedAt;
  final List<ProductVariety> varieties;

  bool get hasVarieties => varieties.isNotEmpty;

  int get effectiveReorderLevel =>
      reorderLevel > 0 ? reorderLevel : defaultReorderLevel;

  double? get margin =>
      costPrice == null ? null : price - costPrice!;

  double? get marginPercent {
    if (costPrice == null || costPrice! <= 0) return null;
    return ((price - costPrice!) / costPrice!) * 100;
  }

  List<String> get unitList => parseProductUnits(unit);

  String get displayUnit => displayProductUnits(unit);

  String get primaryUnit => primaryProductUnit(unit);

  String? get displayDeal {
    final trimmed = deal?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String? get displayOption {
    final trimmed = option?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  /// Stock shown on POS product cards (sums variety stock when applicable).
  int? get catalogStock {
    if (!hasVarieties) {
      return stock;
    }

    final varietyStocks = varieties
        .map((variety) => variety.stock)
        .whereType<int>()
        .toList();
    if (varietyStocks.isEmpty) {
      return stock;
    }

    return varietyStocks.fold<int>(0, (total, value) => total + value);
  }

  /// Promo/deal line for POS cards (first available deal on variety products).
  String? get catalogDeal {
    if (!hasVarieties) {
      return displayDeal;
    }

    for (final variety in varieties) {
      final trimmed = variety.deal?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return null;
  }

  String get catalogMetaLabel {
    if (hasVarieties) {
      return '${varieties.length} types';
    }

    final unitLabel = displayUnit.trim();
    return unitLabel.isEmpty ? 'pc' : unitLabel;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: toInt(json['id']),
      categoryId: toInt(json['category_id']),
      name: (json['name'] ?? '').toString(),
      price: toDouble(json['price']),
      category: (json['category_name'] ?? '').toString(),
      description: json['description']?.toString(),
      option: json['option']?.toString(),
      sku: json['sku']?.toString(),
      barcode: json['barcode']?.toString(),
      unit: json['unit']?.toString(),
      stock: json['stock'] == null ? null : toInt(json['stock']),
      reorderLevel: json['reorder_level'] == null
          ? defaultReorderLevel
          : toInt(json['reorder_level']),
      costPrice: json['cost_price'] == null
          ? null
          : toDouble(json['cost_price']),
      deal: json['deal']?.toString(),
      imageUrl: json['image_url']?.toString(),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'].toString()),
      varieties: json['varieties'] is List
          ? (json['varieties'] as List)
              .whereType<Map>()
              .map((v) =>
                  ProductVariety.fromJson(Map<String, dynamic>.from(v)))
              .toList()
          : const [],
    );
  }
}

class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    this.icon,
  });

  final int id;
  final String name;
  final String? icon;

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    return ProductCategory(
      id: toInt(json['id']),
      name: (json['name'] ?? '').toString(),
      icon: json['icon']?.toString(),
    );
  }
}