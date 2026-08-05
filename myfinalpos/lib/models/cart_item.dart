import 'product.dart';
import 'product_variety.dart';

class CartItem {
  CartItem({
    required this.product,
    this.variety,
    this.quantity = 1,
    this.discount = 0,
  });

  final Product product;
  final ProductVariety? variety;
  double quantity;

  /// Fixed peso amount knocked off this line, entered per item.
  double discount;

  double get unitPrice => variety?.price ?? product.price;

  double? get availableStock => variety?.stock ?? product.stock;

  String get displayName {
    if (variety != null) return '${product.name} - ${variety!.name}';
    // Products without a separate variety row can still carry a flat
    // "option" (e.g. "1000 ML", "50 KILO") set directly on the product.
    final option = product.displayOption;
    return option == null ? product.name : '${product.name} - $option';
  }

  /// Line total before any per-item discount.
  double get grossTotal => unitPrice * quantity;

  double get total => (grossTotal - discount).clamp(0, grossTotal).toDouble();

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
        'discount': discount,
        'total': total,
      };
}
