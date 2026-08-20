<?php

namespace App\Services\Pos;

use App\Support\CatalogStockRevision;
use App\Support\PosHelpers;
use App\Support\StockLedger;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use PhpOffice\PhpSpreadsheet\IOFactory;

class ProductImportExportService
{
    /** @var list<string> */
    public const EXPORT_HEADERS = [
        'id',
        'category',
        'item',
        'option',
        'barcode',
        'price',
        'cost_price',
        'deal',
        'stock',
        'reorder_level',
    ];

    /**
     * @return list<array<string, mixed>>
     */
    public function exportRows(): array
    {
        if (! Schema::hasTable('products')) {
            return [];
        }

        $hasDeal = Schema::hasColumn('products', 'deal');
        $hasOption = Schema::hasColumn('products', 'option');
        $hasBarcode = Schema::hasColumn('products', 'barcode');

        $dealSelect = $hasDeal ? 'p.deal,' : 'NULL AS deal,';
        $optionSelect = $hasOption ? 'p.option,' : 'NULL AS option,';
        $barcodeSelect = $hasBarcode ? 'p.barcode,' : 'NULL AS barcode,';

        $rows = DB::select(
            "SELECT p.id, c.name AS category, p.name AS item, {$optionSelect} {$barcodeSelect}
                    p.price, p.cost_price, {$dealSelect}
                    p.stock, p.reorder_level
             FROM products p
             INNER JOIN categories c ON c.id = p.category_id
             WHERE p.status = 'active'
             ORDER BY p.id ASC",
        );

        return array_map(static fn ($row) => (array) $row, $rows);
    }

    /**
     * @return array{created: int, updated: int, skipped: int, errors: list<string>}
     */
    public function importFromFile(string $filePath, string $extension, ?int $actorUserId = null): array
    {
        $rows = $this->readImportRows($filePath, strtolower($extension));

        return $this->importRows($rows, $actorUserId);
    }

    /**
     * @return array{created: int, updated: int, skipped: int, errors: list<string>, warnings: list<string>}
     */
    public function importFromCsv(string $csvContent, ?int $actorUserId = null): array
    {
        $tmp = tempnam(sys_get_temp_dir(), 'pos-import-');
        if ($tmp === false) {
            return [
                'created' => 0,
                'updated' => 0,
                'skipped' => 0,
                'errors' => ['Could not create temporary file'],
                'warnings' => [],
            ];
        }

        file_put_contents($tmp, $csvContent);

        try {
            return $this->importFromFile($tmp, 'csv', $actorUserId);
        } finally {
            @unlink($tmp);
        }
    }

    /**
     * @return list<array<string, string>>
     */
    private function readImportRows(string $filePath, string $extension): array
    {
        if (in_array($extension, ['xlsx', 'xls'], true)) {
            return $this->readExcelRows($filePath);
        }

        $content = file_get_contents($filePath);
        if ($content === false || trim($content) === '') {
            return [];
        }

        return $this->readCsvRows($content);
    }

    /**
     * @return list<array<string, string>>
     */
    private function readExcelRows(string $filePath): array
    {
        $reader = IOFactory::createReaderForFile($filePath);
        $reader->setReadDataOnly(true);
        $spreadsheet = $reader->load($filePath);
        $sheet = $spreadsheet->getActiveSheet();
        $matrix = $sheet->toArray(null, true, true, false);

        if ($matrix === []) {
            return [];
        }

        $headerRow = array_shift($matrix);
        if (! is_array($headerRow)) {
            return [];
        }

        $headerMap = $this->buildHeaderMap($headerRow);
        if (! $this->hasRequiredImportColumns($headerMap)) {
            return [];
        }

        $rows = [];
        foreach ($matrix as $cells) {
            if (! is_array($cells)) {
                continue;
            }

            $row = $this->rowFromCells($cells, $headerMap);
            if ($this->isImportRowEmpty($row)) {
                continue;
            }

            $rows[] = $row;
        }

        return $rows;
    }

    /**
     * @return list<array<string, string>>
     */
    private function readCsvRows(string $csvContent): array
    {
        $lines = preg_split('/\r\n|\r|\n/', trim($csvContent)) ?: [];
        if ($lines === []) {
            return [];
        }

        $headerLine = array_shift($lines);
        $headers = $this->parseCsvLine((string) $headerLine);
        $headerMap = $this->buildHeaderMap($headers);

        if (! $this->hasRequiredImportColumns($headerMap)) {
            return [];
        }

        $rows = [];
        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '') {
                continue;
            }

            $cells = $this->parseCsvLine($line);
            $row = $this->rowFromCells($cells, $headerMap);
            if ($this->isImportRowEmpty($row)) {
                continue;
            }

            $rows[] = $row;
        }

        return $rows;
    }

    /**
     * @param  list<string|null>  $headers
     * @return array<string, int>
     */
    private function buildHeaderMap(array $headers): array
    {
        $headerMap = [];
        foreach ($headers as $index => $header) {
            $key = $this->normalizeHeaderKey((string) ($header ?? ''));
            if ($key !== '') {
                $headerMap[$key] = (int) $index;
            }
        }

        return $headerMap;
    }

    private function normalizeHeaderKey(string $header): string
    {
        $key = strtolower(trim($header));
        $key = preg_replace('/\s+/', '_', $key) ?? $key;
        $key = preg_replace('/[^a-z0-9_]/', '', $key) ?? $key;

        return match ($key) {
            'item', 'product', 'product_name' => 'name',
            'cost' => 'cost_price',
            'morning_inventory', 'morninginventory', 'morning_in', 'morning_inv', 'morninginv' => 'stock',
            default => $key,
        };
    }

    /**
     * @param  array<string, int>  $headerMap
     */
    private function hasRequiredImportColumns(array $headerMap): bool
    {
        if (! array_key_exists('category', $headerMap)) {
            return false;
        }

        if (! array_key_exists('name', $headerMap)) {
            return false;
        }

        return array_key_exists('price', $headerMap);
    }

    /**
     * @param  array<string, string>  $row
     */
    private function isImportRowEmpty(array $row): bool
    {
        $category = trim((string) ($row['category'] ?? ''));
        $name = trim((string) ($row['name'] ?? ''));

        return $category === '' && $name === '';
    }

    /**
     * @param  list<array<string, string>>  $rows
     * @return array{created: int, updated: int, skipped: int, errors: list<string>, warnings: list<string>}
     */
    private function importRows(array $rows, ?int $actorUserId = null): array
    {
        if ($rows === []) {
            return [
                'created' => 0,
                'updated' => 0,
                'skipped' => 0,
                'errors' => ['File is empty or missing required columns (Category, Item, Price)'],
                'warnings' => [],
            ];
        }

        $created = 0;
        $updated = 0;
        $skipped = 0;
        $errors = [];
        $duplicateWarnings = [];
        $maxErrors = 50;
        $hasOption = Schema::hasColumn('products', 'option');
        $hasDeal = Schema::hasColumn('products', 'deal');
        $hasBarcode = Schema::hasColumn('products', 'barcode');

        /** @var array<string, int> $categoryIdByLower */
        $categoryIdByLower = [];
        foreach (DB::table('categories')->select('id', 'name')->get() as $category) {
            $categoryIdByLower[strtolower((string) $category->name)] = (int) $category->id;
        }

        /** @var array<string, object{id: int, stock: float}> $productIndex */
        $productIndex = $this->buildProductImportIndex($hasOption);

        /** @var array<int, object{id: int, stock: float}> $productIndexById */
        $productIndexById = [];
        foreach ($productIndex as $indexed) {
            $productIndexById[(int) $indexed->id] = $indexed;
        }

        /** @var array<string, list<int>> $productIdsByNameOption */
        $productIdsByNameOption = $this->buildProductNameOptionIndex($hasOption);

        DB::beginTransaction();

        try {
            $now = now();

            foreach ($rows as $lineNumber => $row) {
                $displayLine = $lineNumber + 2;

                $categoryName = $this->normalizeCategoryName((string) ($row['category'] ?? ''));
                $name = trim((string) ($row['name'] ?? ''));
                $option = trim((string) ($row['option'] ?? ''));
                $barcode = trim((string) ($row['barcode'] ?? ''));

                if ($categoryName === '' || $name === '') {
                    $skipped++;
                    if (count($errors) < $maxErrors) {
                        $errors[] = "Row {$displayLine}: category and item are required";
                    }

                    continue;
                }

                $price = $this->parseMoney($row['price'] ?? null, "Row {$displayLine}: invalid price");
                if ($price === null) {
                    $skipped++;
                    if (count($errors) < $maxErrors) {
                        $errors[] = "Row {$displayLine}: invalid price";
                    }

                    continue;
                }

                $costPrice = $this->parseOptionalMoney($row['cost_price'] ?? null);
                if ($costPrice === false) {
                    $skipped++;
                    if (count($errors) < $maxErrors) {
                        $errors[] = "Row {$displayLine}: invalid cost";
                    }

                    continue;
                }

                $stock = $this->parseQuantity($row['stock'] ?? 0, 0.0);
                $reorder = max(0, $this->parseInt($row['reorder_level'] ?? 5, 5));
                $description = trim((string) ($row['description'] ?? ''));
                $deal = trim((string) ($row['deal'] ?? ''));
                $status = trim((string) ($row['status'] ?? 'active'));
                if ($status === '') {
                    $status = 'active';
                }

                $categoryId = $this->resolveCategoryIdCached($categoryName, $categoryIdByLower);
                $matchKey = $this->productMatchKey($categoryId, $name, $option);
                $importId = (int) ($row['id'] ?? 0);
                $existing = null;

                if ($importId > 0 && isset($productIndexById[$importId])) {
                    $existing = $productIndexById[$importId];
                } else {
                    $existing = $productIndex[$matchKey] ?? null;

                    if ($existing === null) {
                        // Category text in the file didn't resolve to the same category_id
                        // as an existing product with this name+option. Don't guess whether
                        // this is the same item under a corrected category or a genuinely
                        // different new item that happens to share a name+option — that's
                        // ambiguous and merging could silently overwrite an unrelated
                        // product. Create it as a new row (safe default) and flag it so
                        // staff can review/merge manually if needed.
                        $nameOptionKey = strtolower($name).'|'.strtolower(trim($option));
                        $candidateIds = $productIdsByNameOption[$nameOptionKey] ?? [];
                        if ($candidateIds !== [] && count($duplicateWarnings) < $maxErrors) {
                            $duplicateWarnings[] = sprintf(
                                "Row {$displayLine}: '%s' (%s) matches existing product ID %s under a different category — created as a separate item; review for a possible duplicate.",
                                $name,
                                $option !== '' ? $option : 'no option',
                                implode(', ', $candidateIds),
                            );
                        }
                    }
                }

                $payload = [
                    'category_id' => $categoryId,
                    'name' => $name,
                    'description' => $description === '' ? null : $description,
                    'price' => $price,
                    'cost_price' => $costPrice,
                    'stock' => $stock,
                    'reorder_level' => $reorder,
                    'status' => $status,
                    'updated_at' => $now,
                ];

                if ($hasOption) {
                    $payload['option'] = $option === '' ? null : $option;
                }

                if ($hasDeal) {
                    $payload['deal'] = $deal === '' ? null : $deal;
                }

                if ($hasBarcode) {
                    $payload['barcode'] = $barcode === '' ? null : $barcode;
                }

                if ($existing !== null) {
                    $productId = (int) $existing->id;
                    $previousStock = (float) $existing->stock;

                    DB::table('products')->where('id', $productId)->update($payload);

                    $delta = round($stock - $previousStock, 3);
                    if ($delta !== 0.0) {
                        StockLedger::record(
                            productId: $productId,
                            varietyId: null,
                            type: 'adjustment',
                            quantityDelta: (float) $delta,
                            balanceAfter: (float) $stock,
                            referenceType: 'import',
                            referenceId: null,
                            note: 'Stock updated via bulk import',
                            userId: $actorUserId,
                        );
                    }

                    $indexed = (object) [
                        'id' => $productId,
                        'stock' => $stock,
                    ];
                    $productIndex[$matchKey] = $indexed;
                    $productIndexById[$productId] = $indexed;
                    $updated++;
                } else {
                    $payload['created_at'] = $now;
                    $productId = (int) DB::table('products')->insertGetId($payload);

                    if ($stock !== 0.0) {
                        StockLedger::record(
                            productId: $productId,
                            varietyId: null,
                            type: 'initial',
                            quantityDelta: $stock,
                            balanceAfter: $stock,
                            referenceType: 'import',
                            referenceId: null,
                            note: 'Initial stock via bulk import',
                            userId: $actorUserId,
                        );
                    }

                    $indexed = (object) [
                        'id' => $productId,
                        'stock' => $stock,
                    ];
                    $productIndex[$matchKey] = $indexed;
                    $productIndexById[$productId] = $indexed;
                    $created++;
                }
            }

            PosHelpers::insertAuditLog(
                $actorUserId,
                'import',
                'inventory',
                'product',
                null,
                'Bulk product import',
                [
                    'created' => $created,
                    'updated' => $updated,
                    'skipped' => $skipped,
                    'rows' => count($rows),
                    'possible_duplicates' => count($duplicateWarnings),
                ],
            );

            DB::commit();
            CatalogStockRevision::bump();
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        if (count($errors) >= $maxErrors) {
            $errors[] = 'Additional row errors were omitted.';
        }

        if (count($duplicateWarnings) >= $maxErrors) {
            $duplicateWarnings[] = 'Additional duplicate warnings were omitted.';
        }

        $warnings = $duplicateWarnings;

        return compact('created', 'updated', 'skipped', 'errors', 'warnings');
    }

    /**
     * @return array<string, object{id: int, stock: float}>
     */
    private function buildProductImportIndex(bool $hasOption): array
    {
        $columns = ['id', 'category_id', 'name', 'stock'];
        if ($hasOption) {
            $columns[] = 'option';
        }

        $index = [];
        foreach (DB::table('products')->select($columns)->get() as $product) {
            $option = $hasOption ? (string) ($product->option ?? '') : '';
            $key = $this->productMatchKey(
                (int) $product->category_id,
                (string) $product->name,
                $option,
            );
            $index[$key] = (object) [
                'id' => (int) $product->id,
                'stock' => (float) ($product->stock ?? 0),
            ];
        }

        return $index;
    }

    private function productMatchKey(int $categoryId, string $name, string $option): string
    {
        return $categoryId.'|'.strtolower($name).'|'.strtolower(trim($option));
    }

    /**
     * @return array<string, list<int>>
     */
    private function buildProductNameOptionIndex(bool $hasOption): array
    {
        $columns = ['id', 'name'];
        if ($hasOption) {
            $columns[] = 'option';
        }

        $index = [];
        foreach (DB::table('products')->select($columns)->get() as $product) {
            $option = $hasOption ? (string) ($product->option ?? '') : '';
            $key = strtolower((string) $product->name).'|'.strtolower(trim($option));
            $index[$key][] = (int) $product->id;
        }

        return $index;
    }

    /**
     * @param  array<string, int>  $categoryIdByLower
     */
    private function resolveCategoryIdCached(string $categoryName, array &$categoryIdByLower): int
    {
        $lookupKey = strtolower($categoryName);
        if (isset($categoryIdByLower[$lookupKey])) {
            return $categoryIdByLower[$lookupKey];
        }

        $categoryId = (int) DB::table('categories')->insertGetId([
            'name' => $categoryName,
            'icon' => null,
            'description' => null,
        ]);

        $categoryIdByLower[$lookupKey] = $categoryId;

        return $categoryId;
    }

    private function normalizeCategoryName(string $raw): string
    {
        $name = trim($raw);
        $name = preg_replace('/^\d+\s*/', '', $name) ?? $name;

        return trim($name);
    }

    /**
     * @param  list<string>  $cells
     * @param  array<string, int>  $headerMap
     * @return array<string, string>
     */
    private function rowFromCells(array $cells, array $headerMap): array
    {
        $row = [];
        foreach ($headerMap as $key => $index) {
            $value = $cells[$index] ?? '';
            $row[$key] = is_scalar($value) || $value === null
                ? trim((string) $value)
                : '';
        }

        return $row;
    }

    /**
     * @return list<string>
     */
    private function parseCsvLine(string $line): array
    {
        return str_getcsv($line);
    }

    private function parseMoney(mixed $value, string $errorContext): ?float
    {
        if ($value === null || $value === '') {
            return 0.0;
        }

        if (! is_numeric($value)) {
            return null;
        }

        $parsed = round((float) $value, 2);
        if ($parsed < 0) {
            return null;
        }

        return $parsed;
    }

    private function parseOptionalMoney(mixed $value): float|null|false
    {
        if ($value === null || $value === '') {
            return null;
        }

        if (! is_numeric($value)) {
            return false;
        }

        $parsed = round((float) $value, 2);
        if ($parsed < 0) {
            return false;
        }

        return $parsed;
    }

    private function parseInt(mixed $value, int $default): int
    {
        if ($value === null || $value === '') {
            return $default;
        }

        if (! is_numeric($value)) {
            return $default;
        }

        return (int) $value;
    }

    private function parseQuantity(mixed $value, float $default): float
    {
        if ($value === null || $value === '') {
            return $default;
        }

        if (! is_numeric($value)) {
            return $default;
        }

        return round((float) $value, 3);
    }
}
