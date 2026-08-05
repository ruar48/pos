<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Records signed stock movements into the stock_movements ledger so the
 * inventory report can reconstruct beginning / added / deducted / ending
 * balances for any date range. All writes are best-effort: if the ledger
 * table is missing the call is a no-op so it never breaks a sale or refund.
 */
class StockLedger
{
    public static function record(
        int $productId,
        ?int $varietyId,
        string $type,
        float $quantityDelta,
        ?float $balanceAfter = null,
        ?string $referenceType = null,
        ?int $referenceId = null,
        ?string $note = null,
        ?int $userId = null,
    ): void {
        if ($productId <= 0 || $quantityDelta === 0) {
            return;
        }

        if (! Schema::hasTable('stock_movements')) {
            return;
        }

        DB::insert(
            'INSERT INTO stock_movements
                (product_id, variety_id, type, quantity_delta, balance_after, reference_type, reference_id, note, user_id, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $productId,
                ($varietyId !== null && $varietyId > 0) ? $varietyId : null,
                $type,
                $quantityDelta,
                $balanceAfter,
                $referenceType,
                $referenceId,
                $note,
                ($userId !== null && $userId > 0) ? $userId : null,
                now(),
            ],
        );
    }
}
