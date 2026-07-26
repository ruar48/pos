<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('drawer_expenses', function (Blueprint $table) {
            $table->string('reference_no', 32)->nullable()->after('payment_type');
        });

        if (! Schema::hasTable('drawer_expenses') || ! Schema::hasTable('cash_drawer_sessions')) {
            return;
        }

        $sessions = DB::table('cash_drawer_sessions')
            ->select('id', 'business_date')
            ->orderBy('id')
            ->get();

        foreach ($sessions as $session) {
            $expenseIds = DB::table('drawer_expenses')
                ->where('session_id', $session->id)
                ->orderBy('id')
                ->pluck('id');

            $sequence = 1;
            foreach ($expenseIds as $expenseId) {
                DB::table('drawer_expenses')
                    ->where('id', $expenseId)
                    ->update([
                        'reference_no' => sprintf(
                            '%s-%03d',
                            $session->business_date,
                            $sequence,
                        ),
                    ]);
                $sequence++;
            }
        }
    }

    public function down(): void
    {
        Schema::table('drawer_expenses', function (Blueprint $table) {
            $table->dropColumn('reference_no');
        });
    }
};
