<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('drawer_expenses')) {
            return;
        }

        if (DB::connection()->getDriverName() !== 'mysql') {
            // ENUM/MODIFY is MySQL-only; SQLite stores payment_type as a
            // plain string, so there's no column definition to widen.
            return;
        }

        DB::statement(
            "ALTER TABLE drawer_expenses MODIFY payment_type ENUM('cash', 'gcash', 'bank', 'non_cash') NOT NULL DEFAULT 'cash'",
        );

        DB::table('drawer_expenses')
            ->where('payment_type', 'non_cash')
            ->update(['payment_type' => 'gcash']);

        DB::statement(
            "ALTER TABLE drawer_expenses MODIFY payment_type ENUM('cash', 'gcash', 'bank') NOT NULL DEFAULT 'cash'",
        );
    }

    public function down(): void
    {
        if (! Schema::hasTable('drawer_expenses')) {
            return;
        }

        if (DB::connection()->getDriverName() !== 'mysql') {
            return;
        }

        DB::statement(
            "ALTER TABLE drawer_expenses MODIFY payment_type ENUM('cash', 'non_cash') NOT NULL DEFAULT 'cash'",
        );
    }
};
