class ReceiptPrintException implements Exception {
  ReceiptPrintException(this.message);

  final String message;

  @override
  String toString() => message;
}

const kCashDrawerKickBytes = <int>[0x1B, 0x70, 0x00, 0x19, 0xFA];
