import '../core/utils/format_utils.dart';

class Customer {
  const Customer({
    required this.id,
    required this.customerName,
    required this.tableName,
    required this.orderType,
    this.createdAt,
  });

  final int id;
  final String customerName;
  final String tableName;
  final String orderType;
  final DateTime? createdAt;

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: toInt(json['id']),
      customerName: (json['customer_name'] ?? '').toString(),
      tableName: (json['table_name'] ?? '').toString(),
      orderType: (json['order_type'] ?? 'Retail').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
    );
  }

  String get displayName {
    final name = customerName.trim();
    return name.isEmpty ? 'Walk In Farmer' : name;
  }

  static bool isWalkInName(String customerName) {
    final normalized = customerName.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return normalized == 'walk in farmer' ||
        normalized == 'walk in' ||
        normalized == 'walk-in farmer';
  }

  bool get isWalkIn => isWalkInName(customerName);
}
