<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('stock_movements', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('product_id');
            $table->unsignedInteger('variety_id')->nullable();
            // sale, refund, adjustment, initial, purchase
            $table->string('type', 30)->default('adjustment');
            $table->integer('quantity_delta');
            $table->integer('balance_after')->nullable();
            $table->string('reference_type', 30)->nullable();
            $table->unsignedInteger('reference_id')->nullable();
            $table->string('note', 255)->nullable();
            $table->unsignedInteger('user_id')->nullable();
            $table->timestamp('created_at')->nullable();

            $table->index(['product_id', 'created_at']);
            $table->index(['variety_id', 'created_at']);

            $table->foreign('product_id')
                ->references('id')
                ->on('products')
                ->cascadeOnDelete();
        });

        $this->backfill();
    }

    private function backfill(): void
    {
        if (Schema::hasTable('order_items') && Schema::hasTable('orders')) {
            $hasVariety = Schema::hasColumn('order_items', 'variety_id');
            $varietySelect = $hasVariety ? 'oi.variety_id' : 'NULL';

            DB::statement(
                "INSERT INTO stock_movements
                    (product_id, variety_id, type, quantity_delta, reference_type, reference_id, note, created_at)
                 SELECT oi.product_id, {$varietySelect}, 'sale', -oi.quantity, 'order', oi.order_id,
                        'Backfilled from sale', o.created_at
                 FROM order_items oi
                 INNER JOIN orders o ON o.id = oi.order_id"
            );
        }

        if (Schema::hasTable('refund_items') && Schema::hasTable('refunds')) {
            $hasVariety = Schema::hasColumn('order_items', 'variety_id');
            $varietySelect = $hasVariety ? 'oi.variety_id' : 'NULL';

            DB::statement(
                "INSERT INTO stock_movements
                    (product_id, variety_id, type, quantity_delta, reference_type, reference_id, note, created_at)
                 SELECT oi.product_id, {$varietySelect}, 'refund', ri.quantity, 'refund', ri.refund_id,
                        'Backfilled from refund', rf.created_at
                 FROM refund_items ri
                 INNER JOIN refunds rf ON rf.id = ri.refund_id
                 INNER JOIN order_items oi ON oi.id = ri.order_item_id"
            );
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_movements');
    }
};
