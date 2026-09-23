<?php

use App\Services\Pos\ProductImportExportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;

uses(RefreshDatabase::class);

/**
 * Reproduces the reported bug: staff exports items, a sale lowers live
 * stock, then staff edits the (now stale) exported file to add a new
 * delivery and re-imports it. The typed number was being written as an
 * absolute value, silently erasing the sale that happened in between.
 */
test('re-importing an edited export applies the edit as a delta, not an absolute overwrite', function () {
    $categoryId = DB::table('categories')->insertGetId(['name' => 'Feeds']);
    $productId = DB::table('products')->insertGetId([
        'category_id' => $categoryId,
        'name' => 'ACC Feeds 40kg',
        'price' => 1234.50,
        'cost_price' => 900,
        'stock' => 100,
        'reorder_level' => 5,
        'status' => 'active',
        'created_at' => now(),
        'updated_at' => now(),
    ]);

    // Staff exports the file here: stock = 100, stock_snapshot = 100.

    // A customer buys 20 units before the file is re-imported.
    DB::table('products')->where('id', $productId)->update(['stock' => 80]);

    // Staff, unaware of the sale, edits the stale exported file to add a
    // delivery of 50 on top of the 100 they saw at export time: 100 + 50 = 150.
    $csv = "id,category,item,option,barcode,price,cost_price,deal,stock,stock_snapshot,reorder_level\n"
        ."{$productId},Feeds,ACC Feeds 40kg,,,1234.50,900,,150,100,5\n";

    $result = app(ProductImportExportService::class)->importFromCsv($csv);

    expect($result['updated'])->toBe(1);
    expect($result['errors'])->toBe([]);

    $stock = DB::table('products')->where('id', $productId)->value('stock');

    // Correct: live stock (80, reflecting the sale) plus the intended
    // delivery delta (+50) = 130. The old behavior wrote the typed 150
    // verbatim, silently undoing the sale.
    expect((float) $stock)->toBe(130.0);

    // The drift is still surfaced so staff can review it.
    expect($result['warnings'])->toHaveCount(1);
    expect($result['warnings'][0])->toContain('ACC Feeds 40kg');
});

test('re-importing an untouched stock cell leaves live stock alone', function () {
    $categoryId = DB::table('categories')->insertGetId(['name' => 'Feeds']);
    $productId = DB::table('products')->insertGetId([
        'category_id' => $categoryId,
        'name' => 'ACC Rice 25kg',
        'price' => 250,
        'cost_price' => 200,
        'stock' => 100,
        'reorder_level' => 5,
        'status' => 'active',
        'created_at' => now(),
        'updated_at' => now(),
    ]);

    DB::table('products')->where('id', $productId)->update(['stock' => 80]);

    // Staff only edits the price column; the stock cell is left as it was
    // in the exported file (100), matching the snapshot.
    $csv = "id,category,item,option,barcode,price,cost_price,deal,stock,stock_snapshot,reorder_level\n"
        ."{$productId},Feeds,ACC Rice 25kg,,,275,200,,100,100,5\n";

    $result = app(ProductImportExportService::class)->importFromCsv($csv);

    expect($result['updated'])->toBe(1);
    expect((float) DB::table('products')->where('id', $productId)->value('stock'))->toBe(80.0);
    expect($result['warnings'])->toBe([]);
});

/**
 * 'recount' mode is the opposite of the default delta mode: it's for a full
 * physical stock count, where the typed number IS the true stock (not a
 * change to apply on top of live stock). A blank cell means "not recounted"
 * and must not zero out that item.
 */
test('recount mode writes the counted number as-is and skips blank cells', function () {
    $categoryId = DB::table('categories')->insertGetId(['name' => 'Feeds']);
    $counted = DB::table('products')->insertGetId([
        'category_id' => $categoryId,
        'name' => 'Counted Item',
        'price' => 100,
        'cost_price' => 80,
        'stock' => 999,
        'reorder_level' => 5,
        'status' => 'active',
        'created_at' => now(),
        'updated_at' => now(),
    ]);
    $uncounted = DB::table('products')->insertGetId([
        'category_id' => $categoryId,
        'name' => 'Uncounted Item',
        'price' => 50,
        'cost_price' => 40,
        'stock' => 999,
        'reorder_level' => 5,
        'status' => 'active',
        'created_at' => now(),
        'updated_at' => now(),
    ]);

    $csv = "id,category,item,option,barcode,price,cost_price,deal,stock,reorder_level\n"
        ."{$counted},Feeds,Counted Item,,,100,80,,42,5\n"
        ."{$uncounted},Feeds,Uncounted Item,,,50,40,,,5\n";

    $result = app(ProductImportExportService::class)->importFromCsv($csv, null, 'recount');

    expect($result['updated'])->toBe(2);
    expect($result['errors'])->toBe([]);
    expect((float) DB::table('products')->where('id', $counted)->value('stock'))->toBe(42.0);
    expect((float) DB::table('products')->where('id', $uncounted)->value('stock'))->toBe(999.0);
});
