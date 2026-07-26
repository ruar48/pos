class BluetoothPrinterTestStep {
  const BluetoothPrinterTestStep({
    required this.label,
    required this.passed,
    required this.message,
  });

  final String label;
  final bool passed;
  final String message;
}

class BluetoothPrinterTestResult {
  const BluetoothPrinterTestResult({
    required this.passed,
    required this.steps,
    required this.summary,
  });

  final bool passed;
  final List<BluetoothPrinterTestStep> steps;
  final String summary;
}
