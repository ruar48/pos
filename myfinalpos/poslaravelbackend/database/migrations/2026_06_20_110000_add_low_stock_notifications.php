<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('app_settings')) {
            Schema::table('app_settings', function (Blueprint $table) {
                if (! Schema::hasColumn('app_settings', 'low_stock_email_enabled')) {
                    $table->boolean('low_stock_email_enabled')->default(true)->after('allow_negative_stock');
                }
                if (! Schema::hasColumn('app_settings', 'low_stock_email_recipients')) {
                    $table->string('low_stock_email_recipients', 500)->default('')->after('low_stock_email_enabled');
                }
            });
        }

        if (Schema::hasTable('products')) {
            Schema::table('products', function (Blueprint $table) {
                if (! Schema::hasColumn('products', 'low_stock_notified_at')) {
                    $table->timestamp('low_stock_notified_at')->nullable()->after('reorder_level');
                }
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('app_settings')) {
            Schema::table('app_settings', function (Blueprint $table) {
                if (Schema::hasColumn('app_settings', 'low_stock_email_recipients')) {
                    $table->dropColumn('low_stock_email_recipients');
                }
                if (Schema::hasColumn('app_settings', 'low_stock_email_enabled')) {
                    $table->dropColumn('low_stock_email_enabled');
                }
            });
        }

        if (Schema::hasTable('products')) {
            Schema::table('products', function (Blueprint $table) {
                if (Schema::hasColumn('products', 'low_stock_notified_at')) {
                    $table->dropColumn('low_stock_notified_at');
                }
            });
        }
    }
};
