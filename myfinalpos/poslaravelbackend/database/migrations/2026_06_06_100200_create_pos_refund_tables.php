<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('refunds', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('order_id');
            $table->enum('refund_type', ['all', 'items'])->default('items');
            $table->decimal('amount', 12, 2)->default(0);
            $table->text('reason');
            $table->timestamp('created_at')->useCurrent();

            $table->foreign('order_id')
                ->references('id')
                ->on('orders')
                ->cascadeOnDelete();
        });

        Schema::create('refund_items', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('refund_id');
            $table->unsignedInteger('order_item_id');
            $table->integer('quantity')->default(1);
            $table->decimal('amount', 12, 2)->default(0);
            $table->timestamp('created_at')->useCurrent();

            $table->foreign('refund_id')
                ->references('id')
                ->on('refunds')
                ->cascadeOnDelete();

            $table->foreign('order_item_id')
                ->references('id')
                ->on('order_items')
                ->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('refund_items');
        Schema::dropIfExists('refunds');
    }
};
