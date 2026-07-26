import 'customer.dart';
import 'loyalty_card.dart';

class NfcCustomerLookup {
  const NfcCustomerLookup({
    required this.customer,
    required this.loyaltyCard,
  });

  final Customer customer;
  final LoyaltyCard loyaltyCard;

  factory NfcCustomerLookup.fromJson(Map<String, dynamic> json) {
    return NfcCustomerLookup(
      customer: Customer.fromJson(
        Map<String, dynamic>.from(json['customer'] as Map),
      ),
      loyaltyCard: LoyaltyCard.fromJson(
        Map<String, dynamic>.from(json['loyalty_card'] as Map),
      ),
    );
  }
}

String normalizeNfcUid(String value) {
  final buffer = StringBuffer();
  for (final codeUnit in value.toUpperCase().codeUnits) {
    final char = String.fromCharCode(codeUnit);
    if ((codeUnit >= 48 && codeUnit <= 57) ||
        (codeUnit >= 65 && codeUnit <= 70)) {
      buffer.write(char);
    }
  }
  return buffer.toString();
}
