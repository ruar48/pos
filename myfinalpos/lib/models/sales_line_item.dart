import '../core/utils/format_utils.dart';

class SalesLineItem {
  const SalesLineItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.total,
    this.varietyId,
    this.varietyName,
  });

  final int productId;
  final String productName;
  final int quantity;
  final double price;
  final double total;
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
    return SalesLineItem(
      productId: toInt(json['product_id']),
      productName: (json['product_name'] ?? '').toString(),
      quantity: toInt(json['quantity']),
      price: toDouble(json['price']),
      total: toDouble(json['total']),
      varietyId: varietyId != null && varietyId > 0 ? varietyId : null,
      varietyName: varietyName == null || varietyName.isEmpty
          ? null
          : varietyName,
    );
  }
}
