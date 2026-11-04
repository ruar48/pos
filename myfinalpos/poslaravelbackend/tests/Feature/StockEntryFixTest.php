<?php

use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;

// End to end through the real HTTP routes on a real MySQL schema:
// Add -> list entries -> Fix entry -> inventory report -> logs.
//
// Runs only against the scratch database `pos_e2e_test` (a schema-only clone of
// pos_db), never against real data; every test rolls back. Run it with:
//   APP_CONFIG_CACHE=/nonexistent DB_CONNECTION=mysql DB_PORT=3308 \
//   DB_DATABASE=pos_e2e_test php artisan test --filter=StockEntryFixTest
uses(DatabaseTransactions::class);

beforeEach(function () {
    if (DB::getDriverName() !== 'mysql' || DB::getDatabaseName() !== 'pos_e2e_test') {
        $this->markTestSkipped('Needs the pos_e2e_test MySQL scratch database.');
    }

    DB::table('app_settings')->delete();
    DB::table('app_settings')->insert(['id' => 1, 'cash_drawer_pin_hash' => password_hash('1234', PASSWORD_DEFAULT)]);
    DB::table('categories')->insert(['id' => 1, 'name' => 'Feeds']);
    DB::table('products')->insert(['id' => 1, 'category_id' => 1, 'name' => 'ACC Feeds 40kg', 'stock' => 12, 'price' => 100]);
    DB::table('users')->insert([
        'id' => 1, 'full_name' => 'Tester', 'username' => 'tester',
        'email' => 'tester@example.test', 'password_hash' => 'x',
    ]);

    $user = new User;
    $user->id = 1;
    $this->actingAs($user);
});

function addStock(float $delta)
{
    return test()->postJson('/pos/inventory/stock', ['product_id' => 1, 'delta' => $delta]);
}

function stockNow(): float
{
    return (float) DB::table('products')->where('id', 1)->value('stock');
}

function reportRow(): array
{
    $today = now()->toDateString();
    $json = test()->getJson("/pos/inventory/report?start={$today}&end={$today}")->assertOk()->json();
    $rows = $json['data']['rows'] ?? $json['rows'] ?? $json['data'] ?? [];

    return collect($rows)->firstWhere('product_id', 1) ?? [];
}

test('add 10 then fix the entry to 5: stock, history, report and logs all agree', function () {
    addStock(10)->assertOk();
    expect(stockNow())->toBe(22.0);

    $entries = $this->getJson('/pos/inventory/stock/entries?product_id=1')->assertOk()->json('data');
    expect($entries)->toHaveCount(1)
        ->and((float) $entries[0]['quantity_delta'])->toBe(10.0);

    $this->postJson('/pos/inventory/stock/entries/fix', [
        'entry_id' => $entries[0]['id'], 'quantity' => 5, 'reason' => 'Typo, only 5 arrived', 'pin' => '1234',
    ])->assertOk()->assertJsonPath('data.new_stock', 17);

    // Live stock moved by the difference; the single ledger row now says +5.
    expect(stockNow())->toBe(17.0);
    $rows = DB::table('stock_movements')->get();
    expect($rows)->toHaveCount(1)
        ->and((float) $rows[0]->quantity_delta)->toBe(5.0)
        ->and((float) $rows[0]->balance_after)->toBe(17.0);

    // Report: Added +5, nothing deducted, and it still balances.
    $row = reportRow();
    expect((float) $row['added'])->toBe(5.0)
        ->and((float) $row['deducted'])->toBe(0.0)
        ->and((float) $row['beginning'] + (float) $row['added'] - (float) $row['deducted'])->toBe((float) $row['ending']);

    // Both logs recorded it, with the original row kept for the audit trail.
    $audit = DB::table('audit_logs')->where('entity_type', 'stock_movement')->first();
    expect($audit->description)->toContain('Typo, only 5 arrived');
    $payload = json_decode($audit->payload_json, true);
    expect((float) $payload['previous_delta'])->toBe(10.0)
        ->and((float) $payload['new_delta'])->toBe(5.0)
        ->and((float) $payload['original_entry']['quantity_delta'])->toBe(10.0);
    expect(DB::table('user_transactions')->where('transaction_type', 'stock_entry_fix')->count())->toBe(1);
});

test('fixing to 0 removes the entry from the history and puts the stock back', function () {
    addStock(10)->assertOk();
    $id = $this->getJson('/pos/inventory/stock/entries?product_id=1')->json('data.0.id');

    $this->postJson('/pos/inventory/stock/entries/fix', [
        'entry_id' => $id, 'quantity' => 0, 'reason' => 'Added by mistake', 'pin' => '1234',
    ])->assertOk();

    expect(stockNow())->toBe(12.0)
        ->and(DB::table('stock_movements')->count())->toBe(0);

    $row = reportRow();
    expect((float) $row['added'])->toBe(0.0)->and((float) $row['deducted'])->toBe(0.0);
    expect(DB::table('audit_logs')->where('entity_type', 'stock_movement')->count())->toBe(1);
});

test('fixing an older entry shifts the running balance of the later ones', function () {
    addStock(10)->assertOk();   // 12 -> 22
    addStock(3)->assertOk();    // 22 -> 25
    $first = DB::table('stock_movements')->orderBy('id')->first();

    $this->postJson('/pos/inventory/stock/entries/fix', [
        'entry_id' => $first->id, 'quantity' => 5, 'reason' => 'Typo', 'pin' => '1234',
    ])->assertOk();

    $balances = DB::table('stock_movements')->orderBy('id')->pluck('balance_after')->map(fn ($b) => (float) $b)->all();
    expect($balances)->toBe([17.0, 20.0])
        ->and(stockNow())->toBe(20.0);
});

test('wrong PIN or a missing reason changes nothing', function () {
    addStock(10)->assertOk();
    $id = $this->getJson('/pos/inventory/stock/entries?product_id=1')->json('data.0.id');

    $this->postJson('/pos/inventory/stock/entries/fix', [
        'entry_id' => $id, 'quantity' => 5, 'reason' => 'x', 'pin' => '9999',
    ])->assertStatus(422)->assertJsonPath('message', 'Invalid or missing cash drawer PIN');

    $this->postJson('/pos/inventory/stock/entries/fix', [
        'entry_id' => $id, 'quantity' => 5, 'reason' => '  ', 'pin' => '1234',
    ])->assertStatus(422)->assertJsonPath('message', 'A reason is required');

    expect(stockNow())->toBe(22.0)
        ->and((float) DB::table('stock_movements')->value('quantity_delta'))->toBe(10.0)
        ->and(DB::table('audit_logs')->where('entity_type', 'stock_movement')->count())->toBe(0);
});

test('an Update (exact count) is hidden from Added/Deducted, not editable, and still logged', function () {
    $this->postJson('/pos/inventory/stock/update', [
        'product_id' => 1, 'stock' => 20, 'reason' => 'Physical count', 'pin' => '1234',
    ])->assertOk();

    expect($this->getJson('/pos/inventory/stock/entries?product_id=1')->assertOk()->json('data'))->toBe([]);

    $row = reportRow();
    expect((float) $row['added'])->toBe(0.0)
        ->and((float) $row['deducted'])->toBe(0.0)
        ->and((float) $row['ending'])->toBe(20.0)
        ->and((float) $row['beginning'])->toBe(20.0);

    expect(DB::table('audit_logs')->where('module', 'inventory')->count())->toBe(1);
    expect(DB::table('user_transactions')->where('transaction_type', 'stock_update')->count())->toBe(1);
});

test('a normal Add still shows in Added', function () {
    addStock(10)->assertOk();

    $row = reportRow();
    expect((float) $row['added'])->toBe(10.0)
        ->and((float) $row['beginning'])->toBe(12.0)
        ->and((float) $row['ending'])->toBe(22.0);
});

test('a fix may take stock below zero (part of it was already sold)', function () {
    addStock(10)->assertOk();
    DB::table('products')->where('id', 1)->update(['stock' => 7]);
    $id = $this->getJson('/pos/inventory/stock/entries?product_id=1')->json('data.0.id');

    $this->postJson('/pos/inventory/stock/entries/fix', [
        'entry_id' => $id, 'quantity' => 0, 'reason' => 'Added by mistake', 'pin' => '1234',
    ])->assertOk();

    expect(stockNow())->toBe(-3.0)
        ->and(DB::table('stock_movements')->count())->toBe(0);
});

test('an item already at -10 can still be added to, but not pushed lower', function () {
    DB::table('products')->where('id', 1)->update(['stock' => -10]);
    DB::table('app_settings')->update(['allow_negative_stock' => 0]);

    addStock(5)->assertOk();
    expect(stockNow())->toBe(-5.0);

    addStock(-3)->assertStatus(400);
    expect(stockNow())->toBe(-5.0);

    // Fixing the +5 entry up to +8 also raises stock, so it is allowed too.
    $id = $this->getJson('/pos/inventory/stock/entries?product_id=1')->json('data.0.id');
    $this->postJson('/pos/inventory/stock/entries/fix', [
        'entry_id' => $id, 'quantity' => 8, 'reason' => 'Typo', 'pin' => '1234',
    ])->assertOk();
    expect(stockNow())->toBe(-2.0);
});

test('an Update may set a negative exact count', function () {
    $this->postJson('/pos/inventory/stock/update', [
        'product_id' => 1, 'stock' => -4, 'reason' => 'Count after oversell', 'pin' => '1234',
    ])->assertOk()->assertJsonPath('data.new_stock', -4);

    expect(stockNow())->toBe(-4.0);
});

test('Remove below zero follows the negative-stock setting', function () {
    // OFF: blocked, stock unchanged.
    DB::table('app_settings')->update(['allow_negative_stock' => 0]);
    addStock(-15)->assertStatus(400);
    expect(stockNow())->toBe(12.0);

    // ON: allowed, goes negative and is logged.
    DB::table('app_settings')->update(['allow_negative_stock' => 1]);
    addStock(-15)->assertOk();
    expect(stockNow())->toBe(-3.0)
        ->and((float) DB::table('stock_movements')->value('quantity_delta'))->toBe(-15.0);
});
