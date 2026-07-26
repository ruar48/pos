<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('product_price_history', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('product_id');
            $table->unsignedInteger('variety_id')->nullable();
            $table->decimal('unit_cost', 12, 2)->default(0);
            $table->decimal('unit_price', 12, 2)->default(0);
            $table->timestamp('effective_from');

            $table->index(['product_id', 'variety_id', 'effective_from']);
            $table->foreign('product_id')
                ->references('id')
                ->on('products')
                ->cascadeOnDelete();
        });

        $this->backfill();
    }

    private function backfill(): void
    {
        if (! Schema::hasTable('products')) {
            return;
        }

        $now = now();

        foreach (DB::table('products')->where('status', 'active')->get() as $p) {
            DB::table('product_price_history')->insert([
                'product_id' => $p->id,
                'variety_id' => null,
                'unit_cost' => (float) ($p->cost_price ?? 0),
                'unit_price' => (float) ($p->price ?? 0),
                'effective_from' => $p->updated_at ?? $p->created_at ?? $now,
            ]);
        }

        if (! Schema::hasTable('product_varieties')) {
            return;
        }

        foreach (DB::table('product_varieties')->where('status', 'active')->get() as $v) {
            DB::table('product_price_history')->insert([
                'product_id' => $v->product_id,
                'variety_id' => $v->id,
                'unit_cost' => (float) ($v->cost_price ?? 0),
                'unit_price' => (float) ($v->price ?? 0),
                'effective_from' => $v->updated_at ?? $v->created_at ?? $now,
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('product_price_history');
    }
};
