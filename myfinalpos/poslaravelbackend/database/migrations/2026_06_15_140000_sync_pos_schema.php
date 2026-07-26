<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Idempotent schema sync for existing databases.
 *
 * Safe to run on any environment: only adds or adjusts columns/tables that are
 * missing. Does not drop data. Replaces many small add_* migration files.
 */
return new class extends Migration
{
    public function up(): void
    {
        $this->syncProductsTable();
        $this->syncProductVarietiesTable();
        $this->syncAppSettingsTable();
        $this->syncUsersTable();
        $this->syncOrderItemsTable();
        $this->syncLoyaltyCardsTable();
        $this->syncBranchesTable();
        $this->syncStaffAttendanceTable();
        $this->syncAutoIncrementIds();
    }

    public function down(): void
    {
        // Intentionally empty — this migration only brings older DBs up to date.
    }

    private function syncProductsTable(): void
    {
        if (! Schema::hasTable('products')) {
            return;
        }

        Schema::table('products', function (Blueprint $table) {
            if (! Schema::hasColumn('products', 'description')) {
                $table->text('description')->nullable();
            }
            if (! Schema::hasColumn('products', 'cost_price')) {
                $table->decimal('cost_price', 12, 2)->nullable();
            }
            if (! Schema::hasColumn('products', 'reorder_level')) {
                $table->integer('reorder_level')->default(5);
            }
            if (! Schema::hasColumn('products', 'barcode')) {
                $table->string('barcode', 60)->nullable()->unique();
            }
            if (! Schema::hasColumn('products', 'updated_at')) {
                $table->timestamp('updated_at')->nullable();
            }
            if (! Schema::hasColumn('products', 'option')) {
                $table->string('option', 120)->nullable();
            }
        });

        if (Schema::hasColumn('products', 'unit')) {
            DB::statement("ALTER TABLE products MODIFY unit VARCHAR(120) NOT NULL DEFAULT 'pc'");
        }

        if (Schema::hasColumn('products', 'sku')) {
            $nullable = DB::selectOne(
                'SELECT IS_NULLABLE
                 FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE()
                   AND TABLE_NAME = ?
                   AND COLUMN_NAME = ?',
                ['products', 'sku'],
            );

            if (($nullable->IS_NULLABLE ?? 'NO') === 'NO') {
                DB::statement('ALTER TABLE products MODIFY sku VARCHAR(60) NULL');
            }
        }
    }

    private function syncProductVarietiesTable(): void
    {
        if (! Schema::hasTable('product_varieties')) {
            return;
        }

        Schema::table('product_varieties', function (Blueprint $table) {
            if (! Schema::hasColumn('product_varieties', 'unit')) {
                $table->string('unit', 120)->nullable()->after('name');
            }
        });
    }

    private function syncAppSettingsTable(): void
    {
        if (! Schema::hasTable('app_settings')) {
            return;
        }

        Schema::table('app_settings', function (Blueprint $table) {
            if (! Schema::hasColumn('app_settings', 'loyalty_points_per_unit')) {
                $table->unsignedInteger('loyalty_points_per_unit')->default(50);
            }
            if (! Schema::hasColumn('app_settings', 'loyalty_spend_unit')) {
                $table->decimal('loyalty_spend_unit', 12, 2)->default(1000);
            }
            if (! Schema::hasColumn('app_settings', 'loyalty_redeem_points_per_peso')) {
                $table->unsignedInteger('loyalty_redeem_points_per_peso')->default(10);
            }
            if (! Schema::hasColumn('app_settings', 'double_print_receipt')) {
                $table->boolean('double_print_receipt')->default(false);
            }
            if (! Schema::hasColumn('app_settings', 'printer_host')) {
                $table->string('printer_host', 120)->default('');
            }
            if (! Schema::hasColumn('app_settings', 'settings_pin')) {
                $table->string('settings_pin', 10)->default('1234');
            }
            if (! Schema::hasColumn('app_settings', 'receipt_store_json')) {
                $table->json('receipt_store_json')->nullable();
            }
            if (! Schema::hasColumn('app_settings', 'default_branch_id')) {
                $table->unsignedInteger('default_branch_id')->nullable();
            }
            if (! Schema::hasColumn('app_settings', 'attendance_start_time')) {
                $table->string('attendance_start_time', 5)->default('08:00');
            }
            if (! Schema::hasColumn('app_settings', 'attendance_grace_minutes')) {
                $table->unsignedSmallInteger('attendance_grace_minutes')->default(15);
            }
            if (! Schema::hasColumn('app_settings', 'attendance_lunch_out_time')) {
                $table->string('attendance_lunch_out_time', 5)->default('12:00');
            }
            if (! Schema::hasColumn('app_settings', 'attendance_afternoon_in_time')) {
                $table->string('attendance_afternoon_in_time', 5)->default('13:00');
            }
            if (! Schema::hasColumn('app_settings', 'attendance_day_end_time')) {
                $table->string('attendance_day_end_time', 5)->default('17:00');
            }
            if (! Schema::hasColumn('app_settings', 'attendance_morning_absent_after_time')) {
                $table->string('attendance_morning_absent_after_time', 5)->default('09:00');
            }
            if (! Schema::hasColumn('app_settings', 'printer_type')) {
                $table->string('printer_type', 20)->default('network');
            }
            if (! Schema::hasColumn('app_settings', 'printer_device')) {
                $table->string('printer_device', 255)->default('');
            }
            if (! Schema::hasColumn('app_settings', 'printer_port')) {
                $table->unsignedSmallInteger('printer_port')->default(9100);
            }
        });
    }

    private function syncUsersTable(): void
    {
        if (! Schema::hasTable('users')) {
            return;
        }

        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'remember_token')) {
                $table->rememberToken()->nullable();
            }
            if (! Schema::hasColumn('users', 'email_verified_at')) {
                $table->timestamp('email_verified_at')->nullable();
            }
        });

        if (! Schema::hasTable('password_reset_tokens')) {
            Schema::create('password_reset_tokens', function (Blueprint $table) {
                $table->string('email')->primary();
                $table->string('token');
                $table->timestamp('created_at')->nullable();
            });
        }
    }

    private function syncOrderItemsTable(): void
    {
        if (! Schema::hasTable('order_items')) {
            return;
        }

        $addedUnitCost = false;

        Schema::table('order_items', function (Blueprint $table) use (&$addedUnitCost) {
            if (! Schema::hasColumn('order_items', 'variety_id')) {
                $table->unsignedInteger('variety_id')->nullable()->after('product_id');
            }
            if (! Schema::hasColumn('order_items', 'variety_name')) {
                $table->string('variety_name', 255)->nullable()->after('product_name');
            }
            if (! Schema::hasColumn('order_items', 'unit_cost')) {
                $table->decimal('unit_cost', 12, 2)->nullable()->after('price');
                $addedUnitCost = true;
            }
        });

        if ($addedUnitCost) {
            $this->backfillOrderItemUnitCost();
        }
    }

    private function backfillOrderItemUnitCost(): void
    {
        if (! Schema::hasTable('order_items') || ! Schema::hasTable('products')) {
            return;
        }

        $hasVariety = Schema::hasColumn('order_items', 'variety_id')
            && Schema::hasTable('product_varieties');

        if ($hasVariety) {
            DB::statement(
                'UPDATE order_items oi
                 LEFT JOIN product_varieties pv ON pv.id = oi.variety_id
                 LEFT JOIN products p ON p.id = oi.product_id
                 SET oi.unit_cost = COALESCE(pv.cost_price, p.cost_price, 0)
                 WHERE oi.unit_cost IS NULL',
            );

            return;
        }

        DB::statement(
            'UPDATE order_items oi
             INNER JOIN products p ON p.id = oi.product_id
             SET oi.unit_cost = COALESCE(p.cost_price, 0)
             WHERE oi.unit_cost IS NULL',
        );
    }

    private function syncLoyaltyCardsTable(): void
    {
        if (! Schema::hasTable('loyalty_cards')) {
            return;
        }

        Schema::table('loyalty_cards', function (Blueprint $table) {
            if (! Schema::hasColumn('loyalty_cards', 'nfc_uid')) {
                $table->string('nfc_uid', 64)->nullable()->unique();
            }
        });
    }

    private function syncBranchesTable(): void
    {
        if (! Schema::hasTable('branches')) {
            return;
        }

        Schema::table('branches', function (Blueprint $table) {
            if (! Schema::hasColumn('branches', 'latitude')) {
                $table->decimal('latitude', 10, 7)->nullable();
            }
            if (! Schema::hasColumn('branches', 'longitude')) {
                $table->decimal('longitude', 10, 7)->nullable();
            }
            if (! Schema::hasColumn('branches', 'geofence_radius_km')) {
                $table->decimal('geofence_radius_km', 5, 2)->default(2.0);
            }
        });

        DB::table('branches')
            ->where('id', 1)
            ->whereNull('latitude')
            ->update([
                'latitude' => 15.8065,
                'longitude' => 120.9925,
                'geofence_radius_km' => 2.0,
            ]);
    }

    private function syncStaffAttendanceTable(): void
    {
        if (Schema::hasTable('staff_attendance')) {
            return;
        }

        Schema::create('staff_attendance', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->unsignedInteger('user_id');
            $table->unsignedInteger('branch_id')->nullable();
            $table->string('event_type', 20);
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->decimal('accuracy_meters', 8, 2)->nullable();
            $table->decimal('distance_from_branch_km', 8, 3)->nullable();
            $table->boolean('within_geofence')->nullable();
            $table->boolean('face_verified')->nullable();
            $table->string('device_info', 255)->nullable();
            $table->string('notes', 255)->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['user_id', 'created_at']);
            $table->index(['branch_id', 'created_at']);
        });
    }

    private function syncAutoIncrementIds(): void
    {
        foreach ([
            'audit_logs',
            'user_transactions',
            'staff_attendance',
            'loyalty_point_logs',
            'stock_movements',
            'staff_payments',
            'orders',
            'order_items',
        ] as $table) {
            $this->fixAutoIncrement($table);
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
