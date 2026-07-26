import 'product.dart';
import 'product_variety.dart';

class CartItem {
  CartItem({required this.product, this.variety, this.quantity = 1});

  final Product product;
  final ProductVariety? variety;
  int quantity;

  double get unitPrice => variety?.price ?? product.price;

  int? get availableStock => variety?.stock ?? product.stock;

  String get displayName =>
      variety == null ? product.name : '${product.name} - ${variety!.name}';

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
