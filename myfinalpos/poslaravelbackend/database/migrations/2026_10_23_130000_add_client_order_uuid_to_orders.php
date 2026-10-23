<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('orders') || Schema::hasColumn('orders', 'client_order_uuid')) {
            return;
        }

        // Tablet-generated id for each sale. A sale whose response was lost
        // (Wi-Fi drop after the server saved it) is retried from the offline
        // queue with the same id, and the server returns the existing order
        // instead of saving it twice. Nullable: older tablet builds don't
        // send it and MySQL allows any number of NULLs in a unique index.
        Schema::table('orders', function (Blueprint $table) {
            $table->string('client_order_uuid', 64)->nullable()->unique();
        });
    }

    public function down(): void
    {
        if (! Schema::hasTable('orders') || ! Schema::hasColumn('orders', 'client_order_uuid')) {
            return;
        }

        Schema::table('orders', function (Blueprint $table) {
            $table->dropUnique(['client_order_uuid']);
            $table->dropColumn('client_order_uuid');
        });
    }
};
