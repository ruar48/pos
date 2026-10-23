<?php

use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;

/*
| Server-side fixes from the full-code bug scan: sign-in tokens, PIN/login
| brute-force limits, admin-only settings and payroll, duplicate-sale
| protection, offline-sale sync, stale-stock overwrites, import field wiping,
| refund limits. Needs the MySQL POS schema; everything is rolled back.
*/

uses(DatabaseTransactions::class);

beforeEach(function () {
    if (DB::connection()->getDriverName() !== 'mysql' || ! DB::getSchemaBuilder()->hasTable('orders')) {
        $this->markTestSkipped('Needs the MySQL POS schema.');
    }

    Mail::fake();
    config(['pos.require_token' => false]);
    DB::update('UPDATE app_settings SET tax_rate = 0, allow_negative_stock = 0, refund_pin_hash = NULL, loyalty_enabled = 1');

    $this->ip = '10.9.'.random_int(0, 255).'.'.random_int(1, 254);
    $this->withServerVariables(['REMOTE_ADDR' => $this->ip]);
});

function hardeningUser(string $role, string $password = 'secret-pass'): int
{
    return (int) DB::table('users')->insertGetId([
        'full_name' => 'ZZTEST '.$role,
        'username' => 'zztest_'.$role.'_'.uniqid(),
        'email' => 'zztest_'.$role.'_'.uniqid().'@example.test',
        'password_hash' => password_hash($password, PASSWORD_BCRYPT),
        'role' => $role,
        'status' => 1,
    ]);
}

function hardeningProduct(float $price = 100, float $stock = 10): int
{
    return (int) DB::table('products')->insertGetId([
        'category_id' => (int) DB::table('products')->value('category_id'),
        'name' => 'ZZTEST item '.uniqid(),
        'price' => $price,
        'cost_price' => 50,
        'stock' => $stock,
        'reorder_level' => 0,
        'status' => 1,
    ]);
}

function hardeningLogin($test, int $userId, string $password = 'secret-pass'): string
{
    $email = DB::table('users')->where('id', $userId)->value('email');
    $res = $test->postJson('/pos_app/login.php', ['email' => $email, 'password' => $password]);
    $res->assertOk();

    return (string) $res->json('token');
}

function orderPayload(int $productId, float $qty, float $price, array $extra = []): array
{
    return $extra + [
        'is_walk_in' => true,
        'items' => [['product_id' => $productId, 'quantity' => $qty, 'price' => $price, 'discount' => 0, 'total' => $qty * $price]],
        'subtotal' => $qty * $price,
        'vat' => 0,
        'total_amount' => $qty * $price,
        'payment_method' => 'Cash',
        'discount_amount' => 0,
        'coupon_discount' => 0,
        'loyalty_discount' => 0,
        'loyalty_points_redeemed' => 0,
    ];
}

// --- Sign-in tokens ---------------------------------------------------------

test('login returns a token and the token decides who is acting', function () {
    $admin = hardeningUser('admin');
    $cashier = hardeningUser('cashier');
    $token = hardeningLogin($this, $cashier);

    expect(strlen($token))->toBe(64);

    // A cashier's token cannot pass itself off as the admin via actor_user_id.
    $this->withToken($token)
        ->postJson('/pos_app/settings.php', ['tax_rate' => 0, 'actor_user_id' => $admin])
        ->assertStatus(403);

    // The admin's own token can save settings.
    $adminToken = hardeningLogin($this, $admin);
    $this->withToken($adminToken)
        ->postJson('/pos_app/settings.php', ['tax_rate' => 0, 'loyalty_enabled' => true])
        ->assertOk();
});

test('invalid, revoked or deactivated tokens are refused', function () {
    $cashier = hardeningUser('cashier');
    $token = hardeningLogin($this, $cashier);

    $this->withToken('not-a-real-token-'.str_repeat('x', 40))
        ->getJson('/pos_app/categories.php')->assertStatus(401);

    $this->withToken($token)->getJson('/pos_app/categories.php')->assertOk();

    DB::table('users')->where('id', $cashier)->update(['status' => 0]);
    $this->withToken($token)->getJson('/pos_app/categories.php')->assertStatus(401);

    DB::table('users')->where('id', $cashier)->update(['status' => 1]);
    $token = hardeningLogin($this, $cashier);
    $this->withToken($token)->postJson('/pos_app/logout.php')->assertOk();
    $this->withToken($token)->getJson('/pos_app/categories.php')->assertStatus(401);
});

test('without a token: allowed while legacy access is on, refused once tokens are required', function () {
    $this->getJson('/pos_app/categories.php')->assertOk();

    config(['pos.require_token' => true]);
    $this->getJson('/pos_app/categories.php')->assertStatus(401);
    $this->getJson('/pos_app/get_orders.php?order_id=1')->assertStatus(401);
    // Sign-in itself stays reachable.
    $this->postJson('/pos_app/login.php', ['email' => 'nobody@example.test', 'password' => 'x'])->assertStatus(401);
});

// --- Brute-force limits -------------------------------------------------------

test('wrong refund PINs lock out after 8 tries, even for the right PIN', function () {
    DB::update('UPDATE app_settings SET refund_pin_hash = ? WHERE id = 1', [password_hash('4321', PASSWORD_BCRYPT)]);
    RateLimiter::clear('pos-pin:refund:'.$this->ip);

    for ($i = 0; $i < 8; $i++) {
        $this->postJson('/pos_app/process_refund.php', [
            'order_id' => 1, 'reason' => 'x', 'refund_type' => 'all', 'refund_pin' => sprintf('%04d', $i),
        ])->assertStatus(403);
    }

    $this->postJson('/pos_app/process_refund.php', [
        'order_id' => 1, 'reason' => 'x', 'refund_type' => 'all', 'refund_pin' => '4321',
    ])->assertStatus(429);

    RateLimiter::clear('pos-pin:refund:'.$this->ip);
});

test('tablet login locks an account after 10 wrong passwords', function () {
    $cashier = hardeningUser('cashier');
    $email = DB::table('users')->where('id', $cashier)->value('email');

    for ($i = 0; $i < 10; $i++) {
        $this->postJson('/pos_app/login.php', ['email' => $email, 'password' => 'wrong'.$i])->assertStatus(401);
    }
    $this->postJson('/pos_app/login.php', ['email' => $email, 'password' => 'secret-pass'])->assertStatus(429);

    RateLimiter::clear('pos-login:'.sha1(strtolower($email)).'|'.$this->ip);
    RateLimiter::clear('pos-login-ip:'.$this->ip);
});

// --- Admin-only actions ---------------------------------------------------------

test('settings and payroll are admin-only', function () {
    // Anonymous settings save (the old hole) is refused.
    $this->postJson('/pos_app/settings.php', ['tax_rate' => 0.5])->assertStatus(401);
    expect((float) DB::table('app_settings')->value('tax_rate'))->toBe(0.0);

    $cashier = User::find(hardeningUser('cashier'));
    $this->actingAs($cashier)->getJson('/pos/payroll/report')->assertStatus(403);
    $this->actingAs($cashier)->postJson('/pos/staff/attendance/photos/purge', ['all' => true])->assertStatus(403);

    $admin = User::find(hardeningUser('admin'));
    $this->actingAs($admin)->getJson('/pos/payroll/report')->assertOk();
});

// --- Checkout ---------------------------------------------------------------------

test('a retried sale with the same client_order_uuid is saved once', function () {
    $product = hardeningProduct(100, 10);
    $payload = orderPayload($product, 2, 100, ['client_order_uuid' => 'tab1-'.uniqid('', true)]);
    $payload['client_order_uuid'] = str_replace('.', '', $payload['client_order_uuid']);

    $first = $this->postJson('/pos_app/orders.php', $payload)->assertStatus(201);
    $second = $this->postJson('/pos_app/orders.php', $payload)->assertStatus(201);

    expect($second->json('order_id'))->toBe($first->json('order_id'))
        ->and($second->json('duplicate'))->toBeTrue()
        ->and((float) DB::table('products')->where('id', $product)->value('stock'))->toBe(8.0);
});

test('an online sale whose server total differs from what the tablet charged is refused', function () {
    $product = hardeningProduct(120, 10);
    // The tablet still had the old price of 100.
    $payload = orderPayload($product, 2, 100, ['client_total' => 200]);
    $before = DB::table('orders')->count();

    $res = $this->postJson('/pos_app/orders.php', $payload);

    $res->assertStatus(409);
    expect($res->json('message'))->toContain('240.00')
        ->and(DB::table('orders')->count())->toBe($before)
        ->and((float) DB::table('products')->where('id', $product)->value('stock'))->toBe(10.0);
});

test('a paid offline sale syncs with its own date and price even if stock ran out', function () {
    $product = hardeningProduct(120, 1); // price raised to 120, only 1 left now
    $soldAt = now()->subDays(2)->setTime(15, 30);
    $payload = orderPayload($product, 3, 100, [
        'queued_offline' => true,
        'sold_at_ms' => $soldAt->copy()->utc()->getTimestampMs(),
        'client_order_uuid' => 'offline-'.bin2hex(random_bytes(6)),
    ]);

    $res = $this->postJson('/pos_app/orders.php', $payload)->assertStatus(201);
    $order = DB::table('orders')->where('id', $res->json('order_id'))->first();

    expect((float) $order->total_amount)->toBe(300.0)
        ->and(substr((string) $order->created_at, 0, 16))->toBe($soldAt->format('Y-m-d H:i'))
        ->and((float) DB::table('products')->where('id', $product)->value('stock'))->toBe(-2.0);

    // The same payload sent online (no queued_offline) is still refused.
    $online = orderPayload($product, 3, 120);
    $this->postJson('/pos_app/orders.php', $online)->assertStatus(400);
});

test('a coupon at its last allowed use cannot be used twice', function () {
    $product = hardeningProduct(1000, 10);
    DB::table('coupons')->where('code', 'ZZONCE')->delete();
    DB::table('coupons')->insert([
        'code' => 'ZZONCE', 'discount_type' => 'fixed', 'discount_value' => 100,
        'min_order_amount' => 0, 'max_uses' => 1, 'usage_count' => 0, 'status' => 1,
        'start_date' => now()->subDay()->toDateString(), 'end_date' => now()->addDay()->toDateString(),
    ]);
    $payload = orderPayload($product, 1, 1000, ['coupon_code' => 'ZZONCE', 'coupon_discount' => 100]);

    $this->postJson('/pos_app/orders.php', $payload)->assertStatus(201);
    $this->postJson('/pos_app/orders.php', $payload)->assertStatus(400);
    expect((int) DB::table('coupons')->where('code', 'ZZONCE')->value('usage_count'))->toBe(1);
});

// --- Refunds -------------------------------------------------------------------------

test('refunds merge repeated lines, never exceed what was paid, and say how much to give back', function () {
    $a = hardeningProduct(1000, 10);
    $b = hardeningProduct(200, 10);
    $res = $this->postJson('/pos_app/orders.php', [
        'is_walk_in' => true,
        'items' => [
            ['product_id' => $a, 'quantity' => 1, 'price' => 1000, 'discount' => 0, 'total' => 1000],
            ['product_id' => $b, 'quantity' => 1, 'price' => 200, 'discount' => 0, 'total' => 200],
        ],
        'subtotal' => 1200, 'vat' => 0, 'total_amount' => 1200, 'payment_method' => 'Cash',
    ])->assertStatus(201);
    $orderId = (int) $res->json('order_id');
    $itemA = (int) DB::table('order_items')->where('order_id', $orderId)->where('product_id', $a)->value('id');

    // The same line twice: 2 units of a 1-unit line.
    $this->postJson('/pos_app/process_refund.php', [
        'order_id' => $orderId, 'reason' => 'x', 'refund_type' => 'items',
        'items' => [['order_item_id' => $itemA, 'quantity' => 1], ['order_item_id' => $itemA, 'quantity' => 1]],
    ])->assertStatus(400);

    $ok = $this->postJson('/pos_app/process_refund.php', [
        'order_id' => $orderId, 'reason' => 'x', 'refund_type' => 'items',
        'items' => [['order_item_id' => $itemA, 'quantity' => 1]],
    ])->assertOk();

    expect($ok->json('message'))->toContain('Give back ₱1,000.00')
        ->and($ok->json('order_status'))->toBe('partial_refund')
        ->and((float) DB::table('products')->where('id', $a)->value('stock'))->toBe(10.0);
});

// --- Stock edits -------------------------------------------------------------------

test('a product edit applies only the stock change the user made', function () {
    $admin = hardeningUser('admin');
    $product = hardeningProduct(100, 100);
    // A sale happens while the edit form is open (showing 100).
    DB::update('UPDATE products SET stock = 90 WHERE id = ?', [$product]);

    // Price edited, stock field untouched (still showing 100).
    $this->putJson('/pos_app/items.php', [
        'id' => $product, 'price' => 105, 'stock' => 100, 'stock_base' => 100, 'actor_user_id' => $admin,
    ])->assertOk();
    expect((float) DB::table('products')->where('id', $product)->value('stock'))->toBe(90.0)
        ->and((float) DB::table('products')->where('id', $product)->value('price'))->toBe(105.0);

    // +50 delivery typed on top of the stale 100 -> live 90 + 50.
    $this->putJson('/pos_app/items.php', [
        'id' => $product, 'stock' => 150, 'stock_base' => 100, 'actor_user_id' => $admin,
    ])->assertOk();
    expect((float) DB::table('products')->where('id', $product)->value('stock'))->toBe(140.0);

    // No stock in the request: untouched.
    $this->putJson('/pos_app/items.php', ['id' => $product, 'deal' => 'Buy 10', 'actor_user_id' => $admin])->assertOk();
    expect((float) DB::table('products')->where('id', $product)->value('stock'))->toBe(140.0);
});

// --- Import ----------------------------------------------------------------------------

test('import leaves missing columns and blank cells alone', function () {
    $product = hardeningProduct(100, 40);
    DB::table('products')->where('id', $product)->update([
        'barcode' => '4800012345678', 'deal' => 'Buy 5 get 1', 'description' => 'Keep me', 'reorder_level' => 12,
    ]);
    $row = DB::table('products as p')->join('categories as c', 'c.id', '=', 'p.category_id')
        ->where('p.id', $product)->select('p.name', 'c.name as category')->first();

    // Legacy sheet: no barcode/deal/description/reorder columns, blank price
    // and blank stock cells.
    $csv = "Category,Item,Option,Price,Cost,Morning Inventory\n".$row->category.','.$row->name.",,,55,\n";
    $path = tempnam(sys_get_temp_dir(), 'imp').'.csv';
    file_put_contents($path, $csv);

    $result = app(\App\Services\Pos\ProductImportExportService::class)->importFromFile($path, 'csv', null);
    @unlink($path);

    $after = DB::table('products')->where('id', $product)->first();
    expect($result['updated'] ?? 0)->toBe(1)
        ->and((float) $after->price)->toBe(100.0)
        ->and((float) $after->stock)->toBe(40.0)
        ->and((float) $after->cost_price)->toBe(55.0)
        ->and($after->barcode)->toBe('4800012345678')
        ->and($after->deal)->toBe('Buy 5 get 1')
        ->and($after->description)->toBe('Keep me')
        ->and((int) $after->reorder_level)->toBe(12);
});
