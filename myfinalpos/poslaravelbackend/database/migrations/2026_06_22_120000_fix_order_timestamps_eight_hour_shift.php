<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Correct orders saved with UTC wall clock (+8h) before the timestamp fix.
 * Moves 2026-06-22 07:xx rows back to 2026-06-21 23:xx Philippines time.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("
            UPDATE orders
            SET created_at = DATE_SUB(created_at, INTERVAL 8 HOUR)
            WHERE created_at >= '2026-06-22 00:00:00'
              AND created_at < '2026-06-22 12:00:00'
        ");
    }

    public function down(): void
    {
        DB::statement("
            UPDATE orders
            SET created_at = DATE_ADD(created_at, INTERVAL 8 HOUR)
            WHERE created_at >= '2026-06-21 16:00:00'
              AND created_at < '2026-06-22 04:00:00'
        ");
    }
};
