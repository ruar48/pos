<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('drawer_expenses', function (Blueprint $table) {
            $table->string('series_no', 60)->nullable()->after('payment_type');
        });
    }

    public function down(): void
    {
        Schema::table('drawer_expenses', function (Blueprint $table) {
            $table->dropColumn('series_no');
        });
    }
};
