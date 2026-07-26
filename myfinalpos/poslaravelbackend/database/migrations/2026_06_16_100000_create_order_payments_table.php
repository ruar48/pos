<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('order_payments')) {
            return;
        }

        Schema::create('order_payments', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('order_id');
            $table->string('payment_method', 50);
            $table->decimal('amount', 12, 2);
            $table->string('reference', 255)->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->foreign('order_id')
                ->references('id')
                ->on('orders')
                ->cascadeOnDelete();

            $table->index('order_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_payments');
    }
};
