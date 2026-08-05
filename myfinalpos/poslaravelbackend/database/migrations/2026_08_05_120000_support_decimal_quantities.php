<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Weight/volume-sold items (e.g. "BLUESTRING - 6 KG") need fractional
 * quantities. Widening int -> decimal is non-destructive: existing whole
 * numbers convert exactly. Also adds a real per-line discount column so
 * item-level discounts persist independently instead of sharing the single
 * order-level discount_amount field.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (DB::connection()->getDriverName() !== 'mysql') {
            // MODIFY is MySQL-only; a fresh SQLite dev database already
            // creates these columns with the right precision.
            return;
        }

        $this->widenToDecimal('order_items', 'quantity', 12, 3);
        $this->widenToDecimal('order_items', 'refunded_quantity', 12, 3);
        $this->widenToDecimal('refund_items', 'quantity', 12, 3);
        $this->widenToDecimal('products', 'stock', 12, 3);
        $this->widenToDecimal('product_varieties', 'stock', 12, 3);
        $this->widenToDecimal('stock_movements', 'quantity_delta', 12, 3);
        $this->widenToDecimal('inventory_opening_balances', 'quantity', 12, 3);

        if (Schema::hasTable('order_items') && ! Schema::hasColumn('order_items', 'discount_amount')) {
            Schema::table('order_items', function (Blueprint $table) {
                $table->decimal('discount_amount', 12, 2)->default(0);
            });
        }
    }

    public function down(): void
    {
        // Non-destructive widening only.
    }

    private function widenToDecimal(string $table, string $column, int $precision, int $scale): void
    {
        if (! Schema::hasTable($table) || ! Schema::hasColumn($table, $column)) {
            return;
        }

        $current = DB::selectOne(
            'SELECT DATA_TYPE
             FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE()
               AND TABLE_NAME = ?
               AND COLUMN_NAME = ?',
            [$table, $column],
        );

        if ($current !== null && strtolower((string) $current->DATA_TYPE) === 'decimal') {
            return;
        }

        DB::statement(
            "ALTER TABLE {$table} MODIFY {$column} DECIMAL({$precision},{$scale}) NOT NULL DEFAULT 0",
        );
    }
};
