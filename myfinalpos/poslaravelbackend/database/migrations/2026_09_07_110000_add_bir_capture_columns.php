<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Point-of-sale capture required for a BIR-valid Z reading.
 *
 * A Z reading must break sales into VATable / VAT-exempt / zero-rated and
 * report senior-citizen, PWD, NAAC and solo-parent discounts separately. None
 * of that could be derived from what was stored: orders had one flat `vat`
 * column and generic discount columns.
 *
 * The split is captured ON THE ORDER at checkout rather than recomputed later
 * from product flags. A reclassified product must not retroactively change a
 * filed reading — the figures have to stay as they were rung up.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table) {
            if (! Schema::hasColumn('products', 'vat_classification')) {
                // vatable | vat_exempt | zero_rated
                $table->string('vat_classification', 20)
                    ->default('vatable')
                    ->after('price');
            }
        });

        Schema::table('orders', function (Blueprint $table) {
            // Statutory discounts, each reported on its own Z line.
            foreach ([
                'sc_discount',
                'pwd_discount',
                'naac_discount',
                'solo_parent_discount',
            ] as $column) {
                if (! Schema::hasColumn('orders', $column)) {
                    $table->decimal($column, 12, 2)->default(0);
                }
            }

            // Who the statutory discount was granted to. BIR requires the
            // cardholder's name and ID number to be recorded against the sale.
            if (! Schema::hasColumn('orders', 'statutory_discount_type')) {
                $table->string('statutory_discount_type', 20)->nullable();
            }
            if (! Schema::hasColumn('orders', 'statutory_id_number')) {
                $table->string('statutory_id_number', 60)->nullable();
            }
            if (! Schema::hasColumn('orders', 'statutory_customer_name')) {
                $table->string('statutory_customer_name', 160)->nullable();
            }

            // VAT classification of the sale as rung up.
            foreach ([
                'vatable_sales',
                'vat_exempt_sales',
                'zero_rated_sales',
            ] as $column) {
                if (! Schema::hasColumn('orders', $column)) {
                    $table->decimal($column, 12, 2)->default(0);
                }
            }
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            foreach ([
                'sc_discount',
                'pwd_discount',
                'naac_discount',
                'solo_parent_discount',
                'statutory_discount_type',
                'statutory_id_number',
                'statutory_customer_name',
                'vatable_sales',
                'vat_exempt_sales',
                'zero_rated_sales',
            ] as $column) {
                if (Schema::hasColumn('orders', $column)) {
                    $table->dropColumn($column);
                }
            }
        });

        Schema::table('products', function (Blueprint $table) {
            if (Schema::hasColumn('products', 'vat_classification')) {
                $table->dropColumn('vat_classification');
            }
        });
    }
};
