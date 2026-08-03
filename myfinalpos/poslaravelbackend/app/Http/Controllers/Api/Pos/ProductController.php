<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\LowStockNotificationService;
use App\Support\CatalogStockRevision;
use App\Support\PosApiLogger;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use App\Support\ProductImageStorage;
use App\Support\ProductPriceHistory;
use App\Support\StockLedger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class ProductController extends Controller
{
    use PosApiResponse;

    private const SELECT_COLUMNS = '
                p.id,
                p.category_id,
                p.name,
                p.option,
                p.description,
                p.price,
                p.cost_price,
                p.deal,
                p.stock,
                p.reorder_level,
                p.image_url,
                p.status,
                p.created_at,
                p.updated_at,
                c.name AS category_name';

    public function handle(Request $request): JsonResponse
    {
        if (! Schema::hasTable('products')) {
            return $this->posError(
                'POS database is not ready. Import backend/sql/agriculture_system.sql first.',
                503,
            );
        }

        return match ($request->method()) {
            'GET' => $this->read($request),
            'POST' => $this->store($request),
            'PUT', 'PATCH' => $this->update($request),
            'DELETE' => $this->destroy($request),
            default => $this->posError('Method not allowed', 405),
        };
    }

    private function read(Request $request): JsonResponse
    {
        $action = strtolower(trim((string) $request->query('action', '')));
        if ($action === 'watch') {
            return $this->posSuccess([
                'data' => app(\App\Services\Pos\PosCatalogSyncService::class)->watch(
                    $request->query('stock_revision'),
                    $request->query('settings_revision'),
                ),
            ]);
        }

        if ($action === 'stock') {
            return $this->stockSync($request);
        }

        return $this->index($request);
    }

    private function stockSync(Request $request): JsonResponse
    {
        $sinceRevision = trim((string) $request->query('revision', ''));

        return $this->posSuccess([
            'data' => app(\App\Services\Pos\CatalogStockService::class)->syncPayload(
                $sinceRevision !== '' ? $sinceRevision : null,
            ),
        ]);
    }

    private function index(?Request $request = null): JsonResponse
    {
        $page = (int) ($request?->query('page') ?? 0);

        if ($page <= 0) {
            $rows = DB::select(
                'SELECT '.self::SELECT_COLUMNS.'
                 FROM products p
                 INNER JOIN categories c ON c.id = p.category_id
                 WHERE p.status = "active"
                 ORDER BY p.id ASC',
            );

            return $this->posSuccess([
                'data' => array_map(static fn ($row) => (array) $row, $rows),
            ]);
        }

        $perPage = max(1, min(200, (int) ($request?->query('per_page') ?? 100)));
        $search = trim((string) $request?->query('search', ''));
        $category = trim((string) $request?->query('category', ''));

        $where = ['p.status = "active"'];
        $bindings = [];

        if ($search !== '') {
            $where[] = 'p.name LIKE ?';
            $bindings[] = '%'.str_replace(['%', '_'], ['\\%', '\\_'], $search).'%';
        }

        if ($category !== '') {
            $where[] = 'c.name = ?';
            $bindings[] = $category;
        }

        $whereSql = implode(' AND ', $where);

        $total = (int) DB::selectOne(
            "SELECT COUNT(*) AS total
             FROM products p
             INNER JOIN categories c ON c.id = p.category_id
             WHERE {$whereSql}",
            $bindings,
        )->total;

        $catalogTotal = (int) DB::selectOne(
            'SELECT COUNT(*) AS total FROM products WHERE status = "active"',
        )->total;

        $lowStockTotal = (int) DB::selectOne(
            'SELECT COUNT(*) AS total
             FROM products
             WHERE status = "active"
               AND COALESCE(stock, 0) <= COALESCE(reorder_level, 0)',
        )->total;

        $categoryCountRows = DB::select(
            'SELECT c.name AS category_name, COUNT(*) AS total
             FROM products p
             INNER JOIN categories c ON c.id = p.category_id
             WHERE p.status = "active"
             GROUP BY c.name',
        );
        $categoryCounts = [];
        foreach ($categoryCountRows as $row) {
            $categoryCounts[(string) $row->category_name] = (int) $row->total;
        }

        $rows = DB::select(
            "SELECT ".self::SELECT_COLUMNS."
             FROM products p
             INNER JOIN categories c ON c.id = p.category_id
             WHERE {$whereSql}
             ORDER BY p.id ASC
             LIMIT ? OFFSET ?",
            [...$bindings, $perPage, ($page - 1) * $perPage],
        );

        return $this->posSuccess([
            'data' => array_map(static fn ($row) => (array) $row, $rows),
            'meta' => [
                'page' => $page,
                'per_page' => $perPage,
                'total' => $total,
                'has_more' => $page * $perPage < $total,
                'catalog_total' => $catalogTotal,
                'low_stock_total' => $lowStockTotal,
                'category_counts' => $categoryCounts,
            ],
        ]);
    }

    private function store(Request $request): JsonResponse
    {
        PosApiLogger::info('product.store.start', PosApiLogger::requestContext($request));

        try {
            $payload = $this->parseProductPayload($request);
        } catch (\InvalidArgumentException $e) {
            PosApiLogger::warning('product.store.validation_failed', [
                'reason' => $e->getMessage(),
            ] + PosApiLogger::requestContext($request));

            return $this->posError($e->getMessage(), 400);
        } catch (\RuntimeException $e) {
            PosApiLogger::error('product.store.image_failed', PosApiLogger::requestContext($request), $e);

            return $this->posError($e->getMessage(), 500);
        }

        if ($payload['name'] === '' || $payload['category_name'] === '' || $payload['price'] < 0) {
            PosApiLogger::warning('product.store.missing_required_fields', [
                'name' => $payload['name'],
                'category' => $payload['category_name'],
                'price' => $payload['price'],
            ]);

            return $this->posError('name, category, and valid price are required', 400);
        }

        $actorUserId = PosHelpers::currentActorId($request);

        try {
            DB::beginTransaction();

            $categoryId = $this->resolveCategoryId($payload['category_name']);

            $productId = (int) DB::table('products')->insertGetId([
                'category_id' => $categoryId,
                'name' => $payload['name'],
                'option' => $payload['option'],
                'description' => $payload['description'],
                'price' => $payload['price'],
                'cost_price' => $payload['cost_price'],
                'deal' => $payload['deal'],
                'stock' => $payload['stock'],
                'reorder_level' => $payload['reorder_level'],
                'image_url' => $payload['image_url'],
                'status' => 'active',
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            if ((int) $payload['stock'] !== 0) {
                StockLedger::record(
                    productId: $productId,
                    varietyId: null,
                    type: 'initial',
                    quantityDelta: (int) $payload['stock'],
                    balanceAfter: (int) $payload['stock'],
                    referenceType: 'product',
                    referenceId: $productId,
                    note: 'Initial stock on create',
                    userId: $actorUserId,
                );
            }

            $this->logProductChange(
                $actorUserId,
                'create',
                $productId,
                $payload['name'],
                $payload['category_name'],
                $payload['price'],
                $payload['stock'],
            );

            $this->snapshotProductPrices($productId);

            DB::commit();

            CatalogStockRevision::bump();

            app(LowStockNotificationService::class)->afterStockChange(
                $productId,
                max((int) $payload['stock'] + 1, 1),
                (int) $payload['stock'],
            );

            PosApiLogger::info('product.store.success', [
                'product_id' => $productId,
                'name' => $payload['name'],
                'image_url' => $payload['image_url'],
            ]);

            return $this->posSuccess([
                'message' => 'Product saved successfully',
                'data' => $this->fetchProductRow($productId),
            ], 201);
        } catch (\InvalidArgumentException $e) {
            DB::rollBack();

            return $this->posError($e->getMessage(), 400);
        } catch (\Throwable $e) {
            DB::rollBack();

            PosApiLogger::error('product.store.failed', [
                'name' => $payload['name'] ?? null,
            ] + PosApiLogger::requestContext($request), $e);

            return $this->posServerError($e);
        }
    }

    private function update(Request $request): JsonResponse
    {
        $productId = (int) $request->input('id', 0);
        if ($productId <= 0) {
            return $this->posError('Product id is required', 400);
        }

        $existing = DB::selectOne(
            'SELECT p.*, c.name AS category_name
             FROM products p
             INNER JOIN categories c ON c.id = p.category_id
             WHERE p.id = ?
             LIMIT 1',
            [$productId],
        );

        if (! $existing) {
            return $this->posError('Product not found', 404);
        }

        try {
            $payload = $this->parseProductPayload($request, (array) $existing);
        } catch (\InvalidArgumentException $e) {
            PosApiLogger::warning('product.update.validation_failed', [
                'product_id' => $productId,
                'reason' => $e->getMessage(),
            ] + PosApiLogger::requestContext($request));

            return $this->posError($e->getMessage(), 400);
        } catch (\RuntimeException $e) {
            PosApiLogger::error('product.update.image_failed', [
                'product_id' => $productId,
            ] + PosApiLogger::requestContext($request), $e);

            return $this->posError($e->getMessage(), 500);
        }
        $actorUserId = PosHelpers::currentActorId($request);

        if ($payload['name'] === '' || $payload['category_name'] === '' || $payload['price'] < 0) {
            return $this->posError('name, category, and valid price are required', 400);
        }

        $previousStock = (int) ($existing->stock ?? 0);

        try {
            DB::beginTransaction();

            $categoryId = $this->resolveCategoryId($payload['category_name']);

            DB::table('products')
                ->where('id', $productId)
                ->update([
                    'category_id' => $categoryId,
                    'name' => $payload['name'],
                    'option' => $payload['option'],
                    'description' => $payload['description'],
                    'price' => $payload['price'],
                    'cost_price' => $payload['cost_price'],
                    'deal' => $payload['deal'],
                    'stock' => $payload['stock'],
                    'reorder_level' => $payload['reorder_level'],
                    'image_url' => $payload['image_url'],
                    'updated_at' => now(),
                ]);

            $delta = (int) $payload['stock'] - $previousStock;
            if ($delta !== 0) {
                StockLedger::record(
                    productId: $productId,
                    varietyId: null,
                    type: 'adjustment',
                    quantityDelta: $delta,
                    balanceAfter: (int) $payload['stock'],
                    referenceType: 'product',
                    referenceId: $productId,
                    note: 'Stock edited via product form',
                    userId: $actorUserId,
                );
            }

            $this->logProductChange(
                $actorUserId,
                'update',
                $productId,
                $payload['name'],
                $payload['category_name'],
                $payload['price'],
                $payload['stock'],
            );

            $this->snapshotProductPrices($productId);

            DB::commit();

            CatalogStockRevision::bump();

            app(LowStockNotificationService::class)->afterStockChange(
                $productId,
                $previousStock,
                (int) $payload['stock'],
            );

            return $this->posSuccess([
                'message' => 'Product updated successfully',
                'data' => $this->fetchProductRow($productId),
            ]);
        } catch (\InvalidArgumentException $e) {
            DB::rollBack();

            return $this->posError($e->getMessage(), 400);
        } catch (\Throwable $e) {
            DB::rollBack();

            return $this->posServerError($e);
        }
    }

    private function destroy(Request $request): JsonResponse
    {
        $productId = (int) $request->input('id', 0);
        if ($productId <= 0) {
            return $this->posError('Product id is required', 400);
        }

        $existing = DB::selectOne(
            'SELECT p.*, c.name AS category_name
             FROM products p
             INNER JOIN categories c ON c.id = p.category_id
             WHERE p.id = ?
             LIMIT 1',
            [$productId],
        );

        if (! $existing) {
            return $this->posError('Product not found', 404);
        }

        if ((string) ($existing->status ?? 'active') !== 'active') {
            return $this->posError('Product already removed', 404);
        }

        $actorUserId = PosHelpers::currentActorId($request);

        try {
            DB::table('products')
                ->where('id', $productId)
                ->update([
                    'status' => 'inactive',
                    'updated_at' => now(),
                ]);

            PosHelpers::insertAuditLog(
                $actorUserId,
                'delete',
                'inventory',
                'product',
                $productId,
                'Product removed from catalog',
                [
                    'name' => (string) $existing->name,
                    'category' => (string) $existing->category_name,
                ],
            );

            CatalogStockRevision::bump();

            return $this->posSuccess([
                'message' => 'Product removed successfully',
            ]);
        } catch (\Throwable $e) {
            PosApiLogger::error('product.delete.failed', [
                'product_id' => $productId,
            ] + PosApiLogger::requestContext($request), $e);

            return $this->posServerError($e);
        }
    }

    /**
     * @param  array<string, mixed>|null  $existing
     * @return array{
     *     name: string,
     *     category_name: string,
     *     price: float,
     *     cost_price: ?float,
     *     stock: int,
     *     reorder_level: int,
     *     reorder_level: int,
     *     description: ?string,
     *     image_url: ?string,
     *     option: ?string
     * }
     */
    private function parseProductPayload(Request $request, ?array $existing = null): array
    {
        $name = trim((string) $request->input(
            'name',
            $existing['name'] ?? '',
        ));
        $option = trim((string) $request->input(
            'option',
            $existing['option'] ?? '',
        ));
        if (strlen($option) > 120) {
            throw new \InvalidArgumentException('Option must be 120 characters or less');
        }
        $categoryName = trim((string) $request->input(
            'category',
            $existing['category_name'] ?? '',
        ));
        $price = $this->parseMoneyField(
            $request->input('price', $existing['price'] ?? 0),
            'price',
            false,
        );
        $costPrice = $this->parseMoneyField(
            $request->input('cost_price', $existing['cost_price'] ?? null),
            'cost',
            true,
        );
        $deal = trim((string) $request->input(
            'deal',
            $existing['deal'] ?? '',
        ));
        if (strlen($deal) > 500) {
            throw new \InvalidArgumentException('Deal must be 500 characters or less');
        }
        $stock = (int) ($request->input(
            'stock',
            $existing['stock'] ?? 0,
        ) ?? 0);
        $reorderLevel = (int) ($request->input(
            'reorder_level',
            $existing['reorder_level'] ?? 5,
        ) ?? 5);
        $description = trim((string) $request->input(
            'description',
            $existing['description'] ?? '',
        ));
        $imageUrl = $this->resolveProductImageUrl($request, $existing);

        return [
            'name' => $name,
            'option' => $option === '' ? null : $option,
            'category_name' => $categoryName,
            'price' => $price,
            'cost_price' => $costPrice,
            'deal' => $deal === '' ? null : $deal,
            'stock' => $stock,
            'reorder_level' => max(0, $reorderLevel),
            'description' => $description === '' ? null : $description,
            'image_url' => $imageUrl === '' ? null : $imageUrl,
        ];
    }

    /**
     * @throws \InvalidArgumentException
     */
    private function parseMoneyField(mixed $input, string $label, bool $allowNull): ?float
    {
        if ($input === null || $input === '') {
            return $allowNull ? null : 0.0;
        }

        if (! is_numeric($input)) {
            throw new \InvalidArgumentException("Enter a valid {$label}");
        }

        $value = round((float) $input, 2);
        if ($value < 0) {
            throw new \InvalidArgumentException(ucfirst($label).' cannot be negative');
        }

        return $value;
    }

    private function resolveProductImageUrl(Request $request, ?array $existing = null): ?string
    {
        $base64 = trim((string) $request->input('image_base64', ''));
        if ($base64 !== '') {
            PosApiLogger::info('product.image.save.start', [
                'filename' => $request->input('image_filename'),
                'mime_type' => $request->input('image_mime_type'),
                'base64_chars' => strlen($base64),
            ]);

            try {
                $saved = ProductImageStorage::saveBase64(
                    $base64,
                    (string) $request->input('image_filename', 'upload.jpg'),
                    (string) $request->input('image_mime_type', 'image/jpeg'),
                );
            } catch (\Throwable $throwable) {
                PosApiLogger::error('product.image.save.failed', [
                    'filename' => $request->input('image_filename'),
                    'mime_type' => $request->input('image_mime_type'),
                    'base64_chars' => strlen($base64),
                ], $throwable);
                throw $throwable;
            }

            PosApiLogger::info('product.image.save.success', [
                'image_url' => $saved['image_url'],
            ]);

            return $saved['image_url'];
        }

        $imageUrl = trim((string) $request->input(
            'image_url',
            $existing['image_url'] ?? '',
        ));

        return $imageUrl === '' ? null : $imageUrl;
    }

    private function resolveCategoryId(string $categoryName): int
    {
        $category = DB::selectOne(
            'SELECT id FROM categories WHERE LOWER(name) = LOWER(?) LIMIT 1',
            [$categoryName],
        );

        if ($category) {
            return (int) $category->id;
        }

        return (int) DB::table('categories')->insertGetId([
            'name' => $categoryName,
            'icon' => null,
            'description' => null,
        ]);
    }

    private function fetchProductRow(int $productId): array
    {
        $row = DB::selectOne(
            'SELECT '.self::SELECT_COLUMNS.'
             FROM products p
             INNER JOIN categories c ON c.id = p.category_id
             WHERE p.id = ?
             LIMIT 1',
            [$productId],
        );

        return (array) $row;
    }

    private function snapshotProductPrices(int $productId): void
    {
        $product = DB::selectOne(
            'SELECT price, cost_price FROM products WHERE id = ? LIMIT 1',
            [$productId],
        );

        if ($product) {
            ProductPriceHistory::recordIfChanged(
                $productId,
                null,
                (float) ($product->cost_price ?? 0),
                (float) ($product->price ?? 0),
            );
        }
    }

    private function logProductChange(
        ?int $actorUserId,
        string $action,
        int $productId,
        string $name,
        string $categoryName,
        float $price,
        int $stock,
    ): void {
        PosHelpers::insertAuditLog(
            $actorUserId,
            $action,
            'inventory',
            'product',
            $productId,
            $action === 'create'
                ? 'Product saved successfully'
                : 'Product updated successfully',
            [
                'name' => $name,
                'category' => $categoryName,
                'price' => $price,
            ],
        );

        PosHelpers::insertUserTransaction(
            $actorUserId,
            $action === 'create' ? 'product_save' : 'product_update',
            'products',
            $productId,
            $price,
            $action === 'create'
                ? 'Product record saved'
                : 'Product record updated',
            [
                'name' => $name,
                'stock' => $stock,
            ],
        );
    }
}
