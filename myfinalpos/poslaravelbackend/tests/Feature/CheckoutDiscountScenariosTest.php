<?php

use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;

/*
| End-to-end discount matrix against the real POS schema: every mix of item,
| manual, coupon and loyalty discounts (with and without VAT) goes through
| orders.php -> get_orders.php / transaction_reports.php -> partial and full
| refunds via process_refund.php, and every peso is checked at each step.
|
| Needs the full MySQL schema (the SQLite test database lacks the POS
| tables), so it only runs when the default connection is MySQL. Everything
| happens inside a transaction that is rolled back afterwards.
*/

uses(DatabaseTransactions::class);

const SCENARIO_LOYALTY_START_POINTS = 50000;
const SCENARIO_POINTS_PER_UNIT = 50;
const SCENARIO_SPEND_UNIT = 1000.0;
const SCENARIO_REDEEM_POINTS_PER_PESO = 10;

beforeEach(function () {
    if (DB::connection()->getDriverName() !== 'mysql' || ! DB::getSchemaBuilder()->hasTable('orders')) {
        $this->markTestSkipped('Needs the MySQL POS schema.');
    }

    Mail::fake();
});

/**
 * @return array{products: array<string, array{id: int, price: float}>, customer_id: int}
 */
function seedScenarioFixtures(float $taxRate): array
{
    DB::update(
        'UPDATE app_settings SET tax_rate = ?, loyalty_enabled = 1, loyalty_points_per_unit = ?,
            loyalty_spend_unit = ?, loyalty_redeem_points_per_peso = ?, refund_pin_hash = NULL',
        [$taxRate, SCENARIO_POINTS_PER_UNIT, SCENARIO_SPEND_UNIT, SCENARIO_REDEEM_POINTS_PER_PESO],
    );

    $categoryId = (int) DB::table('products')->value('category_id');
    $products = [];
    foreach ([
        'A' => ['ZZTEST AGWAY CARTAP', 120.00],
        'B' => ['ZZTEST LAUDA', 650.00],
        'C' => ['ZZTEST MEDIUM EGG', 7.50],
        'D' => ['ZZTEST FEEDS LOOSE', 89.75],
    ] as $key => [$name, $price]) {
        $id = DB::table('products')->insertGetId([
            'category_id' => $categoryId,
            'name' => $name,
            'price' => $price,
            'cost_price' => round($price * 0.7, 2),
            'stock' => 1000000,
            'reorder_level' => 0,
            'status' => 1,
        ]);
        $products[$key] = ['id' => $id, 'price' => $price];
    }

    $customerId = DB::table('customers')->insertGetId([
        'customer_name' => 'ZZTEST Juan Farmer '.uniqid(),
        'order_type' => 'Retail',
    ]);
    DB::table('loyalty_cards')->insert([
        'customer_id' => $customerId,
        'card_number' => 'ZZT-'.uniqid(),
        'points' => SCENARIO_LOYALTY_START_POINTS,
        'tier' => 'Bronze',
        'status' => 'Active',
    ]);

    $today = now()->toDateString();
    foreach ([
        ['ZZFIX500', 'fixed', 500],
        ['ZZPCT10', 'percentage', 10],
        ['ZZFIX99999', 'fixed', 99999],
    ] as [$code, $type, $value]) {
        DB::table('coupons')->where('code', $code)->delete();
        DB::table('coupons')->insert([
            'code' => $code,
            'discount_type' => $type,
            'discount_value' => $value,
            'min_order_amount' => 0,
            'start_date' => now()->subDay()->toDateString(),
            'end_date' => now()->addDay()->toDateString(),
            'usage_count' => 0,
            'status' => 1,
        ]);
    }

    return ['products' => $products, 'customer_id' => $customerId, 'today' => $today];
}

/**
 * Builds the exact payload the tablet sends (PosApi.buildOrderPayload +
 * CartItem.toJson), using double maths like the Dart client does.
 *
 * @param  array<int, array{key: string, qty: float, dpu: float}>  $lines
 */
function tabletPayload(array $fx, array $s, float $taxRate): array
{
    $items = [];
    $clientSubtotal = 0.0;
    foreach ($s['lines'] as $line) {
        $price = $fx['products'][$line['key']]['price'];
        $gross = $price * $line['qty'];
        $discount = min(max(0, $line['dpu'] * $line['qty']), $gross);
        $total = $gross - $discount;
        $clientSubtotal += $total;
        $items[] = [
            'product_id' => $fx['products'][$line['key']]['id'],
            'quantity' => $line['qty'],
            'price' => $price,
            'discount_per_unit' => $line['dpu'],
            'discount' => $discount,
            'total' => $total,
        ];
    }

    $coupon = 0.0;
    if ($s['coupon'] === 'ZZFIX500') {
        $coupon = min(500, $clientSubtotal);
    } elseif ($s['coupon'] === 'ZZPCT10') {
        $coupon = min($clientSubtotal, $clientSubtotal * 0.10);
    } elseif ($s['coupon'] === 'ZZFIX99999') {
        $coupon = min(99999, $clientSubtotal);
    }

    $loyaltyPeso = min($s['points'] / SCENARIO_REDEEM_POINTS_PER_PESO, $clientSubtotal);
    $totalDiscount = min(max(0, $s['manual'] + $coupon + $loyaltyPeso), $clientSubtotal);
    $net = $clientSubtotal - $totalDiscount;
    $vat = $net * $taxRate;
    $grand = $net + $vat;

    // A tampered / stale client sending more than the coupon or points are worth.
    if (isset($s['send_coupon'])) {
        $coupon = $s['send_coupon'];
    }
    if (isset($s['send_loyalty'])) {
        $loyaltyPeso = $s['send_loyalty'];
    }

    return [
        'payload' => array_filter([
            'customer_id' => $s['customer'] ? $fx['customer_id'] : null,
            'is_walk_in' => ! $s['customer'],
            'items' => $items,
            'subtotal' => $net,
            'vat' => $vat,
            'total_amount' => $grand,
            'client_change' => 0,
            'payment_method' => 'Cash',
            'reference' => '',
            'discount_amount' => $s['manual'],
            'coupon_discount' => $coupon,
            'coupon_code' => $s['coupon'] ?: null,
            'loyalty_discount' => $loyaltyPeso,
            'loyalty_points_redeemed' => $s['points'],
            'branch_id' => 1,
            'actor_user_id' => null,
        ], fn ($v) => $v !== null),
        'client_total' => $grand,
        'client_coupon' => $coupon,
        'client_loyalty' => $loyaltyPeso,
    ];
}

/**
 * Independent expectation of what the server should store.
 */
function expectedOrder(array $fx, array $s, array $client, float $taxRate, int $cardPoints): array
{
    $lines = [];
    $merch = 0.0;
    foreach ($s['lines'] as $i => $line) {
        $item = $client['payload']['items'][$i];
        $gross = round($fx['products'][$line['key']]['price'] * $line['qty'], 2);
        $disc = min(round($item['discount'], 2), $gross);
        $total = round($gross - $disc, 2);
        $merch += $total;
        $lines[] = ['key' => $line['key'], 'qty' => $line['qty'], 'gross' => $gross, 'discount' => $disc, 'total' => $total];
    }
    $merch = round($merch, 2);

    // Coupon: never more than the coupon is worth on this order.
    $coupon = round($client['payload']['coupon_discount'], 2);
    if ($s['coupon'] === 'ZZFIX500') {
        $coupon = min($coupon, round(min($merch, 500), 2));
    } elseif ($s['coupon'] === 'ZZPCT10') {
        $coupon = min($coupon, round(min($merch, $merch * 0.10), 2));
    } elseif ($s['coupon'] === 'ZZFIX99999') {
        $coupon = min($coupon, round(min($merch, 99999), 2));
    }

    // Loyalty: at most the card balance, and at most what the points buy.
    $loyalty = round($client['payload']['loyalty_discount'], 2);
    $points = $s['points'];
    if (! $s['customer'] || $points <= 0) {
        [$loyalty, $points] = [0.0, 0];
    } elseif ($points > $cardPoints) {
        $loyalty = round($loyalty * $cardPoints / $points, 2);
        $points = $cardPoints;
    }
    $loyalty = round(min($loyalty, $points / SCENARIO_REDEEM_POINTS_PER_PESO), 2);

    // Then the three together never exceed the merchandise (loyalty trimmed first).
    $room = $merch;
    $manual = round(min(max(0, $s['manual']), $room), 2);
    $room = round($room - $manual, 2);
    $coupon = round(min($coupon, $room), 2);
    $room = round($room - $coupon, 2);
    $sentLoyalty = $loyalty;
    $loyalty = round(min($sentLoyalty, $room), 2);
    if ($sentLoyalty > 0 && $loyalty < $sentLoyalty) {
        $points = (int) ceil(round($points * $loyalty / $sentLoyalty, 4));
    }

    $net = max(0, round($merch - $manual - $coupon - $loyalty, 2));
    $vat = round($net * $taxRate, 2);
    $total = round($net + $vat, 2);
    $earned = $s['customer'] ? (int) floor(($total / SCENARIO_SPEND_UNIT) * SCENARIO_POINTS_PER_UNIT) : 0;

    return compact('lines', 'merch', 'manual', 'coupon', 'loyalty', 'points', 'net', 'vat', 'total', 'earned');
}

function scenarioMatrix(): array
{
    $withItemDiscounts = [
        ['key' => 'A', 'qty' => 120, 'dpu' => 31],
        ['key' => 'B', 'qty' => 12, 'dpu' => 140],
        ['key' => 'C', 'qty' => 30, 'dpu' => 0.5],
        ['key' => 'D', 'qty' => 2.5, 'dpu' => 3.25],
    ];
    $noItemDiscounts = array_map(fn ($l) => [...$l, 'dpu' => 0], $withItemDiscounts);

    $scenarios = [];
    foreach ([0.0, 0.12] as $vat) {
        foreach (['walk-in' => false, 'loyalty' => true] as $customerLabel => $customer) {
            foreach (['item' => $withItemDiscounts, 'no-item' => $noItemDiscounts] as $itemLabel => $lines) {
                foreach ([0, 3720] as $manual) {
                    foreach (['', 'ZZFIX500', 'ZZPCT10'] as $coupon) {
                        foreach ($customer ? [0, 15000] : [0] as $points) {
                            $scenarios[] = [
                                'name' => sprintf(
                                    'VAT %d%% | %s | %s | manual %d | coupon %s | points %d',
                                    $vat * 100, $customerLabel, $itemLabel, $manual, $coupon ?: '-', $points,
                                ),
                                'vat' => $vat,
                                'customer' => $customer,
                                'lines' => $lines,
                                'manual' => $manual,
                                'coupon' => $coupon,
                                'points' => $points,
                            ];
                        }
                    }
                }
            }
        }
    }

    // Stacked discounts larger than the order, as an older tablet build or
    // an offline-queued sale could still send them - the server must cap.
    $small = [['key' => 'B', 'qty' => 2, 'dpu' => 50]]; // 1,300 gross, 1,200 net
    foreach ([0.0, 0.12] as $vat) {
        $scenarios[] = ['name' => "VAT ".($vat * 100)."% | OVERFLOW loyalty trimmed", 'vat' => $vat, 'customer' => true,
            'lines' => $small, 'manual' => 600, 'coupon' => 'ZZFIX500', 'points' => 4000]; // 600+500+400 > 1200
        $scenarios[] = ['name' => "VAT ".($vat * 100)."% | OVERFLOW manual = whole order", 'vat' => $vat, 'customer' => true,
            'lines' => $small, 'manual' => 1200, 'coupon' => '', 'points' => 2000];
        $scenarios[] = ['name' => "VAT ".($vat * 100)."% | coupon bigger than order", 'vat' => $vat, 'customer' => false,
            'lines' => $small, 'manual' => 0, 'coupon' => 'ZZFIX99999', 'points' => 0];
        $scenarios[] = ['name' => "VAT ".($vat * 100)."% | item discount = full price", 'vat' => $vat, 'customer' => true,
            'lines' => [['key' => 'B', 'qty' => 2, 'dpu' => 650], ['key' => 'A', 'qty' => 3, 'dpu' => 0]],
            'manual' => 100, 'coupon' => 'ZZPCT10', 'points' => 500];
        $scenarios[] = ['name' => "VAT ".($vat * 100)."% | single unit all discounts", 'vat' => $vat, 'customer' => true,
            'lines' => [['key' => 'B', 'qty' => 1, 'dpu' => 50]], 'manual' => 100, 'coupon' => 'ZZPCT10', 'points' => 1000];

        // Stale tablet: card only holds 3,000 points but 15,000 are redeemed.
        $scenarios[] = ['name' => "VAT ".($vat * 100)."% | redeem more points than card holds", 'vat' => $vat, 'customer' => true,
            'lines' => $withItemDiscounts, 'manual' => 3720, 'coupon' => 'ZZFIX500', 'points' => 15000, 'card_points' => 3000];
        $scenarios[] = ['name' => "VAT ".($vat * 100)."% | card has zero points", 'vat' => $vat, 'customer' => true,
            'lines' => $small, 'manual' => 0, 'coupon' => '', 'points' => 500, 'card_points' => 0];
        // Tampered payload: pesos larger than the points / coupon are worth.
        $scenarios[] = ['name' => "VAT ".($vat * 100)."% | loyalty pesos inflated", 'vat' => $vat, 'customer' => true,
            'lines' => $withItemDiscounts, 'manual' => 0, 'coupon' => '', 'points' => 100, 'send_loyalty' => 5000.0, 'tampered' => true];
        $scenarios[] = ['name' => "VAT ".($vat * 100)."% | coupon pesos inflated", 'vat' => $vat, 'customer' => false,
            'lines' => $withItemDiscounts, 'manual' => 0, 'coupon' => 'ZZFIX500', 'points' => 0, 'send_coupon' => 5000.0, 'tampered' => true];
        // Penny-rounding stress: odd prices, decimal quantities, percentage coupon.
        $scenarios[] = ['name' => "VAT ".($vat * 100)."% | rounding stress", 'vat' => $vat, 'customer' => true,
            'lines' => [['key' => 'D', 'qty' => 0.333, 'dpu' => 1.11], ['key' => 'C', 'qty' => 7, 'dpu' => 0.33], ['key' => 'D', 'qty' => 1.7, 'dpu' => 0]],
            'manual' => 0.07, 'coupon' => 'ZZPCT10', 'points' => 33];
    }

    return $scenarios;
}

function near(float $a, float $b, float $tol = 0.005): bool
{
    return abs($a - $b) <= $tol;
}

test('every discount combination checks out, reports and refunds to the peso', function () {
    $failures = [];
    $notes = [];
    $ran = 0;

    $fail = function (string $scenario, string $message) use (&$failures) {
        $failures[] = "[$scenario] $message";
    };

    $fx = null;
    $currentVat = null;
    $orderIds = [];

    foreach (scenarioMatrix() as $s) {
        if ($currentVat !== $s['vat'] || $fx === null) {
            $fx = seedScenarioFixtures($s['vat']);
            $currentVat = $s['vat'];
        }
        $name = $s['name'];
        $ran++;

        // Two identical sales: one is refunded item by item, the other in one go.
        foreach (['items', 'all'] as $flow) {
            $cardPoints = $s['card_points'] ?? SCENARIO_LOYALTY_START_POINTS;
            DB::table('loyalty_cards')->where('customer_id', $fx['customer_id'])->update(['points' => $cardPoints]);

            $client = tabletPayload($fx, $s, $s['vat']);
            $exp = expectedOrder($fx, $s, $client, $s['vat'], $cardPoints);
            $tag = "$name | refund:$flow";

            $pointsBefore = $cardPoints;
            $couponUsesBefore = $s['coupon'] !== ''
                ? (int) DB::table('coupons')->where('code', $s['coupon'])->value('usage_count')
                : 0;
            $stockBefore = DB::table('products')
                ->whereIn('id', array_column($fx['products'], 'id'))
                ->pluck('stock', 'id')->map(fn ($v) => (float) $v)->all();

            $res = $this->postJson('/pos_app/orders.php', $client['payload']);
            if ($res->status() !== 201 || $res->json('success') !== true) {
                $fail($tag, 'checkout failed: '.$res->status().' '.$res->content());

                continue;
            }
            $orderId = (int) $res->json('order_id');
            $orderIds[$orderId] = ['tag' => $tag, 'exp' => $exp, 's' => $s];

            // --- Stored order -------------------------------------------------
            $order = DB::table('orders')->where('id', $orderId)->first();
            foreach ([
                'subtotal' => $exp['net'], 'vat' => $exp['vat'], 'total_amount' => $exp['total'],
                'discount_amount' => $exp['manual'], 'coupon_discount' => $exp['coupon'],
                'loyalty_discount' => $exp['loyalty'],
            ] as $col => $want) {
                if (! near((float) $order->$col, $want)) {
                    $fail($tag, "orders.$col = {$order->$col}, expected $want");
                }
            }
            if ((int) $order->loyalty_points_redeemed !== $exp['points']) {
                $fail($tag, "loyalty_points_redeemed = {$order->loyalty_points_redeemed}, expected {$exp['points']}");
            }
            $clientAgrees = ! ($s['tampered'] ?? false) && ! isset($s['card_points']);
            if ($clientAgrees && ! near($client['client_total'], (float) $order->total_amount, 0.011)) {
                $fail($tag, sprintf('tablet charged %.4f but server stored %.2f', $client['client_total'], $order->total_amount));
            }

            $items = DB::table('order_items')->where('order_id', $orderId)->orderBy('id')->get();
            foreach ($exp['lines'] as $i => $line) {
                $row = $items[$i] ?? null;
                if (! $row || ! near((float) $row->total, $line['total']) || ! near((float) $row->discount_amount, $line['discount'])) {
                    $fail($tag, "order_items[{$line['key']}] total/discount = ".($row ? "{$row->total}/{$row->discount_amount}" : 'missing')
                        ." expected {$line['total']}/{$line['discount']}");
                }
            }

            // --- Coupon usage + loyalty points ---------------------------------
            if ($s['coupon'] !== '') {
                $uses = (int) DB::table('coupons')->where('code', $s['coupon'])->value('usage_count');
                $shouldCount = $exp['coupon'] > 0;
                if ($uses !== $couponUsesBefore + ($shouldCount ? 1 : 0)) {
                    $fail($tag, "coupon usage went $couponUsesBefore -> $uses");
                }
            }
            if ($s['customer']) {
                $pointsAfter = (int) DB::table('loyalty_cards')->where('customer_id', $fx['customer_id'])->value('points');
                $wantPoints = $pointsBefore - $exp['points'] + $exp['earned'];
                if ($pointsAfter !== $wantPoints) {
                    $fail($tag, "loyalty card $pointsBefore -> $pointsAfter, expected $wantPoints (redeem {$exp['points']}, earn {$exp['earned']})");
                }
            }

            // --- Refunds ---------------------------------------------------------
            $refund = fn (array $body) => $this->postJson('/pos_app/process_refund.php', $body + [
                'order_id' => $orderId, 'reason' => 'scenario test', 'action' => 'refund',
            ]);
            $itemRows = $items->values();

            if ($flow === 'all' || $exp['total'] <= 0) {
                // A sale fully covered by discounts can still be returned: it
                // pays back nothing but must put the goods back into stock.
                $r = $refund(['refund_type' => 'all']);
                if ($r->status() !== 200) {
                    $fail($tag, 'refund all failed: '.$r->content());

                    continue;
                }
            } else {
                // 1) one unit of the first line, 2) half of every remaining
                // line (decimals included), 3) whatever is left.
                $remaining = [];
                foreach ($itemRows as $row) {
                    $remaining[(int) $row->id] = (float) $row->quantity;
                }
                $first = (int) $itemRows[0]->id;
                $steps = [[[$first, min(1.0, $remaining[$first])]]];
                $half = [];
                foreach ($remaining as $id => $qty) {
                    $take = $id === $first ? floor(($qty - 1) / 2) : round($qty / 2, 2);
                    if ($take > 0) {
                        $half[] = [$id, $take];
                    }
                }
                $steps[] = $half;

                foreach ($steps as $stepNo => $step) {
                    if ($step === []) {
                        continue;
                    }
                    $before = (float) DB::table('orders')->where('id', $orderId)->value('refunded_amount');
                    $r = $refund(['refund_type' => 'items', 'items' => array_map(
                        fn ($l) => ['order_item_id' => $l[0], 'quantity' => $l[1]], $step,
                    )]);
                    foreach ($step as [$id, $qty]) {
                        $remaining[$id] -= $qty;
                    }
                    if ($r->status() !== 200) {
                        $fail($tag, 'partial refund step '.($stepNo + 1).' failed: '.$r->content());

                        continue 2;
                    }
                    $paid = (float) DB::table('orders')->where('id', $orderId)->value('refunded_amount') - $before;

                    // Each partial refund is that merchandise's share of what
                    // the customer actually paid.
                    $wantMerch = 0.0;
                    foreach ($step as [$id, $qty]) {
                        $row = $itemRows->firstWhere('id', $id);
                        $wantMerch += round(((float) $row->total / (float) $row->quantity) * $qty * ($exp['net'] / $exp['merch']), 2);
                    }
                    $want = round($wantMerch + $wantMerch * ($exp['net'] > 0 ? $exp['vat'] / $exp['net'] : 0), 2);
                    if (! near($paid, $want, 0.02 * count($step))) {
                        $fail($tag, sprintf('partial refund step %d paid %.2f, expected about %.2f', $stepNo + 1, $paid, $want));
                    }
                    if ($paid <= 0 && $want > 0) {
                        $fail($tag, 'partial refund step '.($stepNo + 1).' paid nothing');
                    }

                    // Loyalty: the refunded share of points earned is taken
                    // back and of points redeemed is returned (rounded down
                    // until the sale is fully refunded).
                    if ($s['customer']) {
                        $share = DB::selectOne(
                            'SELECT SUM(total) AS v, SUM(total * refunded_quantity / quantity) AS r,
                                    SUM(quantity) AS q, SUM(refunded_quantity) AS rq
                             FROM order_items WHERE order_id = ?',
                            [$orderId],
                        );
                        $fraction = (float) $share->q - (float) $share->rq <= 0.0001 ? 1.0
                            : ((float) $share->v > 0 ? min(1.0, (float) $share->r / (float) $share->v)
                                : (float) $share->rq / (float) $share->q);
                        $wantPoints = $pointsBefore - $exp['points'] + $exp['earned']
                            + ($fraction >= 1.0 ? $exp['points'] : (int) floor($exp['points'] * $fraction))
                            - ($fraction >= 1.0 ? $exp['earned'] : (int) floor($exp['earned'] * $fraction));
                        $pointsNow = (int) DB::table('loyalty_cards')->where('customer_id', $fx['customer_id'])->value('points');
                        if ($pointsNow !== $wantPoints) {
                            $fail($tag, sprintf(
                                'after partial refund step %d (%.1f%% refunded) card has %d points, expected %d',
                                $stepNo + 1, $fraction * 100, $pointsNow, $wantPoints,
                            ));
                        }
                    }
                }

                $rest = [];
                foreach ($remaining as $id => $qty) {
                    if ($qty > 0.0001) {
                        $rest[] = ['order_item_id' => $id, 'quantity' => round($qty, 3)];
                    }
                }
                if ($rest !== []) {
                    $r = $refund(['refund_type' => 'items', 'items' => $rest]);
                    if ($r->status() !== 200) {
                        $fail($tag, 'final refund failed: '.$r->content());

                        continue;
                    }
                }
            }

            $refunded = (float) DB::table('refunds')->where('order_id', $orderId)->sum('amount');
            $order = DB::table('orders')->where('id', $orderId)->first();
            if (! near($refunded, $exp['total'])) {
                $fail($tag, "refunds total $refunded, expected exactly {$exp['total']}");
            }
            if ($order->status !== 'refunded') {
                $fail($tag, "status after full refund = {$order->status}");
            }
            $lineSum = (float) DB::table('refund_items')
                ->join('refunds', 'refunds.id', '=', 'refund_items.refund_id')
                ->where('refunds.order_id', $orderId)->sum('refund_items.amount');
            if (! near($lineSum, $refunded, 0.011)) {
                $fail($tag, "refund_items add up to $lineSum but refunds to $refunded");
            }
            $stockAfter = DB::table('products')
                ->whereIn('id', array_column($fx['products'], 'id'))
                ->pluck('stock', 'id')->map(fn ($v) => (float) $v)->all();
            foreach ($stockBefore as $id => $qty) {
                if (! near($stockAfter[$id], $qty, 0.0001)) {
                    $fail($tag, "product #$id stock $qty -> {$stockAfter[$id]} after full refund");
                }
            }
            if ($s['customer']) {
                // A fully refunded sale leaves the card exactly as before it.
                $pointsNow = (int) DB::table('loyalty_cards')->where('customer_id', $fx['customer_id'])->value('points');
                if ($pointsNow !== $pointsBefore) {
                    $fail($tag, "card has $pointsNow points after full refund, expected $pointsBefore (redeemed {$exp['points']}, earned {$exp['earned']})");
                }
                $logNet = (int) DB::table('loyalty_point_logs')->where('order_id', $orderId)
                    ->whereIn('action', ['earn', 'redeem', 'refund'])->sum('points_change');
                if ($logNet !== 0) {
                    $fail($tag, "loyalty logs for the order net to $logNet, expected 0");
                }
            }
        }
    }

    // --- Order history (tablet) and transaction report (admin) ------------
    $today = now()->toDateString();
    $history = collect($this->getJson("/pos_app/get_orders.php?from=$today&to=$today")->json('data'))->keyBy('id');

    // Filters: a single order by id, and a range that excludes today.
    $someOrder = array_key_first($orderIds);
    $single = $this->getJson("/pos_app/get_orders.php?order_id=$someOrder")->json('data');
    if (count($single) !== 1 || (int) $single[0]['id'] !== $someOrder) {
        $fail('get_orders order_id', 'expected exactly order '.$someOrder.', got '.count($single).' rows');
    } elseif ($single[0] != $history[$someOrder]) {
        $fail('get_orders order_id', 'single-order row differs from the date-range row');
    }
    $yesterday = now()->subDay()->toDateString();
    $past = collect($this->getJson("/pos_app/get_orders.php?to=$yesterday&from=".now()->subDays(3)->toDateString())->json('data'))
        ->pluck('id')->intersect(array_keys($orderIds));
    if ($past->isNotEmpty()) {
        $fail('get_orders to=yesterday', 'returned today\'s orders: '.$past->implode(','));
    }
    $report = collect();
    for ($page = 1; ; $page++) {
        $json = $this->getJson('/pos_app/transaction_reports.php?view=details&per_page=100&page='.$page
            .'&start='.now()->toDateString().'&end='.now()->toDateString())->json('data');
        $report = $report->replace(collect($json['rows'] ?? [])->keyBy('id'));
        if ($page >= (int) ($json['pagination']['total_pages'] ?? 1)) {
            break;
        }
    }

    foreach ($orderIds as $orderId => ['tag' => $tag, 'exp' => $exp]) {
        $h = $history[$orderId] ?? null;
        if (! $h) {
            $fail($tag, 'missing from get_orders.php');

            continue;
        }
        $itemDisc = array_sum(array_column($exp['lines'], 'discount'));
        if (! near((float) $h['discount_amount'], $itemDisc + $exp['manual'])) {
            $fail($tag, "get_orders discount_amount {$h['discount_amount']}, expected item+manual ".($itemDisc + $exp['manual']));
        }

        // Receipt maths the tablet does on reprint (TransactionService.buildReceiptData
        // + ThermalReceiptLayout): order-level manual = discount_amount - item discounts,
        // SUBTOTAL = subtotal + every discount, must equal the real gross.
        $gross = 0.0;
        $histItemDisc = 0.0;
        foreach ($h['items'] as $it) {
            $g = (float) $it['price'] * (float) $it['quantity'];
            $gross += $g;
            $histItemDisc += max((float) $it['discount_amount'], $g - (float) $it['total']);
        }
        $manualOnly = max(0, (float) $h['discount_amount'] - $histItemDisc);
        $printedDiscount = $histItemDisc + $manualOnly + (float) $h['coupon_discount'] + (float) $h['loyalty_discount'];
        $printedSubtotal = (float) $h['subtotal'] + $printedDiscount;
        if (! near($printedSubtotal, $gross, 0.02)) {
            $fail($tag, sprintf('reprint SUBTOTAL %.2f != gross %.2f', $printedSubtotal, $gross));
        }
        if (! near($printedSubtotal - $printedDiscount + (float) $h['vat'], (float) $h['total_amount'], 0.011)) {
            $fail($tag, 'reprint SUBTOTAL - DISCOUNT + VAT != TOTAL');
        }

        $row = $report[$orderId] ?? null;
        if (! $row) {
            $fail($tag, 'missing from transaction report');

            continue;
        }
        $wantDisc = round($itemDisc + $exp['manual'] + $exp['coupon'] + $exp['loyalty'], 2);
        if (! near((float) $row['discount'], $wantDisc, 0.011)) {
            $fail($tag, "report discount {$row['discount']}, expected $wantDisc");
        }
        if ($row['receipt_number'] !== sprintf('INV-%06d', $orderId)) {
            $fail($tag, "report receipt_number {$row['receipt_number']}");
        }
    }

    // Receipt-number search, with and without the prefix / leading zeros.
    $someId = array_key_first($orderIds);
    foreach ([sprintf('%06d', $someId), sprintf('INV-%06d', $someId), sprintf('RCP-%06d', $someId), (string) $someId] as $q) {
        $ids = collect($this->getJson('/pos_app/transaction_reports.php?view=details&per_page=100&search='.urlencode($q)
            .'&start='.now()->toDateString().'&end='.now()->toDateString())->json('data.rows'))->pluck('id');
        if (! $ids->contains($someId)) {
            $fail("search '$q'", "order $someId not found");
        }
    }

    fwrite(STDERR, sprintf("\n%d scenarios, %d orders, %d failures\n", $ran, count($orderIds), count($failures)));
    foreach ($notes as $note) {
        fwrite(STDERR, "NOTE: $note\n");
    }

    expect($failures)->toBe([]);
})->group('scenarios');

test('refund cannot take back earned points the customer already spent', function () {
    $fx = seedScenarioFixtures(0.0);
    $card = fn () => (int) DB::table('loyalty_cards')->where('customer_id', $fx['customer_id'])->value('points');
    DB::table('loyalty_cards')->where('customer_id', $fx['customer_id'])->update(['points' => 1000]);

    // 120 x 120 = 14,400; redeem 1,000 points (100 pesos) -> pays 14,300,
    // earns floor(14,300 / 1,000 * 50) = 715 points.
    $s = ['customer' => true, 'lines' => [['key' => 'A', 'qty' => 120, 'dpu' => 0]],
        'manual' => 0, 'coupon' => '', 'points' => 1000];
    $orderId = (int) $this->postJson('/pos_app/orders.php', tabletPayload($fx, $s, 0.0)['payload'])->json('order_id');
    expect($card())->toBe(715);

    // Customer spends most of it elsewhere before coming back.
    DB::table('loyalty_cards')->where('customer_id', $fx['customer_id'])->update(['points' => 15]);

    $res = $this->postJson('/pos_app/process_refund.php', [
        'order_id' => $orderId, 'reason' => 'scenario test', 'refund_type' => 'all', 'action' => 'refund',
    ]);

    $res->assertOk();
    // 1,000 redeemed points come back first, then all 715 earned are taken
    // back - the card had enough once the redeemed points were returned.
    expect($card())->toBe(1015 - 715)
        ->and($res->json('loyalty.redeemed_returned'))->toBe(1000)
        ->and($res->json('loyalty.earned_reversed'))->toBe(715);

    // Second sale with no redemption: earned points spent -> floor at 0.
    $s['points'] = 0;
    $orderId = (int) $this->postJson('/pos_app/orders.php', tabletPayload($fx, $s, 0.0)['payload'])->json('order_id');
    $earned = (int) floor(14400 / 1000 * 50); // 720
    DB::table('loyalty_cards')->where('customer_id', $fx['customer_id'])->update(['points' => 100]);

    $res = $this->postJson('/pos_app/process_refund.php', [
        'order_id' => $orderId, 'reason' => 'scenario test', 'refund_type' => 'all', 'action' => 'refund',
    ]);

    $res->assertOk();
    expect($card())->toBe(0)
        ->and($res->json('loyalty.earned_reversed'))->toBe(100)
        ->and(DB::table('loyalty_point_logs')->where('order_id', $orderId)->where('action', 'refund')->value('description'))
        ->toContain(($earned - 100).' already spent');
})->group('scenarios');
