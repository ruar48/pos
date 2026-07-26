class OrderPayment {
  const OrderPayment({
    required this.paymentMethod,
    required this.amount,
    this.reference = '',
  });

  final String paymentMethod;
  final double amount;
  final String reference;

  Map<String, dynamic> toJson() => {
        'payment_method': paymentMethod,
        'amount': amount,
        if (reference.trim().isNotEmpty) 'reference': reference.trim(),
      };

  factory OrderPayment.fromJson(Map<String, dynamic> json) => OrderPayment(
        paymentMethod: json['payment_method']?.toString() ?? 'Cash',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        reference: json['reference']?.toString() ?? '',
      );
}
