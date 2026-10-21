<?php

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// Only the tables this endpoint reads; the full migration set does not run
// on SQLite (remove_product_sku_and_barcode fails on its unique index).
beforeEach(function () {
    Schema::create('users', function (Blueprint $table) {
        $table->increments('id');
        $table->string('full_name')->nullable();
    });
    Schema::create('customers', function (Blueprint $table) {
        $table->increments('id');
        $table->string('customer_name');
    });
    Schema::create('loyalty_point_logs', function (Blueprint $table) {
        $table->bigIncrements('id');
        $table->unsignedInteger('customer_id');
        $table->unsignedInteger('loyalty_card_id')->nullable();
        $table->unsignedInteger('order_id')->nullable();
        $table->string('action', 30);
        $table->integer('points_change');
        $table->integer('points_balance_after')->default(0);
        $table->decimal('order_amount', 12, 2)->nullable();
        $table->string('description');
        $table->unsignedInteger('actor_user_id')->nullable();
        $table->timestamp('created_at')->useCurrent();
    });
});

function loyaltyAdmin(): User
{
    $user = new User;
    $user->id = 1;

    return $user;
}

function seedLoyaltyActivity(): void
{
    $juan = DB::table('customers')->insertGetId(['customer_name' => 'Juan Farmer']);
    $maria = DB::table('customers')->insertGetId(['customer_name' => 'Maria Grower']);

    DB::table('loyalty_point_logs')->insert([
        ['customer_id' => $juan, 'order_id' => 12, 'action' => 'earn', 'points_change' => 50,
            'points_balance_after' => 50, 'description' => 'Earned', 'created_at' => '2026-10-01 09:00:00'],
        ['customer_id' => $juan, 'order_id' => 15, 'action' => 'redeem', 'points_change' => -30,
            'points_balance_after' => 20, 'description' => 'Redeemed', 'created_at' => '2026-10-05 10:00:00'],
        ['customer_id' => $maria, 'order_id' => null, 'action' => 'open_card', 'points_change' => 0,
            'points_balance_after' => 0, 'description' => 'Opened', 'created_at' => '2026-10-06 11:00:00'],
    ]);
}

test('admin sees every customer\'s point movements with totals', function () {
    seedLoyaltyActivity();
    $this->actingAs(loyaltyAdmin());

    $response = $this->getJson('/pos/loyalty/activity')->assertOk();

    expect($response->json('data'))->toHaveCount(3)
        ->and($response->json('data.0.customer_name'))->toBe('Maria Grower')
        ->and($response->json('data.1.receipt_number'))->toBe('RCP-000015')
        ->and($response->json('totals'))->toBe([
            'earned' => 50, 'redeemed' => 30, 'earn_count' => 1, 'redeem_count' => 1,
        ]);
});

test('activity filters by type, customer and date', function () {
    seedLoyaltyActivity();
    $this->actingAs(loyaltyAdmin());

    $redeemed = $this->getJson('/pos/loyalty/activity?action=redeem')->json('data');
    expect($redeemed)->toHaveCount(1)
        ->and($redeemed[0]['points_change'])->toBe(-30);

    expect($this->getJson('/pos/loyalty/activity?q=maria')->json('data'))->toHaveCount(1);

    $ranged = $this->getJson('/pos/loyalty/activity?from=2026-10-01&to=2026-10-01');
    expect($ranged->json('data'))->toHaveCount(1)
        ->and($ranged->json('totals.redeemed'))->toBe(0);
});

test('guests cannot read loyalty activity', function () {
    $this->getJson('/pos/loyalty/activity')->assertUnauthorized();
});

test('excel download lists the filtered activity with Sep 5, 2026 style dates', function () {
    seedLoyaltyActivity();
    $this->actingAs(loyaltyAdmin());

    $response = $this->get('/pos/loyalty/activity/export?action=redeem&from=2026-10-01&to=2026-10-31')
        ->assertOk()
        ->assertHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

    $path = tempnam(sys_get_temp_dir(), 'xlsx');
    file_put_contents($path, $response->streamedContent());
    $sheet = \PhpOffice\PhpSpreadsheet\IOFactory::load($path)->getActiveSheet();
    unlink($path);

    expect($sheet->getCell('A2')->getValue())->toBe('Period: Oct 1, 2026 to Oct 31, 2026')
        ->and($sheet->rangeToArray('A6:H6')[0])->toBe([
            'Oct 5, 2026', '10:00 AM', 'Juan Farmer', 'Redeemed', '-30', '20', 'RCP-000015', null,
        ])
        ->and($sheet->getCell('E6')->getValue())->toBe(-30)
        ->and($sheet->getCell('A7')->getValue())->toBeNull();
});
