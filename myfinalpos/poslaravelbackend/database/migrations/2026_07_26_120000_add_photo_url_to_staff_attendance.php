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

        if (! Schema::hasColumn('staff_attendance', 'photo_url')) {
            Schema::table('staff_attendance', function (Blueprint $table) {
                $table->string('photo_url', 500)->nullable()->after('face_verified');
            });
        }
    }

    public function down(): void
    {
        if (! Schema::hasTable('staff_attendance')) {
            return;
        }

        if (Schema::hasColumn('staff_attendance', 'photo_url')) {
            Schema::table('staff_attendance', function (Blueprint $table) {
                $table->dropColumn('photo_url');
            });
        }
    }
};
