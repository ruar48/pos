<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('loyalty_cards', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('customer_id');
            $table->string('card_number', 40)->unique();
            $table->string('nfc_uid', 64)->nullable()->unique();
            $table->integer('points')->default(0);
            $table->string('tier', 30)->default('Bronze');
            $table->string('status', 20)->default('Active');
            $table->timestamp('created_at')->useCurrent();
            $table->timestamp('updated_at')->useCurrent()->useCurrentOnUpdate();

            $table->foreign('customer_id')
                ->references('id')
                ->on('customers')
                ->cascadeOnDelete();
        });

        Schema::create('app_settings', function (Blueprint $table) {
            $table->increments('id');
            $table->decimal('tax_rate', 8, 4)->default(0.12);
            $table->boolean('auto_print_receipt')->default(true);
            $table->boolean('double_print_receipt')->default(false);
            $table->string('printer_host', 120)->default('');
            $table->string('printer_type', 20)->default('network');
            $table->string('printer_device', 255)->default('');
            $table->unsignedSmallInteger('printer_port')->default(9100);
            $table->boolean('allow_negative_stock')->default(false);
            $table->boolean('loyalty_enabled')->default(true);
            $table->unsignedInteger('loyalty_points_per_unit')->default(50);
            $table->decimal('loyalty_spend_unit', 12, 2)->default(1000);
            $table->unsignedInteger('loyalty_redeem_points_per_peso')->default(10);
            $table->string('currency_symbol', 10)->default('PHP');
            $table->string('settings_pin', 10)->default('1234');
            $table->json('receipt_store_json')->nullable();
            $table->unsignedInteger('default_branch_id')->nullable();
            $table->string('attendance_start_time', 5)->default('08:00');
            $table->unsignedSmallInteger('attendance_grace_minutes')->default(15);
            $table->string('attendance_lunch_out_time', 5)->default('12:00');
            $table->string('attendance_afternoon_in_time', 5)->default('13:00');
            $table->string('attendance_day_end_time', 5)->default('17:00');
            $table->string('attendance_morning_absent_after_time', 5)->default('09:00');
            $table->unsignedInteger('updated_by')->nullable();
            $table->timestamp('created_at')->useCurrent();
            $table->timestamp('updated_at')->useCurrent()->useCurrentOnUpdate();

            $table->foreign('updated_by')
                ->references('id')
                ->on('users')
                ->nullOnDelete();
        });

        Schema::create('audit_logs', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->unsignedInteger('user_id')->nullable();
            $table->string('action', 50);
            $table->string('module', 80);
            $table->string('entity_type', 80);
            $table->unsignedInteger('entity_id')->nullable();
            $table->string('description', 255);
            $table->longText('payload_json')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['user_id', 'created_at']);
            $table->index(['module', 'created_at']);

            $table->foreign('user_id')
                ->references('id')
                ->on('users')
                ->nullOnDelete();
        });

        Schema::create('user_transactions', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->unsignedInteger('user_id')->nullable();
            $table->string('transaction_type', 60);
            $table->string('reference_table', 80);
            $table->unsignedInteger('reference_id')->nullable();
            $table->decimal('amount', 12, 2)->default(0);
            $table->string('notes', 255)->default('');
            $table->longText('payload_json')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['user_id', 'created_at']);

            $table->foreign('user_id')
                ->references('id')
                ->on('users')
                ->nullOnDelete();
        });

        Schema::create('coupons', function (Blueprint $table) {
            $table->increments('id');
            $table->string('code', 100)->unique();
            $table->string('description', 255)->nullable();
            $table->enum('discount_type', ['percentage', 'fixed'])->default('fixed');
            $table->decimal('discount_value', 12, 2)->default(0);
            $table->decimal('min_order_amount', 12, 2)->default(0);
            $table->date('start_date');
            $table->date('end_date');
            $table->unsignedInteger('max_uses')->nullable();
            $table->unsignedInteger('usage_count')->default(0);
            $table->unsignedTinyInteger('status')->default(1);
            $table->timestamp('created_at')->useCurrent();
        });

        Schema::create('staff_payments', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('user_id');
            $table->unsignedInteger('branch_id')->nullable();
            $table->decimal('amount', 10, 2);
            $table->enum('payment_type', ['salary', 'commission', 'bonus', 'allowance'])->default('salary');
            $table->date('period_start')->nullable();
            $table->date('period_end')->nullable();
            $table->string('notes', 255)->nullable();
            $table->unsignedInteger('paid_by_user_id')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index('user_id');
            $table->index('branch_id');
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_payments');
        Schema::dropIfExists('coupons');
        Schema::dropIfExists('user_transactions');
        Schema::dropIfExists('audit_logs');
        Schema::dropIfExists('app_settings');
        Schema::dropIfExists('loyalty_cards');
    }
};
