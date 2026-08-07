import 'dart:math';

import '../core/utils/format_utils.dart';

class SalesLineItem {
  const SalesLineItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.total,
    this.discount = 0,
    this.varietyId,
    this.varietyName,
  });

  final int productId;
  final String productName;
  final double quantity;
  final double price;
  final double total;
  final double discount;
  final int? varietyId;
  final String? varietyName;

  String get displayName => (varietyName == null || varietyName!.isEmpty)
      ? productName
      : '$productName - $varietyName';

  factory SalesLineItem.fromJson(Map<String, dynamic> json) {
    final varietyId = json['variety_id'] == null
        ? null
        : toInt(json['variety_id']);
    final varietyName = json['variety_name']?.toString();
    final quantity = toDouble(json['quantity']);
    final price = toDouble(json['price']);
    final total = toDouble(json['total']);
    return SalesLineItem(
      productId: toInt(json['product_id']),
      productName: (json['product_name'] ?? '').toString(),
      quantity: quantity,
      price: price,
      total: total,
      discount: max(
        toDouble(json['discount_amount']),
        max(0.0, (price * quantity) - total),
      ),
      varietyId: varietyId != null && varietyId > 0 ? varietyId : null,
      varietyName: varietyName == null || varietyName.isEmpty
          ? null
          : varietyName,
    );
  }
}
