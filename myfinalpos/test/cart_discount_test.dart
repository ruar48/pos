import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/models/cart_item.dart';
import 'package:myfinalpos/models/product.dart';
import 'package:myfinalpos/models/product_variety.dart';

Product _product({double price = 100}) => Product(
      id: 1,
      categoryId: 1,
      name: 'Item1',
      price: price,
      category: 'General',
      stock: 50,
    );

/// Mirrors the order maths in PosHomePageState (subtotal -> order discount ->
/// VAT -> grand total) so a cart can be checked the way the terminal totals it.
class _Order {
  _Order(this.cart, {this.manualDiscount = 0, this.taxRate = 0.12});

  final List<CartItem> cart;
  final double manualDiscount;
  final double taxRate;

  double get subtotal => cart.fold(0, (sum, item) => sum + item.total);
  double get totalDiscount => manualDiscount.clamp(0, subtotal).toDouble();
  double get netSubtotal => (subtotal - totalDiscount).clamp(0, subtotal);
  double get vatAmount => netSubtotal * taxRate;
  double get grandTotal => netSubtotal + vatAmount;
}

void main() {
  group('per-piece item discount follows the quantity', () {
    test('the reported case: P10 off, then press +', () {
      final item = CartItem(product: _product(), discountPerUnit: 10);

      expect(item.quantity, 1);
      expect(item.discount, 10);
      expect(item.total, 90);

      item.quantity += 1; // the plus button

      expect(item.discount, 20, reason: 'discount scales with qty');
      expect(item.total, 180);
    });

    test('pressing minus scales the discount back down', () {
      final item = CartItem(
        product: _product(),
        quantity: 3,
        discountPerUnit: 10,
      );
      expect(item.discount, 30);

      item.quantity -= 2;

      expect(item.discount, 10);
      expect(item.total, 90);
    });

    test('discount is capped so a line can never go negative', () {
      final item = CartItem(
        product: _product(),
        quantity: 2,
        discountPerUnit: 250, // more than the unit price
      );

      expect(item.discount, item.grossTotal);
      expect(item.total, 0);
      expect(item.total, greaterThanOrEqualTo(0));
    });

    test('decimal quantities still total correctly', () {
      final item = CartItem(
        product: _product(price: 80),
        quantity: 2.5,
        discountPerUnit: 4,
      );

      expect(item.discount, 10);
      expect(item.total, 190);
    });

    test('a variety line discounts against the variety price', () {
      final item = CartItem(
        product: _product(price: 100),
        variety: const ProductVariety(
          id: 9,
          productId: 1,
          name: '1000 ML',
          price: 60,
          stock: 10,
        ),
        quantity: 3,
        discountPerUnit: 5,
      );

      expect(item.unitPrice, 60);
      expect(item.grossTotal, 180);
      expect(item.discount, 15);
      expect(item.total, 165);
    });

    test('zero discount leaves the line untouched', () {
      final item = CartItem(product: _product(), quantity: 4);
      expect(item.discount, 0);
      expect(item.total, item.grossTotal);
    });
  });

  group('checkout payload', () {
    test('sends the line total in discount and adds discount_per_unit', () {
      final item = CartItem(
        product: _product(),
        quantity: 2,
        discountPerUnit: 10,
      );

      final json = item.toJson();

      expect(json['quantity'], 2);
      expect(json['price'], 100);
      expect(json['discount'], 20, reason: 'backend contract is unchanged');
      expect(json['discount_per_unit'], 10);
      expect(json['total'], 180);
      expect(json['product_id'], 1);
    });

    test('discount stays the line total when the quantity changes', () {
      final item = CartItem(product: _product(), discountPerUnit: 10);
      expect(item.toJson()['discount'], 10);

      item.quantity = 5;

      expect(item.toJson()['discount'], 50);
      expect(item.toJson()['total'], 450);
    });
  });

  group('order totals end to end', () {
    test('per-item and order-level discounts stack without conflict', () {
      final itemA = CartItem(
        product: _product(price: 100),
        quantity: 2,
        discountPerUnit: 10, // -20
      );
      final itemB = CartItem(
        product: Product(
          id: 2,
          categoryId: 1,
          name: 'Item2',
          price: 50,
          category: 'General',
          stock: 20,
        ),
        quantity: 3, // no item discount
      );

      final order = _Order([itemA, itemB], manualDiscount: 30);

      expect(itemA.total, 180);
      expect(itemB.total, 150);
      expect(order.subtotal, 330);
      expect(order.totalDiscount, 30, reason: 'discount on the whole total');
      expect(order.netSubtotal, 300);
      expect(closeTo(36, 0.001).matches(order.vatAmount, {}), isTrue);
      expect(order.grandTotal, closeTo(336, 0.001));
    });

    test('raising qty after an order discount recomputes the grand total', () {
      final item = CartItem(
        product: _product(price: 100),
        discountPerUnit: 10,
      );
      final order = _Order([item], manualDiscount: 0, taxRate: 0);

      expect(order.grandTotal, 90);

      item.quantity = 4;

      expect(item.discount, 40);
      expect(order.grandTotal, 360);
    });

    test('an order discount larger than the cart cannot go negative', () {
      final item = CartItem(product: _product(price: 100));
      final order = _Order([item], manualDiscount: 999, taxRate: 0);

      expect(order.netSubtotal, 0);
      expect(order.grandTotal, 0);
    });
  });
}
