<?php

namespace App\Services\Pos;

use App\Support\CatalogStockRevision;
use App\Support\PosHelpers;
use App\Support\StockLedger;
use Illuminate\Support\Facades\DB;

/**
 * Admin "Update" on the Adjust Stock dialog: sets an item to an exact count,
 * but only with a reason and the cash drawer PIN. A size's stock is set
 * directly and its product total moves by the same amount, matching how a
 * sale lowers both.
 */
class StockUpdateService
{
    /**
     * @return array{previous_stock: float, new_stock: float}
     *
     * @throws \InvalidArgumentException when the input or PIN is rejected
     */
    public function update(
        int $productId,
        ?int $varietyId,
        float $newStock,
        string $reason,
        string $pin,
        ?int $actorUserId,
    ): array {
        $reason = trim($reason);

        if ($productId <= 0) {
            throw new \InvalidArgumentException('product_id is required');
        }
        if ($newStock < 0) {
            throw new \InvalidArgumentException('Stock cannot be negative');
        }
        if ($reason === '') {
            throw new \InvalidArgumentException('A reason is required');
        }
        if (! PosHelpers::verifyCashDrawerPin(trim($pin))) {
            throw new \InvalidArgumentException('Invalid or missing cash drawer PIN');
        }

        $reason = mb_substr($reason, 0, 200);

        $result = DB::transaction(function () use ($productId, $varietyId, $newStock, $reason, $actorUserId) {
            $product = DB::table('products')
                ->select('id', 'name', 'stock')
                ->where('id', $productId)
                ->where('status', 'active')
                ->lockForUpdate()
                ->first();
            if (! $product) {
                throw new \InvalidArgumentException('Product not found');
            }

            $variety = null;
            if ($varietyId !== null) {
                $variety = DB::table('product_varieties')
                    ->select('id', 'name', 'stock')
                    ->where('id', $varietyId)
                    ->where('product_id', $productId)
                    ->lockForUpdate()
                    ->first();
                if (! $variety) {
                    throw new \InvalidArgumentException('Size not found for this product');
                }
            }

            $previousStock = (float) ($variety ? $variety->stock : $product->stock);
            $delta = $newStock - $previousStock;

            if ($variety) {
                DB::update('UPDATE product_varieties SET stock = ? WHERE id = ?', [$newStock, $varietyId]);
            }
            DB::update(
                'UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?',
                [$delta, now(), $productId],
            );

            StockLedger::record(
                productId: $productId,
                varietyId: $varietyId,
                type: 'adjustment',
                quantityDelta: $delta,
                balanceAfter: $newStock,
                referenceType: 'inventory',
                referenceId: $productId,
                note: 'Stock update: '.$reason,
                userId: $actorUserId,
            );

            PosHelpers::insertAuditLog(
                $actorUserId,
                'update',
                'inventory',
                $variety ? 'product_variety' : 'product',
                $variety ? (int) $varietyId : $productId,
                'Stock updated with PIN: '.$reason,
                [
                    'name' => $product->name,
                    'variety' => $variety?->name,
                    'previous_stock' => $previousStock,
                    'new_stock' => $newStock,
                    'delta' => $delta,
                    'reason' => $reason,
                ],
            );

            return [
                'previous_stock' => $previousStock,
                'new_stock' => $newStock,
                'product_stock_before' => (float) $product->stock,
            ];
        });

        CatalogStockRevision::bump();

        if ($varietyId === null) {
            app(LowStockNotificationService::class)->afterStockChange(
                $productId,
                $result['previous_stock'],
                $result['new_stock'],
            );
        }

        return [
            'previous_stock' => $result['previous_stock'],
            'new_stock' => $result['new_stock'],
        ];
    }
}
