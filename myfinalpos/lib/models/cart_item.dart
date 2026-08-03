import 'product.dart';
import 'product_variety.dart';

class CartItem {
  CartItem({required this.product, this.variety, this.quantity = 1});

  final Product product;
  final ProductVariety? variety;
  int quantity;

  double get unitPrice => variety?.price ?? product.price;

  /// Unit shown alongside the quantity on printed receipts. A variety's unit
  /// takes precedence over the product's default unit.
  String get receiptUnit {
    final varietyUnit = variety?.unit?.trim() ?? '';
    return varietyUnit.isNotEmpty ? varietyUnit : product.primaryUnit;
  }

  int? get availableStock => variety?.stock ?? product.stock;

  String get displayName {
    if (variety != null) return '${product.name} - ${variety!.name}';
    // Products without a separate variety row can still carry a flat
    // "option" (e.g. "1000 ML", "50 KILO") set directly on the product.
    final option = product.displayOption;
    return option == null ? product.name : '${product.name} - $option';
  }

  double get total => unitPrice * quantity;

  /// Identity key used to deduplicate cart lines. Lines with the same product
  /// but different varieties are tracked separately.
  String get lineKey =>
      variety == null ? 'p${product.id}' : 'p${product.id}-v${variety!.id}';

  Map<String, dynamic> toJson() => {
        'product_id': product.id,
        if (variety != null) 'variety_id': variety!.id,
        if (variety != null) 'variety_name': variety!.name,
        'quantity': quantity,
        'price': unitPrice,
        'total': total,
      };
}
