class ProductUnitOption {
  const ProductUnitOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

const List<ProductUnitOption> productUnitOptions = [
  ProductUnitOption(value: 'pc', label: 'Piece (pc)'),
  ProductUnitOption(value: 'kg', label: 'Kilo (kg)'),
  ProductUnitOption(value: 'g', label: 'Gram (g)'),
  ProductUnitOption(value: 'bag', label: 'Bag'),
  ProductUnitOption(value: 'sack', label: 'Sack'),
  ProductUnitOption(value: 'box', label: 'Box'),
  ProductUnitOption(value: 'bottle', label: 'Bottle'),
  ProductUnitOption(value: 'roll', label: 'Roll'),
  ProductUnitOption(value: 'tray', label: 'Tray'),
  ProductUnitOption(value: 'bundle', label: 'Bundle'),
  ProductUnitOption(value: 'liter', label: 'Liter (L)'),
  ProductUnitOption(value: 'ton', label: 'Ton'),
];

String normalizeProductUnit(String raw) {
  final value = raw.trim().toLowerCase();
  switch (value) {
    case 'pcs':
    case 'piece':
    case 'pieces':
      return 'pc';
    case 'kilo':
    case 'kilogram':
    case 'kilograms':
      return 'kg';
    case 'gram':
    case 'grams':
      return 'g';
    case 'l':
    case 'litre':
    case 'litres':
    case 'liter':
      return 'liter';
    default:
      return value;
  }
}

List<String> parseProductUnits(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const ['pc'];
  }

  final units = raw
      .split(',')
      .map(normalizeProductUnit)
      .where((unit) => unit.isNotEmpty)
      .toList();

  if (units.isEmpty) {
    return const ['pc'];
  }

  return units.toSet().toList();
}

String encodeProductUnits(Iterable<String> units) {
  final normalized = units
      .map(normalizeProductUnit)
      .where((unit) => unit.isNotEmpty)
      .toSet()
      .toList();

  if (normalized.isEmpty) {
    return 'pc';
  }

  normalized.sort();
  return normalized.join(',');
}

String displayProductUnits(String? raw) {
  return parseProductUnits(raw).join(', ');
}

String primaryProductUnit(String? raw) {
  return parseProductUnits(raw).first;
}

String productUnitLabel(String value) {
  final normalized = normalizeProductUnit(value);
  for (final option in productUnitOptions) {
    if (option.value == normalized) {
      return option.label;
    }
  }
  return normalized;
}

List<String> availableProductUnits(Iterable<String> selected) {
  final selectedSet = selected.map(normalizeProductUnit).toSet();
  return productUnitOptions
      .map((option) => option.value)
      .where((value) => !selectedSet.contains(value))
      .toList();
}
