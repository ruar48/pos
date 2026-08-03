<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('app_settings')) {
            return;
        }

        // The original `refund_pin_hash` column was actually being used as the
        // cash drawer PIN (refund and cash drawer shared one PIN). Rename it so
        // a genuinely separate refund PIN column can be added below.
        if (Schema::hasColumn('app_settings', 'refund_pin_hash')
            && ! Schema::hasColumn('app_settings', 'cash_drawer_pin_hash')) {
            DB::statement('ALTER TABLE app_settings CHANGE refund_pin_hash cash_drawer_pin_hash VARCHAR(255) NULL');
        }

        Schema::table('app_settings', function (Blueprint $table) {
            if (! Schema::hasColumn('app_settings', 'refund_pin_hash')) {
                $table->string('refund_pin_hash', 255)->nullable()->after('cash_drawer_pin_hash');
            }
        });
    }

    public function down(): void
    {
        if (! Schema::hasTable('app_settings')) {
            return;
        }

        Schema::table('app_settings', function (Blueprint $table) {
            if (Schema::hasColumn('app_settings', 'refund_pin_hash')) {
                $table->dropColumn('refund_pin_hash');
            }
        });

        if (Schema::hasColumn('app_settings', 'cash_drawer_pin_hash')
            && ! Schema::hasColumn('app_settings', 'refund_pin_hash')) {
            DB::statement('ALTER TABLE app_settings CHANGE cash_drawer_pin_hash refund_pin_hash VARCHAR(255) NULL');
        }
    }
};
