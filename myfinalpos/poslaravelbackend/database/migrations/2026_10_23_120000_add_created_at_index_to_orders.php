<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('orders')) {
            return;
        }

        // get_orders.php, the transaction report and every sales summary
        // filter orders by a created_at range; without this index each of
        // them scanned the whole orders table.
        $hasIndex = collect(Schema::getIndexes('orders'))
            ->contains(fn (array $index) => $index['columns'] === ['created_at']);

        if (! $hasIndex) {
            Schema::table('orders', function (Blueprint $table) {
                $table->index('created_at');
            });
        }
    }

    public function down(): void
    {
        if (! Schema::hasTable('orders')) {
            return;
        }

        $hasIndex = collect(Schema::getIndexes('orders'))
            ->contains(fn (array $index) => $index['columns'] === ['created_at']);

        if ($hasIndex) {
            Schema::table('orders', function (Blueprint $table) {
                $table->dropIndex(['created_at']);
            });
        }
    }
};
