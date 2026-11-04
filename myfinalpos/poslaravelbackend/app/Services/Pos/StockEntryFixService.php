<?php

namespace App\Services\Pos;

use App\Support\CatalogStockRevision;
use App\Support\PosHelpers;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Rewrites a mistaken manual stock entry in place (e.g. "+10" that should have
 * been "+5") so the inventory history shows only the right figure. The
 * product's live stock moves by the difference and the running balances of the
 * entry and every later one are shifted to match. Needs a reason and the cash
 * drawer PIN, and the original value is kept in the audit log.
 */
class StockEntryFixService
{
    /**
     * Recent manual entries for a product (newest first) that can be fixed.
     *
     * @return list<array<string, mixed>>
     */
    public function recentEntries(int $productId, int $limit = 15): array
    {
        if ($productId <= 0 || ! Schema::hasTable('stock_movements')) {
            return [];
        }

        $rows = DB::select(
            'SELECT id, type, quantity_delta, balance_after, note, created_at
             FROM stock_movements
             WHERE product_id = ? AND variety_id IS NULL
               AND type = "adjustment" AND reference_type = "inventory"
               AND (note IS NULL OR note NOT LIKE "Stock update:%")
             ORDER BY id DESC
             LIMIT '.max(1, min(50, $limit)),
            [$productId],
        );

        return array_map(fn ($r) => [
            'id' => (int) $r->id,
            'type' => (string) $r->type,
            'quantity_delta' => (float) $r->quantity_delta,
            'balance_after' => $r->balance_after !== null ? (float) $r->balance_after : null,
            'note' => $r->note,
            'created_at' => $r->created_at,
        ], $rows);
    }

    /**
     * @param  float  $newDelta  the entry's correct signed quantity; 0 removes the entry
     * @return array{previous_delta: float, new_delta: float, new_stock: float}
     *
     * @throws \InvalidArgumentException when the input or PIN is rejected
     */
    public function fix(
        int $entryId,
        float $newDelta,
        string $reason,
        string $pin,
        ?int $actorUserId,
    ): array {
        $reason = trim($reason);

        if ($entryId <= 0) {
            throw new \InvalidArgumentException('entry_id is required');
        }
        if ($reason === '') {
            throw new \InvalidArgumentException('A reason is required');
        }
        if (! PosHelpers::verifyCashDrawerPin(trim($pin))) {
            throw new \InvalidArgumentException('Invalid or missing cash drawer PIN');
        }

        $reason = mb_substr($reason, 0, 200);

        $result = DB::transaction(function () use ($entryId, $newDelta, $reason, $actorUserId) {
            $entry = DB::table('stock_movements')
                ->where('id', $entryId)
                ->where('type', 'adjustment')
                ->where('reference_type', 'inventory')
                ->whereNull('variety_id')
                ->lockForUpdate()
                ->first();
            if (! $entry) {
                throw new \InvalidArgumentException('Stock entry not found or cannot be edited');
            }

            $productId = (int) $entry->product_id;
            $product = DB::table('products')
                ->select('id', 'name', 'stock')
                ->where('id', $productId)
                ->lockForUpdate()
                ->first();
            if (! $product) {
                throw new \InvalidArgumentException('Product not found');
            }

            $previousDelta = (float) $entry->quantity_delta;
            $diff = $newDelta - $previousDelta;
            $newStock = (float) $product->stock + $diff;

            if ($newStock < 0) {
                throw new \InvalidArgumentException(
                    'Stock would go below zero - part of it has already been sold',
                );
            }

            if ($newDelta == 0.0) {
                DB::table('stock_movements')->where('id', $entryId)->delete();
            } else {
                DB::update(
                    'UPDATE stock_movements
                     SET quantity_delta = ?, balance_after = balance_after + ?, note = ?
                     WHERE id = ?',
                    [$newDelta, $diff, mb_substr('Corrected entry: '.$reason, 0, 255), $entryId],
                );
            }

            DB::update(
                'UPDATE stock_movements SET balance_after = balance_after + ?
                 WHERE product_id = ? AND id > ? AND balance_after IS NOT NULL',
                [$diff, $productId, $entryId],
            );
            DB::update(
                'UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?',
                [$diff, now(), $productId],
            );

            PosHelpers::insertAuditLog(
                $actorUserId,
                'update',
                'inventory',
                'stock_movement',
                $entryId,
                ($newDelta == 0.0 ? 'Stock entry removed: ' : 'Stock entry corrected: ').$reason,
                [
                    'name' => $product->name,
                    'previous_delta' => $previousDelta,
                    'new_delta' => $newDelta,
                    'previous_stock' => (float) $product->stock,
                    'new_stock' => $newStock,
                    'reason' => $reason,
                ],
            );

            return [
                'previous_delta' => $previousDelta,
                'new_delta' => $newDelta,
                'new_stock' => $newStock,
            ];
        });

        CatalogStockRevision::bump();

        return $result;
    }
}
