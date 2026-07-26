<?php

namespace App\Support;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Stores unit cost/price changes over time so inventory reports can value
 * stock using prices that were effective on the selected date — not today's
 * live catalog prices.
 */
class ProductPriceHistory
{
    public static function recordIfChanged(
        int $productId,
        ?int $varietyId,
        float $unitCost,
        float $unitPrice,
        ?Carbon $effectiveFrom = null,
    ): void {
        if ($productId <= 0 || ! Schema::hasTable('product_price_history')) {
            return;
        }

        $latest = self::latestFor($productId, $varietyId);
        if (
            $latest !== null
            && abs($latest['unit_cost'] - $unitCost) < 0.001
            && abs($latest['unit_price'] - $unitPrice) < 0.001
        ) {
            return;
        }

        self::record($productId, $varietyId, $unitCost, $unitPrice, $effectiveFrom);
    }

    public static function record(
        int $productId,
        ?int $varietyId,
        float $unitCost,
        float $unitPrice,
        ?Carbon $effectiveFrom = null,
    ): void {
        if ($productId <= 0 || ! Schema::hasTable('product_price_history')) {
            return;
        }

        $effectiveFrom ??= now();

        DB::insert(
            'INSERT INTO product_price_history
                (product_id, variety_id, unit_cost, unit_price, effective_from)
             VALUES (?, ?, ?, ?, ?)',
            [
                $productId,
                ($varietyId !== null && $varietyId > 0) ? $varietyId : null,
                round($unitCost, 2),
                round($unitPrice, 2),
                $effectiveFrom,
            ],
        );
    }

    /**
     * @return array<string, object{unit_cost: float, unit_price: float}>
     */
    public static function pricesAsOf(string $asOfDatetime): array
    {
        if (! Schema::hasTable('product_price_history')) {
            return [];
        }

        $rows = DB::select(
            'SELECT h.product_id, h.variety_id, h.unit_cost, h.unit_price
             FROM product_price_history h
             INNER JOIN (
                 SELECT product_id, variety_id, MAX(effective_from) AS max_effective
                 FROM product_price_history
                 WHERE effective_from <= :as_of
                 GROUP BY product_id, variety_id
             ) latest
               ON latest.product_id = h.product_id
              AND (
                    (latest.variety_id IS NULL AND h.variety_id IS NULL)
                 OR (latest.variety_id = h.variety_id)
              )
              AND latest.max_effective = h.effective_from',
            ['as_of' => $asOfDatetime],
        );

        $map = [];
        foreach ($rows as $row) {
            $key = self::key((int) $row->product_id, $row->variety_id !== null ? (int) $row->variety_id : null);
            $map[$key] = (object) [
                'unit_cost' => (float) $row->unit_cost,
                'unit_price' => (float) $row->unit_price,
            ];
        }

        return $map;
    }

    /**
     * @return array{unit_cost: float, unit_price: float}|null
     */
    public static function latestFor(int $productId, ?int $varietyId): ?array
    {
        if (! Schema::hasTable('product_price_history')) {
            return null;
        }

        if ($varietyId !== null && $varietyId > 0) {
            $row = DB::selectOne(
                'SELECT unit_cost, unit_price
                 FROM product_price_history
                 WHERE product_id = ? AND variety_id = ?
                 ORDER BY effective_from DESC
                 LIMIT 1',
                [$productId, $varietyId],
            );
        } else {
            $row = DB::selectOne(
                'SELECT unit_cost, unit_price
                 FROM product_price_history
                 WHERE product_id = ? AND variety_id IS NULL
                 ORDER BY effective_from DESC
                 LIMIT 1',
                [$productId],
            );
        }

        if (! $row) {
            return null;
        }

        return [
            'unit_cost' => (float) $row->unit_cost,
            'unit_price' => (float) $row->unit_price,
        ];
    }

    public static function key(int $productId, ?int $varietyId): string
    {
        return $varietyId !== null && $varietyId > 0
            ? "{$productId}:{$varietyId}"
            : (string) $productId;
    }

    /**
     * @param  array<string, object{unit_cost: float, unit_price: float}>  $priceMap
     * @return array{0: float, 1: float}
     */
    public static function resolve(
        array $priceMap,
        int $productId,
        ?int $varietyId,
        float $fallbackCost,
        float $fallbackPrice,
    ): array {
        $key = self::key($productId, $varietyId);
        $entry = $priceMap[$key] ?? null;

        if ($entry === null) {
            return [$fallbackCost, $fallbackPrice];
        }

        return [(float) $entry->unit_cost, (float) $entry->unit_price];
    }
}
