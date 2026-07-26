import '../core/utils/format_utils.dart';

class LoyaltyCard {
  const LoyaltyCard({
    required this.customerId,
    required this.customerName,
    required this.cardNumber,
    required this.points,
    required this.tier,
    required this.status,
    required this.createdAt,
    this.nfcUid,
  });

  final int customerId;
  final String customerName;
  final String cardNumber;
  final int points;
  final String tier;
  final String status;
  final DateTime createdAt;
  final String? nfcUid;

  factory LoyaltyCard.fromJson(Map<String, dynamic> json) {
    final rawNfc = (json['nfc_uid'] ?? '').toString().trim();

    return LoyaltyCard(
      customerId: toInt(json['customer_id']),
      customerName: (json['customer_name'] ?? '').toString(),
      cardNumber: (json['card_number'] ?? '').toString(),
      points: toInt(json['points']),
      tier: (json['tier'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      nfcUid: rawNfc.isEmpty ? null : rawNfc.toUpperCase(),
    );
  }

  LoyaltyCard copyWith({
    String? customerName,
    String? cardNumber,
    int? points,
    String? tier,
    String? status,
    DateTime? createdAt,
    String? nfcUid,
  }) {
    return LoyaltyCard(
      customerId: customerId,
      customerName: customerName ?? this.customerName,
      cardNumber: cardNumber ?? this.cardNumber,
      points: points ?? this.points,
      tier: tier ?? this.tier,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      nfcUid: nfcUid ?? this.nfcUid,
    );
  }
}
