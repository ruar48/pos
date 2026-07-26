<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('products') && ! Schema::hasColumn('products', 'deal')) {
            Schema::table('products', function (Blueprint $table) {
                $table->string('deal', 500)->nullable()->after('cost_price');
            });
        }

        if (
            Schema::hasTable('product_varieties')
            && ! Schema::hasColumn('product_varieties', 'deal')
        ) {
            Schema::table('product_varieties', function (Blueprint $table) {
                $table->string('deal', 500)->nullable()->after('cost_price');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('products') && Schema::hasColumn('products', 'deal')) {
            Schema::table('products', function (Blueprint $table) {
                $table->dropColumn('deal');
            });
        }

        if (
            Schema::hasTable('product_varieties')
            && Schema::hasColumn('product_varieties', 'deal')
        ) {
            Schema::table('product_varieties', function (Blueprint $table) {
                $table->dropColumn('deal');
            });
        }
    }
};
