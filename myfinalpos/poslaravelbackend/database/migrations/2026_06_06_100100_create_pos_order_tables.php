<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('orders', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('customer_id')->nullable();
            $table->unsignedInteger('branch_id')->nullable()->default(1);
            $table->unsignedInteger('cashier_user_id')->nullable();
            $table->decimal('subtotal', 12, 2)->default(0);
            $table->decimal('vat', 12, 2)->default(0);
            $table->decimal('total_amount', 12, 2)->default(0);
            $table->decimal('refunded_amount', 12, 2)->default(0);
            $table->decimal('discount_amount', 12, 2)->default(0);
            $table->decimal('coupon_discount', 12, 2)->default(0);
            $table->decimal('loyalty_discount', 12, 2)->default(0);
            $table->integer('loyalty_points_redeemed')->default(0);
            $table->decimal('client_change', 12, 2)->default(0);
            $table->string('payment_method', 50)->default('Cash');
            $table->string('reference', 255)->nullable();
            $table->string('status', 30)->default('completed');
            $table->timestamp('created_at')->useCurrent();

            $table->foreign('customer_id')
                ->references('id')
                ->on('customers')
                ->restrictOnDelete();
        });

        Schema::create('order_items', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('order_id');
            $table->unsignedInteger('product_id');
            $table->unsignedInteger('variety_id')->nullable();
            $table->string('product_name', 255);
            $table->string('variety_name', 255)->nullable();
            $table->integer('quantity')->default(1);
            $table->integer('refunded_quantity')->default(0);
            $table->decimal('price', 12, 2)->default(0);
            $table->decimal('unit_cost', 12, 2)->nullable();
            $table->decimal('total', 12, 2)->default(0);
            $table->timestamp('created_at')->useCurrent();

            $table->foreign('order_id')
                ->references('id')
                ->on('orders')
                ->cascadeOnDelete();

            $table->foreign('product_id')
                ->references('id')
                ->on('products')
                ->restrictOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_items');
        Schema::dropIfExists('orders');
    }
};
