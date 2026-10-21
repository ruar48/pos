<?php

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// Only the tables this endpoint touches; the full migration set does not run
// on SQLite (remove_product_sku_and_barcode fails on its unique index).
beforeEach(function () {
    Schema::create('app_settings', function (Blueprint $table) {
        $table->increments('id');
        $table->string('cash_drawer_pin_hash')->nullable();
    });
    Schema::create('products', function (Blueprint $table) {
        $table->increments('id');
        $table->string('name');
        $table->decimal('stock', 12, 3)->default(0);
        $table->integer('reorder_level')->default(0);
        $table->string('status')->default('active');
        $table->timestamp('updated_at')->nullable();
    });
    Schema::create('product_varieties', function (Blueprint $table) {
        $table->increments('id');
        $table->unsignedInteger('product_id');
        $table->string('name');
        $table->integer('stock')->default(0);
    });
    Schema::create('stock_movements', function (Blueprint $table) {
        $table->increments('id');
        $table->unsignedInteger('product_id');
        $table->unsignedInteger('variety_id')->nullable();
        $table->string('type');
        $table->decimal('quantity_delta', 12, 3);
        $table->decimal('balance_after', 12, 3)->nullable();
        $table->string('reference_type')->nullable();
        $table->unsignedInteger('reference_id')->nullable();
        $table->string('note')->nullable();
        $table->unsignedInteger('user_id')->nullable();
        $table->timestamp('created_at')->nullable();
    });

    DB::table('app_settings')->insert(['id' => 1, 'cash_drawer_pin_hash' => password_hash('1234', PASSWORD_DEFAULT)]);
    DB::table('products')->insert(['id' => 1, 'name' => 'ACC Feeds 40kg', 'stock' => 10]);
    DB::table('products')->insert(['id' => 2, 'name' => 'Super Pinoy', 'stock' => 15]);
    DB::table('product_varieties')->insert(['id' => 7, 'product_id' => 2, 'name' => '400 GRAMS', 'stock' => 5]);

    $user = new User;
    $user->id = 1;
    $this->actingAs($user);
});

test('update sets the exact stock and logs the reason when the PIN is right', function () {
    $this->postJson('/pos/inventory/stock/update', [
        'product_id' => 1, 'stock' => 20, 'reason' => 'Physical count', 'pin' => '1234',
    ])->assertOk()->assertJsonPath('data.new_stock', 20);

    expect((float) DB::table('products')->where('id', 1)->value('stock'))->toBe(20.0);

    $movement = DB::table('stock_movements')->first();
    expect((float) $movement->quantity_delta)->toBe(10.0)
        ->and($movement->note)->toBe('Stock update: Physical count');
});

test('a size update sets the size and moves the product total by the same amount', function () {
    $this->postJson('/pos/inventory/stock/update', [
        'product_id' => 2, 'variety_id' => 7, 'stock' => 8, 'reason' => 'Recount', 'pin' => '1234',
    ])->assertOk();

    expect((int) DB::table('product_varieties')->where('id', 7)->value('stock'))->toBe(8)
        ->and((float) DB::table('products')->where('id', 2)->value('stock'))->toBe(18.0);
});

test('wrong PIN or missing reason leaves stock unchanged', function () {
    $this->postJson('/pos/inventory/stock/update', [
        'product_id' => 1, 'stock' => 20, 'reason' => 'Physical count', 'pin' => '9999',
    ])->assertStatus(422)->assertJsonPath('message', 'Invalid or missing cash drawer PIN');

    $this->postJson('/pos/inventory/stock/update', [
        'product_id' => 1, 'stock' => 20, 'reason' => '  ', 'pin' => '1234',
    ])->assertStatus(422)->assertJsonPath('message', 'A reason is required');

    expect((float) DB::table('products')->where('id', 1)->value('stock'))->toBe(10.0)
        ->and(DB::table('stock_movements')->count())->toBe(0);
});
