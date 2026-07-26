<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('product_varieties') && Schema::hasTable('products')) {
            $aggregates = DB::table('product_varieties')
                ->where('status', 'active')
                ->selectRaw('product_id, COALESCE(SUM(stock), 0) AS total_stock, MIN(price) AS min_price')
                ->groupBy('product_id')
                ->get();

            foreach ($aggregates as $agg) {
                DB::table('products')
                    ->where('id', (int) $agg->product_id)
                    ->update([
                        'stock' => (int) $agg->total_stock,
                        'price' => round((float) $agg->min_price, 2),
                        'updated_at' => now(),
                    ]);
            }

            Schema::dropIfExists('product_varieties');
        }

        if (Schema::hasTable('products') && Schema::hasColumn('products', 'unit')) {
            Schema::table('products', function (Blueprint $table) {
                $table->dropColumn('unit');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('products') && ! Schema::hasColumn('products', 'unit')) {
            Schema::table('products', function (Blueprint $table) {
                $table->string('unit', 120)->default('pc')->after('reorder_level');
            });
        }

        if (! Schema::hasTable('product_varieties')) {
            Schema::create('product_varieties', function (Blueprint $table) {
                $table->increments('id');
                $table->unsignedInteger('product_id');
                $table->string('name', 150);
                $table->string('unit', 120)->nullable();
                $table->string('sku', 60)->nullable()->unique();
                $table->string('barcode', 60)->nullable()->unique();
                $table->decimal('price', 12, 2)->default(0);
                $table->decimal('cost_price', 12, 2)->nullable();
                $table->integer('stock')->default(0);
                $table->integer('reorder_level')->default(5);
                $table->string('image_url', 255)->nullable();
                $table->string('status', 30)->default('active');
                $table->timestamp('created_at')->nullable();
                $table->timestamp('updated_at')->nullable();

                $table->foreign('product_id')
                    ->references('id')
                    ->on('products')
                    ->cascadeOnDelete();
            });
        }
    }
};
