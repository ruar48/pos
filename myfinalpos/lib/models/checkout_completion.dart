class CheckoutCompletion {
  const CheckoutCompletion({
    required this.orderId,
    required this.invoiceNumber,
    this.isOfflinePending = false,
  });

  final int orderId;
  final String invoiceNumber;
  final bool isOfflinePending;
}
