<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('products')) {
            return;
        }

        Schema::table('products', function (Blueprint $table) {
            $columns = [];

            if (Schema::hasColumn('products', 'sku')) {
                $columns[] = 'sku';
            }

            if (Schema::hasColumn('products', 'barcode')) {
                $columns[] = 'barcode';
            }

            if ($columns !== []) {
                $table->dropColumn($columns);
            }
        });
    }

    public function down(): void
    {
        if (! Schema::hasTable('products')) {
            return;
        }

        Schema::table('products', function (Blueprint $table) {
            if (! Schema::hasColumn('products', 'sku')) {
                $table->string('sku', 60)->nullable()->unique()->after('description');
            }

            if (! Schema::hasColumn('products', 'barcode')) {
                $table->string('barcode', 60)->nullable()->unique()->after('sku');
            }
        });
    }
};
