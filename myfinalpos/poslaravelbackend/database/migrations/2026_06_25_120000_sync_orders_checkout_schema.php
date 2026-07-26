<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Bring legacy/imported order tables in line with checkout API expectations.
 * Fixes MySQL 1364 "doesn't have a default value" on tablet checkout.
 */
return new class extends Migration
{
    public function up(): void
    {
        $this->syncOrdersTable();
        $this->syncOrderItemsTable();
        $this->fixAutoIncrement('orders');
        $this->fixAutoIncrement('order_items');
    }

    public function down(): void
    {
        // Non-destructive sync only.
    }

    private function syncOrdersTable(): void
    {
        if (! Schema::hasTable('orders')) {
            return;
        }

        Schema::table('orders', function (Blueprint $table) {
            if (! Schema::hasColumn('orders', 'branch_id')) {
                $table->unsignedInteger('branch_id')->nullable()->default(1);
            }
            if (! Schema::hasColumn('orders', 'cashier_user_id')) {
                $table->unsignedInteger('cashier_user_id')->nullable();
            }
            if (! Schema::hasColumn('orders', 'refunded_amount')) {
                $table->decimal('refunded_amount', 12, 2)->default(0);
            }
            if (! Schema::hasColumn('orders', 'discount_amount')) {
                $table->decimal('discount_amount', 12, 2)->default(0);
            }
            if (! Schema::hasColumn('orders', 'coupon_discount')) {
                $table->decimal('coupon_discount', 12, 2)->default(0);
            }
            if (! Schema::hasColumn('orders', 'loyalty_discount')) {
                $table->decimal('loyalty_discount', 12, 2)->default(0);
            }
            if (! Schema::hasColumn('orders', 'loyalty_points_redeemed')) {
                $table->integer('loyalty_points_redeemed')->default(0);
            }
            if (! Schema::hasColumn('orders', 'receipt_note')) {
                $table->string('receipt_note', 240)->nullable();
            }
            if (! Schema::hasColumn('orders', 'status')) {
                $table->string('status', 30)->default('completed');
            }
            if (! Schema::hasColumn('orders', 'client_change')) {
                $table->decimal('client_change', 12, 2)->default(0);
            }
            if (! Schema::hasColumn('orders', 'payment_method')) {
                $table->string('payment_method', 50)->default('Cash');
            }
            if (! Schema::hasColumn('orders', 'reference')) {
                $table->string('reference', 255)->nullable();
            }
        });

        if (Schema::hasColumn('orders', 'created_at')) {
            DB::statement(
                'ALTER TABLE orders MODIFY created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP',
            );
        }
    }

    private function syncOrderItemsTable(): void
    {
        if (! Schema::hasTable('order_items')) {
            return;
        }

        Schema::table('order_items', function (Blueprint $table) {
            if (! Schema::hasColumn('order_items', 'variety_id')) {
                $table->unsignedInteger('variety_id')->nullable();
            }
            if (! Schema::hasColumn('order_items', 'variety_name')) {
                $table->string('variety_name', 255)->nullable();
            }
            if (! Schema::hasColumn('order_items', 'unit_cost')) {
                $table->decimal('unit_cost', 12, 2)->nullable();
            }
            if (! Schema::hasColumn('order_items', 'refunded_quantity')) {
                $table->integer('refunded_quantity')->default(0);
            }
            if (! Schema::hasColumn('order_items', 'created_at')) {
                $table->timestamp('created_at')->nullable()->useCurrent();
            }
        });

        if (Schema::hasColumn('order_items', 'created_at')) {
            DB::statement(
                'ALTER TABLE order_items MODIFY created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP',
            );
        }
    }

    private function fixAutoIncrement(string $table): void
    {
        if (! Schema::hasTable($table) || ! Schema::hasColumn($table, 'id')) {
            return;
        }

        $column = DB::selectOne(
            'SELECT COLUMN_TYPE, EXTRA
             FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE()
               AND TABLE_NAME = ?
               AND COLUMN_NAME = ?',
            [$table, 'id'],
        );

        if ($column === null) {
            return;
        }

        $extra = strtolower((string) ($column->EXTRA ?? ''));
        if (str_contains($extra, 'auto_increment')) {
            return;
        }

        $primaryOnId = DB::selectOne(
            'SELECT COUNT(*) AS c
             FROM information_schema.statistics
             WHERE table_schema = DATABASE()
               AND table_name = ?
               AND index_name = ?
               AND column_name = ?',
            [$table, 'PRIMARY', 'id'],
        );

        if ((int) ($primaryOnId->c ?? 0) === 0) {
            DB::statement("ALTER TABLE {$table} ADD PRIMARY KEY (id)");
        }

        // Keep the existing column type so foreign keys that reference this id stay valid.
        $columnType = (string) $column->COLUMN_TYPE;
        DB::statement(
            "ALTER TABLE {$table} MODIFY id {$columnType} NOT NULL AUTO_INCREMENT",
        );
    }
};
