class PosPaymentMethods {
  const PosPaymentMethods._();

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

  static String referenceValidationMessage(String method) {
    if (method == 'Cheque') return 'Enter a cheque number to continue';
    if (method == chargeInvoice) {
      return 'Enter a charge invoice number to continue';
    }
    return 'Enter a $method reference to continue';
  }
}
