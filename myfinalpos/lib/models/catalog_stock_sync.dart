class CatalogStockSyncResult {
  const CatalogStockSyncResult({
    required this.revision,
    required this.unchanged,
    this.products = const {},
    this.varieties = const {},
  });

  final String revision;
  final bool unchanged;
  final Map<String, int> products;
  final Map<String, int> varieties;

  factory CatalogStockSyncResult.fromJson(Map<String, dynamic> json) {
    final rawProducts = json['products'];
    final rawVarieties = json['varieties'];
    final products = <String, int>{};
    final varieties = <String, int>{};

    if (rawProducts is Map) {
      rawProducts.forEach((key, value) {
        products[key.toString()] = (value as num?)?.toInt() ?? 0;
      });
    }

    if (rawVarieties is Map) {
      rawVarieties.forEach((key, value) {
        varieties[key.toString()] = (value as num?)?.toInt() ?? 0;
      });
    }

    return CatalogStockSyncResult(
      revision: json['revision']?.toString() ?? '0',
      unchanged: json['unchanged'] == true,
      products: products,
      varieties: varieties,
    );
  }
}
