<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('cash_drawer_sessions', function (Blueprint $table) {
            $table->increments('id');
            $table->date('business_date')->unique();
            $table->decimal('starting_cash', 12, 2)->default(0);
            $table->unsignedInteger('created_by_user_id')->nullable();
            $table->unsignedInteger('updated_by_user_id')->nullable();
            $table->timestamp('created_at')->useCurrent();
            $table->timestamp('updated_at')->useCurrent()->useCurrentOnUpdate();

            $table->foreign('created_by_user_id')
                ->references('id')
                ->on('users')
                ->nullOnDelete();

            $table->foreign('updated_by_user_id')
                ->references('id')
                ->on('users')
                ->nullOnDelete();
        });

        Schema::create('cash_additions', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('session_id');
            $table->decimal('amount', 12, 2);
            $table->string('remarks', 255)->default('');
            $table->unsignedInteger('created_by_user_id')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['session_id', 'created_at']);

            $table->foreign('session_id')
                ->references('id')
                ->on('cash_drawer_sessions')
                ->cascadeOnDelete();

            $table->foreign('created_by_user_id')
                ->references('id')
                ->on('users')
                ->nullOnDelete();
        });

        Schema::create('drawer_expenses', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('session_id');
            $table->string('name', 120);
            $table->decimal('amount', 12, 2);
            $table->enum('payment_type', ['cash', 'gcash', 'bank'])->default('cash');
            $table->unsignedInteger('created_by_user_id')->nullable();
            $table->unsignedInteger('updated_by_user_id')->nullable();
            $table->timestamp('created_at')->useCurrent();
            $table->timestamp('updated_at')->useCurrent()->useCurrentOnUpdate();

            $table->index(['session_id', 'payment_type', 'created_at']);

            $table->foreign('session_id')
                ->references('id')
                ->on('cash_drawer_sessions')
                ->cascadeOnDelete();

            $table->foreign('created_by_user_id')
                ->references('id')
                ->on('users')
                ->nullOnDelete();

            $table->foreign('updated_by_user_id')
                ->references('id')
                ->on('users')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('drawer_expenses');
        Schema::dropIfExists('cash_additions');
        Schema::dropIfExists('cash_drawer_sessions');
    }
};
