<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('users')) {
            return;
        }

        DB::table('users')
            ->whereIn('role', ['super_admin', 'superadmin', 'manager'])
            ->update(['role' => 'admin']);

        DB::table('users')
            ->where('role', 'like', '%admin%')
            ->whereNotIn('role', ['admin', 'cashier', 'labor'])
            ->update(['role' => 'admin']);

        DB::table('users')
            ->where('role', 'like', '%manager%')
            ->update(['role' => 'admin']);
    }

    public function down(): void
    {
        // Roles are not restored to legacy values.
    }
};
