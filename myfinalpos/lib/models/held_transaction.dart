import 'cart_item.dart';
import 'customer.dart';

class HeldTransaction {
  const HeldTransaction({
    required this.id,
    required this.label,
    required this.customer,
    required this.orderType,
    required this.items,
    required this.discountAmount,
    required this.couponCode,
    required this.loyaltyPointsRedeemed,
    required this.createdAt,
  });

  final int id;
  final String label;
  final Customer? customer;
  final String orderType;
  final List<CartItem> items;
  final double discountAmount;
  final String couponCode;
  final int loyaltyPointsRedeemed;
  final DateTime createdAt;
}
