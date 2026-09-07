import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/features/pos/pages/pos_home_page.dart';
import 'package:myfinalpos/models/product.dart';
import 'package:myfinalpos/models/product_variety.dart';

Product product({
  required int id,
  required String name,
  String? barcode,
  String? sku,
  List<ProductVariety> varieties = const [],
}) {
  return Product(
    id: id,
    categoryId: 1,
    name: name,
    price: 100,
    category: 'Coffee',
    barcode: barcode,
    sku: sku,
    varieties: varieties,
  );
}

ProductVariety variety({
  required int id,
  required int productId,
  required String name,
  String? barcode,
}) {
  return ProductVariety(
    id: id,
    productId: productId,
    name: name,
    price: 120,
    barcode: barcode,
  );
}

void main() {
  group('findBarcodeHit', () {
    final latte = product(id: 1, name: 'Latte', barcode: '4800101');
    final beans = product(
      id: 2,
      name: 'House Blend Beans',
      barcode: '4800202',
      varieties: [
        variety(id: 10, productId: 2, name: '250g', barcode: '4800202-250'),
        variety(id: 11, productId: 2, name: '1kg', barcode: '4800202-1K'),
      ],
    );
    final catalog = [latte, beans];

    test('matches a product barcode exactly', () {
      final hit = findBarcodeHit(catalog, '4800101');
      expect(hit?.product.id, latte.id);
      expect(hit?.variety, isNull);
    });

    test('prefers a variety barcode so the picker can be skipped', () {
      final hit = findBarcodeHit(catalog, '4800202-1K');
      expect(hit?.product.id, beans.id);
      expect(hit?.variety?.id, 11);
    });

    test('falls back to the parent when only the parent code matches', () {
      final hit = findBarcodeHit(catalog, '4800202');
      expect(hit?.product.id, beans.id);
      expect(hit?.variety, isNull);
    });

    test('ignores surrounding whitespace and case from the scanner', () {
      final hit = findBarcodeHit(catalog, '  4800202-1k  ');
      expect(hit?.variety?.id, 11);
    });

    test('is exact, so a partial code is not a hit', () {
      expect(findBarcodeHit(catalog, '48001'), isNull);
    });

    test('returns null for an unknown code', () {
      expect(findBarcodeHit(catalog, '9999999'), isNull);
    });

    test('returns null for empty or whitespace-only input', () {
      expect(findBarcodeHit(catalog, ''), isNull);
      expect(findBarcodeHit(catalog, '   '), isNull);
    });

    test('never matches products that have no barcode', () {
      final unbarcoded = [product(id: 3, name: 'Daily Special')];
      expect(findBarcodeHit(unbarcoded, ''), isNull);
      // A blank stored code must not be treated as matching a blank scan.
      final blank = [product(id: 4, name: 'Blank code', barcode: '   ')];
      expect(findBarcodeHit(blank, '   '), isNull);
    });
  });

  group('barcodeContains', () {
    test('matches partial codes for type-ahead search', () {
      expect(barcodeContains('4800202-250', '0202'), isTrue);
    });

    test('is case-insensitive', () {
      expect(barcodeContains('ABC-123', 'abc'), isTrue);
    });

    test('ignores null and blank stored codes', () {
      expect(barcodeContains(null, '480'), isFalse);
      expect(barcodeContains('', '480'), isFalse);
      expect(barcodeContains('   ', '480'), isFalse);
    });
  });
}
