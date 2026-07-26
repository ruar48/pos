<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('orders') || Schema::hasColumn('orders', 'receipt_note')) {
            return;
        }

        Schema::table('orders', function (Blueprint $table) {
            $table->string('receipt_note', 255)->nullable()->after('reference');
        });
    }

    public function down(): void
    {
        if (! Schema::hasTable('orders') || ! Schema::hasColumn('orders', 'receipt_note')) {
            return;
        }

        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn('receipt_note');
        });
    }
};
