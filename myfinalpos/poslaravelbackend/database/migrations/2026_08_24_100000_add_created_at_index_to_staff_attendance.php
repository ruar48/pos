<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('staff_attendance')) {
            return;
        }

        // Payroll/punctuality reports scan a whole date range on created_at
        // without a branch filter; the existing (user_id, created_at) and
        // (branch_id, created_at) composite indexes don't help there since
        // created_at isn't their leading column.
        $hasIndex = collect(Schema::getIndexes('staff_attendance'))
            ->contains(fn (array $index) => $index['columns'] === ['created_at']);

        if (! $hasIndex) {
            Schema::table('staff_attendance', function (Blueprint $table) {
                $table->index('created_at');
            });
        }
    }

    public function down(): void
    {
        if (! Schema::hasTable('staff_attendance')) {
            return;
        }

        $hasIndex = collect(Schema::getIndexes('staff_attendance'))
            ->contains(fn (array $index) => $index['columns'] === ['created_at']);

        if ($hasIndex) {
            Schema::table('staff_attendance', function (Blueprint $table) {
                $table->dropIndex(['created_at']);
            });
        }
    }
};
