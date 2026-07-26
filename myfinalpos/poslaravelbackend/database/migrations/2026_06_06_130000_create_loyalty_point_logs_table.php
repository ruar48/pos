<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('loyalty_point_logs', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->unsignedInteger('customer_id');
            $table->unsignedInteger('loyalty_card_id')->nullable();
            $table->unsignedInteger('order_id')->nullable();
            $table->string('action', 30);
            $table->integer('points_change');
            $table->integer('points_balance_after')->default(0);
            $table->decimal('order_amount', 12, 2)->nullable();
            $table->string('description', 255);
            $table->unsignedInteger('actor_user_id')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->foreign('customer_id')
                ->references('id')
                ->on('customers')
                ->cascadeOnDelete();
            $table->foreign('loyalty_card_id')
                ->references('id')
                ->on('loyalty_cards')
                ->nullOnDelete();
            $table->foreign('order_id')
                ->references('id')
                ->on('orders')
                ->nullOnDelete();
            $table->foreign('actor_user_id')
                ->references('id')
                ->on('users')
                ->nullOnDelete();

            $table->index(['customer_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('loyalty_point_logs');
    }
};
