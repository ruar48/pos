class PosPaymentMethods {
  const PosPaymentMethods._();

  /// Charge invoice is a credit sale: nothing lands in the drawer, the
  /// invoice number is what the store collects against later.
  static const chargeInvoice = 'Charge Invoice';

  static const all = [
    'Cash',
    'GCash',
    'Card',
    'Bank Transfer',
    'Cheque',
    chargeInvoice,
  ];

  static bool requiresReference(String method) => method != 'Cash';

  static String referenceLabel(String method) {
    if (method == 'Cheque') return 'Cheque Number';
    if (method == chargeInvoice) return 'Charge Invoice Number';
    return '$method Reference';
  }

  static String referenceHint(String method) {
    if (method == 'Cheque') return 'Enter cheque number';
    if (method == chargeInvoice) return 'Enter charge invoice number';
    return 'Transaction reference number';
  }
}
