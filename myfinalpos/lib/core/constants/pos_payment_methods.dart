class PosPaymentMethods {
  const PosPaymentMethods._();

  static const all = [
    'Cash',
    'GCash',
    'Card',
    'Bank Transfer',
    'Cheque',
  ];

  static bool requiresReference(String method) => method != 'Cash';

  static String referenceLabel(String method) {
    if (method == 'Cheque') return 'Cheque Number';
    return '$method Reference';
  }

  static String referenceHint(String method) {
    if (method == 'Cheque') return 'Enter cheque number';
    return 'Transaction reference number';
  }
}
