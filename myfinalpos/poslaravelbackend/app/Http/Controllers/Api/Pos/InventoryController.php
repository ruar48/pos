<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\LowStockNotificationService;
use App\Support\CatalogStockRevision;
use App\Support\PosApiLogger;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use App\Support\StockLedger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class InventoryController extends Controller
{
    use PosApiResponse;

    private const SELECT_COLUMNS = '
                p.id,
                p.category_id,
                p.name,
                p.description,
                p.price,
                p.cost_price,
                p.stock,
                p.reorder_level,
                p.image_url,
                p.status,
                p.created_at,
                p.updated_at,
                c.name AS category_name';

    public function handle(Request $request): JsonResponse
    {
        if ($request->isMethod('OPTIONS')) {
            return $this->posSuccess();
        }

        if (! Schema::hasTable('products')) {
            return $this->posError(
                'POS database is not ready. Import backend/sql/agriculture_system.sql first.',
                503,
            );
        }

        return match ($request->method()) {
            'GET' => $this->index(),
            'POST' => $this->updateStock($request),
            default => $this->posError('Method not allowed', 405),
        };
    }

    private function index(): JsonResponse
    {
        $rows = DB::select(
            'SELECT '.self::SELECT_COLUMNS.'
             FROM products p
             INNER JOIN categories c ON c.id = p.category_id
             WHERE p.status = "active"
             ORDER BY p.stock ASC, c.name ASC, p.name ASC',
        );

        return $this->posSuccess([
            'data' => array_map(fn ($row) => (array) $row, $rows),
        ]);
    }

    private function updateStock(Request $request): JsonResponse
    {
        PosApiLogger::info('inventory.update.start', PosApiLogger::requestContext($request));

        $productId = (int) $request->input('product_id', 0);
        $hasStock = $request->exists('stock');
        $hasDelta = $request->exists('delta');
        $stock = $hasStock ? (int) $request->input('stock') : null;
        $delta = $hasDelta ? (int) $request->input('delta') : null;
        $actorUserId = PosHelpers::currentActorId($request);

        if ($productId <= 0) {
            return $this->posError('product_id is required', 400);
        }

        if (! $hasStock && ! $hasDelta) {
            return $this->posError('stock or delta is required', 400);
        }

        $product = DB::selectOne(
            'SELECT p.id, p.name, p.stock, p.price
             FROM products p
             WHERE p.id = ? AND p.status = "active"
             LIMIT 1',
            [$productId],
        );

        if (! $product) {
            return $this->posError('Product not found', 404);
        }

        $currentStock = (int) ($product->stock ?? 0);
        $newStock = $hasStock ? (int) $stock : ($currentStock + (int) $delta);

        if (! $this->allowNegativeStock() && $newStock < 0) {
            PosApiLogger::warning('inventory.update.rejected_negative_stock', [
                'product_id' => $productId,
                'current_stock' => $currentStock,
                'requested_stock' => $newStock,
            ]);

            return $this->posError('Stock cannot be negative', 400);
        }

        try {
            DB::beginTransaction();

            DB::table('products')
                ->where('id', $productId)
                ->update([
                    'stock' => $newStock,
                    'updated_at' => now(),
                ]);

            StockLedger::record(
                productId: $productId,
                varietyId: null,
                type: 'adjustment',
                quantityDelta: $newStock - $currentStock,
                balanceAfter: $newStock,
                referenceType: 'inventory',
                referenceId: $productId,
                note: 'Manual stock adjustment',
                userId: $actorUserId,
            );

            PosHelpers::insertAuditLog(
                $actorUserId,
                'update',
                'inventory',
                'product',
                $productId,
                'Stock updated',
                [
                    'name' => $product->name,
                    'previous_stock' => $currentStock,
                    'new_stock' => $newStock,
                    'delta' => $newStock - $currentStock,
                ],
            );

            PosHelpers::insertUserTransaction(
                $actorUserId,
                'stock_update',
                'products',
                $productId,
                (float) $product->price,
                'Inventory stock adjusted',
                [
                    'previous_stock' => $currentStock,
                    'new_stock' => $newStock,
                ],
            );

            StockLedger::record(
                productId: $productId,
                varietyId: null,
                type: 'adjustment',
                quantityDelta: $newStock - $currentStock,
                balanceAfter: $newStock,
                referenceType: 'inventory',
                referenceId: $productId,
                note: 'Manual stock adjustment',
                userId: $actorUserId,
            );

            DB::commit();
            CatalogStockRevision::bump();

            app(LowStockNotificationService::class)->afterStockChange(
                $productId,
                $currentStock,
                $newStock,
            );
        } catch (\Throwable $e) {
            DB::rollBack();

            PosApiLogger::error('inventory.update.failed', [
                'product_id' => $productId,
            ], $e);

            return $this->posServerError($e);
        }

        $updated = $this->fetchProductRow($productId);

        PosApiLogger::info('inventory.update.success', [
            'product_id' => $productId,
            'previous_stock' => $currentStock,
            'new_stock' => $newStock,
        ]);

        return $this->posSuccess([
            'message' => 'Stock updated successfully',
            'data' => $updated,
        ]);
    }

    private function allowNegativeStock(): bool
    {
        if (! PosHelpers::tableExists('app_settings')) {
            return false;
        }

        $settings = DB::selectOne(
            'SELECT allow_negative_stock
             FROM app_settings
             ORDER BY id ASC
             LIMIT 1',
        );

        return $settings && (int) ($settings->allow_negative_stock ?? 0) === 1;
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
}
