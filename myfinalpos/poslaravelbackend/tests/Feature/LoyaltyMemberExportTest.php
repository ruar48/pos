<?php

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

beforeEach(function () {
    Schema::create('customers', function (Blueprint $table) {
        $table->increments('id');
        $table->string('customer_name');
        $table->string('table_name')->nullable();
        $table->string('order_type')->nullable();
        $table->timestamp('created_at')->nullable();
    });
    Schema::create('loyalty_cards', function (Blueprint $table) {
        $table->increments('id');
        $table->unsignedInteger('customer_id');
        $table->string('card_number');
        $table->string('nfc_uid')->nullable();
        $table->integer('points')->default(0);
        $table->string('tier')->default('Bronze');
        $table->string('status')->default('Active');
        $table->timestamps();
    });
    Schema::create('loyalty_point_logs', function (Blueprint $table) {
        $table->bigIncrements('id');
        $table->unsignedInteger('customer_id');
        $table->string('action', 30);
        $table->integer('points_change');
    });
});

test('member points excel lists each loyalty member with lifetime totals and a total row', function () {
    $juan = DB::table('customers')->insertGetId(['customer_name' => 'Juan Farmer', 'order_type' => 'Retail']);
    $maria = DB::table('customers')->insertGetId(['customer_name' => 'Maria Grower', 'order_type' => 'Retail']);
    DB::table('customers')->insert(['customer_name' => 'No Card Pedro', 'order_type' => 'Retail']);

    DB::table('loyalty_cards')->insert([
        ['customer_id' => $juan, 'card_number' => '000123', 'points' => 20],
        ['customer_id' => $maria, 'card_number' => '000456', 'points' => 100],
    ]);
    DB::table('loyalty_point_logs')->insert([
        ['customer_id' => $juan, 'action' => 'earn', 'points_change' => 50],
        ['customer_id' => $juan, 'action' => 'redeem', 'points_change' => -30],
        ['customer_id' => $maria, 'action' => 'earn', 'points_change' => 100],
    ]);

    $user = new User;
    $user->id = 1;
    $this->actingAs($user);

    $response = $this->get('/pos/loyalty/members/export')
        ->assertOk()
        ->assertHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

    $path = tempnam(sys_get_temp_dir(), 'xlsx');
    file_put_contents($path, $response->streamedContent());
    $sheet = \PhpOffice\PhpSpreadsheet\IOFactory::load($path)->getActiveSheet();
    unlink($path);

    expect($sheet->getCell('A3')->getValue())->toBe('Members: 2    Total points on file: 120')
        ->and($sheet->getCell('A6')->getValue())->toBe('Maria Grower')
        ->and($sheet->getCell('B7')->getValue())->toBe('000123')
        ->and($sheet->getCell('F7')->getValue())->toBe(20)
        ->and($sheet->getCell('G7')->getValue())->toBe(50)
        ->and($sheet->getCell('H7')->getValue())->toBe(30)
        ->and($sheet->getCell('A8')->getValue())->toBe('TOTAL')
        ->and($sheet->getCell('F8')->getCalculatedValue())->toBe(120);
});

test('guests cannot download member points', function () {
    $this->get('/pos/loyalty/members/export')->assertRedirect();
});
