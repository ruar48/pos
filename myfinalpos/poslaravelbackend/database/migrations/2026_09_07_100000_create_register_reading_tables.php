<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * X reading / Z reading support (BIR).
 *
 * Three pieces:
 *  - orders gain a terminal + session link, so a reading can be scoped to one
 *    register's shift. Until now `pos_terminal_id` lived only in app settings
 *    for the live monitor and was never persisted on a sale.
 *  - pos_terminal_counters holds the accumulators BIR requires to be
 *    monotonic: the grand total that must never reset, the Z counter, and the
 *    reset counter. One row per terminal.
 *  - pos_register_sessions / pos_register_readings record each shift and each
 *    reading taken from it.
 *
 * Columns exist here for the SC/PWD/NAAC/Solo-Parent and VAT-classification
 * figures BIR requires. They are written as 0 until the point of sale captures
 * those classifications — see RegisterReadingService::UNCAPTURED_BIR_FIELDS,
 * which reports them as unavailable rather than as a truthful zero.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            if (! Schema::hasColumn('orders', 'terminal_id')) {
                $table->string('terminal_id', 60)->nullable()->index();
            }
            if (! Schema::hasColumn('orders', 'register_session_id')) {
                $table->unsignedInteger('register_session_id')
                    ->nullable()
                    ->index();
            }
        });

        Schema::create('pos_terminal_counters', function (Blueprint $table) {
            $table->increments('id');
            $table->string('terminal_id', 60)->unique();

            // Never reset, never decremented. Every completed sale adds to it.
            $table->decimal('grand_total_accumulated', 16, 2)->default(0);

            $table->unsignedInteger('z_counter')->default(0);
            $table->unsignedInteger('reset_counter')->default(0);
            $table->timestamp('last_z_at')->nullable();
            $table->timestamps();
        });

        Schema::create('pos_register_sessions', function (Blueprint $table) {
            $table->increments('id');
            $table->string('terminal_id', 60)->index();
            $table->unsignedInteger('branch_id')->nullable();
            $table->unsignedInteger('cashier_user_id')->nullable();
            $table->date('business_date')->index();
            $table->decimal('opening_cash', 12, 2)->default(0);
            $table->timestamp('opened_at')->useCurrent();
            $table->timestamp('closed_at')->nullable();

            // 'open' | 'closed'. A terminal may only have one open session,
            // enforced in RegisterSessionService rather than by a partial
            // index, which MySQL does not support.
            $table->string('status', 20)->default('open')->index();
            $table->timestamps();
        });

        Schema::create('pos_register_readings', function (Blueprint $table) {
            $table->increments('id');
            $table->string('terminal_id', 60)->index();
            $table->unsignedInteger('register_session_id')->nullable()->index();

            // 'x' = interim, does not close. 'z' = end of shift, closes and
            // increments the Z counter.
            $table->string('type', 1);

            $table->unsignedInteger('z_counter')->nullable();
            $table->unsignedInteger('reset_counter')->default(0);
            $table->date('business_date')->index();
            $table->unsignedInteger('taken_by_user_id')->nullable();

            $table->timestamp('covers_from')->nullable();
            $table->timestamp('covers_to')->nullable();

            // Sales invoice range for the period.
            $table->string('beginning_or', 40)->nullable();
            $table->string('ending_or', 40)->nullable();

            // BIR's "old" and "new" accumulated grand totals.
            $table->decimal('beginning_grand_total', 16, 2)->default(0);
            $table->decimal('ending_grand_total', 16, 2)->default(0);

            $table->decimal('gross_sales', 14, 2)->default(0);
            $table->decimal('net_sales', 14, 2)->default(0);

            // VAT classification.
            $table->decimal('vatable_sales', 14, 2)->default(0);
            $table->decimal('vat_amount', 14, 2)->default(0);
            $table->decimal('vat_exempt_sales', 14, 2)->default(0);
            $table->decimal('zero_rated_sales', 14, 2)->default(0);

            // Statutory discounts. Zero until captured at point of sale.
            $table->decimal('sc_discount', 14, 2)->default(0);
            $table->decimal('pwd_discount', 14, 2)->default(0);
            $table->decimal('naac_discount', 14, 2)->default(0);
            $table->decimal('solo_parent_discount', 14, 2)->default(0);
            $table->decimal('other_discount', 14, 2)->default(0);
            $table->decimal('discount_total', 14, 2)->default(0);

            $table->decimal('refund_amount', 14, 2)->default(0);
            $table->unsignedInteger('refund_count')->default(0);
            $table->decimal('void_amount', 14, 2)->default(0);
            $table->unsignedInteger('void_count')->default(0);

            $table->unsignedInteger('transaction_count')->default(0);

            // {"Cash": 1200.00, "GCash": 300.00}
            $table->json('payment_breakdown')->nullable();

            // Which BIR figures this reading could not source from captured
            // data, so a printed copy can say so instead of implying zero.
            $table->json('uncaptured_fields')->nullable();

            $table->timestamp('created_at')->useCurrent();

            $table->index(['terminal_id', 'type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pos_register_readings');
        Schema::dropIfExists('pos_register_sessions');
        Schema::dropIfExists('pos_terminal_counters');

        Schema::table('orders', function (Blueprint $table) {
            if (Schema::hasColumn('orders', 'register_session_id')) {
                $table->dropColumn('register_session_id');
            }
            if (Schema::hasColumn('orders', 'terminal_id')) {
                $table->dropColumn('terminal_id');
            }
        });
    }
};
