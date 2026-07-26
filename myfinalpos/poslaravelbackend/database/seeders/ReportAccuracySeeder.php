<?php

namespace Database\Seeders;

use App\Services\Pos\ReportService;
use App\Support\PosHelpers;
use Carbon\Carbon;
use Illuminate\Database\Seeder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Seeds predictable orders with VAT = 0 for report verification.
 *
 * Run: php artisan db:seed --class=ReportAccuracySeeder
 */
class ReportAccuracySeeder extends Seeder
{
    private const REF_PREFIX = 'ACCURACY-';

    /** @var array<string, array{id: int, price: float, cost: float}> */
    private array $catalog = [];

    public function run(): void
    {
        if (! Schema::hasTable('orders') || ! Schema::hasTable('order_items')) {
            $this->command?->warn('Order tables missing. Run migrations first.');

            return;
        }

        if (! DB::table('products')->exists()) {
            $this->call(PosDatabaseSeeder::class);
        }

        $this->forceZeroVat();
        $this->purgeSeededOrders();
        $this->ensureCatalogProducts();
        $this->seedOrders();
        $this->printVerification();
    }

    private function forceZeroVat(): void
    {
        if (! Schema::hasTable('app_settings')) {
            return;
        }

        DB::table('app_settings')->updateOrInsert(
            ['id' => 1],
            [
                'tax_rate' => 0,
                'updated_at' => now(),
            ],
        );

        $this->command?->info('app_settings.tax_rate set to 0 (0% VAT).');
    }

    private function purgeSeededOrders(): void
    {
        foreach (['ACCURACY-', 'SAMPLE-RPT-'] as $prefix) {
            $orderIds = DB::table('orders')
                ->where('reference', 'like', $prefix.'%')
                ->pluck('id')
                ->all();

            if ($orderIds === []) {
                continue;
            }

            if (Schema::hasTable('refund_items') && Schema::hasTable('refunds')) {
                $refundIds = DB::table('refunds')
                    ->whereIn('order_id', $orderIds)
                    ->pluck('id')
                    ->all();

                if ($refundIds !== []) {
                    DB::table('refund_items')->whereIn('refund_id', $refundIds)->delete();
                    DB::table('refunds')->whereIn('id', $refundIds)->delete();
                }
            }

            DB::table('order_items')->whereIn('order_id', $orderIds)->delete();
            DB::table('orders')->whereIn('id', $orderIds)->delete();
        }
    }

    private function ensureCatalogProducts(): void
    {
        $defs = [
            'ACC Rice 25kg' => ['price' => 890.0, 'cost' => 695.0, 'category' => 'Animal Feed'],
            'ACC Fertilizer 50kg' => ['price' => 1920.0, 'cost' => 1485.0, 'category' => 'Fertilizers'],
            'ACC Corn Seed 1kg' => ['price' => 320.0, 'cost' => 248.0, 'category' => 'Seeds'],
            'ACC Pesticide 1L' => ['price' => 520.0, 'cost' => 385.0, 'category' => 'Pesticides'],
            'ACC Feeds 40kg' => ['price' => 1280.0, 'cost' => 985.0, 'category' => 'Animal Feed'],
        ];

        foreach ($defs as $name => $meta) {
            $existing = DB::table('products')->where('name', $name)->first();

            if ($existing) {
                DB::table('products')->where('id', $existing->id)->update([
                    'price' => $meta['price'],
                    'cost_price' => $meta['cost'],
                    'status' => 'active',
                ]);
                $this->catalog[$name] = [
                    'id' => (int) $existing->id,
                    'price' => $meta['price'],
                    'cost' => $meta['cost'],
                ];

                continue;
            }

            $categoryId = (int) (DB::table('categories')
                ->where('name', $meta['category'])
                ->value('id') ?? DB::table('categories')->value('id') ?? 1);

            $row = [
                'name' => $name,
                'category_id' => $categoryId,
                'price' => $meta['price'],
                'cost_price' => $meta['cost'],
                'stock' => 500,
                'status' => 'active',
                'created_at' => now(),
            ];

            if (Schema::hasColumn('products', 'unit')) {
                $row['unit'] = 'pc';
            }

            $id = DB::table('products')->insertGetId($row);

            $this->catalog[$name] = [
                'id' => $id,
                'price' => $meta['price'],
                'cost' => $meta['cost'],
            ];
        }
    }

    private function seedOrders(): void
    {
        $cashierId = (int) (DB::table('users')->where('role', 'cashier')->value('id')
            ?? DB::table('users')->value('id')
            ?? 1);

        $plans = $this->orderPlans();
        $created = 0;

        foreach ($plans as $plan) {
            $this->createOrder($plan, $cashierId);
            $created++;
        }

        $this->command?->info("Seeded {$created} accuracy orders (reference prefix ".self::REF_PREFIX.').');
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function orderPlans(): array
    {
        $rice = 'ACC Rice 25kg';
        $fert = 'ACC Fertilizer 50kg';
        $seed = 'ACC Corn Seed 1kg';
        $pest = 'ACC Pesticide 1L';
        $feed = 'ACC Feeds 40kg';

        return [
            ['ref' => '001', 'daysAgo' => 0, 'hour' => 9, 'payment' => 'Cash', 'lines' => [[$rice, 2]], 'discount' => 0],
            ['ref' => '002', 'daysAgo' => 0, 'hour' => 11, 'payment' => 'GCash', 'lines' => [[$fert, 1], [$seed, 2]], 'discount' => 0],
            ['ref' => '003', 'daysAgo' => 0, 'hour' => 15, 'payment' => 'Cash', 'lines' => [[$feed, 1], [$pest, 1]], 'discount' => 20],
            ['ref' => '004', 'daysAgo' => 1, 'hour' => 10, 'payment' => 'Cash', 'lines' => [[$rice, 3]], 'discount' => 50],
            ['ref' => '005', 'daysAgo' => 1, 'hour' => 14, 'payment' => 'Bank Transfer', 'lines' => [[$fert, 4]], 'discount' => 0],
            ['ref' => '006', 'daysAgo' => 1, 'hour' => 16, 'payment' => 'GCash', 'lines' => [[$seed, 6]], 'discount' => 0],
            ['ref' => '007', 'daysAgo' => 2, 'hour' => 8, 'payment' => 'Cash', 'lines' => [[$rice, 1]], 'discount' => 0, 'fullRefund' => true],
            ['ref' => '008', 'daysAgo' => 2, 'hour' => 12, 'payment' => 'GCash', 'lines' => [[$fert, 2], [$seed, 1]], 'discount' => 0, 'partialRefund' => [$fert, 1]],
            ['ref' => '009', 'daysAgo' => 2, 'hour' => 17, 'payment' => 'Cash', 'lines' => [[$pest, 2]], 'discount' => 10],
            ['ref' => '010', 'daysAgo' => 3, 'hour' => 9, 'payment' => 'Cash', 'lines' => [[$seed, 5]], 'discount' => 25],
            ['ref' => '011', 'daysAgo' => 3, 'hour' => 13, 'payment' => 'GCash', 'lines' => [[$feed, 2]], 'discount' => 0],
            ['ref' => '012', 'daysAgo' => 3, 'hour' => 15, 'payment' => 'Bank Transfer', 'lines' => [[$rice, 1], [$fert, 2]], 'discount' => 0],
            ['ref' => '013', 'daysAgo' => 4, 'hour' => 10, 'payment' => 'Cash', 'lines' => [[$pest, 1], [$seed, 4]], 'discount' => 0],
            ['ref' => '014', 'daysAgo' => 4, 'hour' => 14, 'payment' => 'GCash', 'lines' => [[$feed, 1]], 'discount' => 0, 'partialRefund' => [$feed, 1]],
            ['ref' => '015', 'daysAgo' => 5, 'hour' => 9, 'payment' => 'Cash', 'lines' => [[$rice, 2], [$fert, 1]], 'discount' => 30],
            ['ref' => '016', 'daysAgo' => 5, 'hour' => 11, 'payment' => 'Bank Transfer', 'lines' => [[$seed, 8]], 'discount' => 0],
            ['ref' => '017', 'daysAgo' => 5, 'hour' => 16, 'payment' => 'Cash', 'lines' => [[$pest, 3]], 'discount' => 0],
            ['ref' => '018', 'daysAgo' => 6, 'hour' => 8, 'payment' => 'GCash', 'lines' => [[$feed, 1], [$rice, 1]], 'discount' => 0],
            ['ref' => '019', 'daysAgo' => 6, 'hour' => 12, 'payment' => 'Cash', 'lines' => [[$fert, 3], [$seed, 2]], 'discount' => 15],
            ['ref' => '020', 'daysAgo' => 6, 'hour' => 15, 'payment' => 'Bank Transfer', 'lines' => [[$rice, 4]], 'discount' => 0],
            ['ref' => '021', 'daysAgo' => 0, 'hour' => 18, 'payment' => 'Cash', 'lines' => [[$seed, 10]], 'discount' => 0],
            ['ref' => '022', 'daysAgo' => 1, 'hour' => 19, 'payment' => 'GCash', 'lines' => [[$pest, 1], [$fert, 1]], 'discount' => 0],
            ['ref' => '023', 'daysAgo' => 3, 'hour' => 11, 'payment' => 'Cash', 'lines' => [[$feed, 1], [$seed, 3]], 'discount' => 0],
            ['ref' => '024', 'daysAgo' => 4, 'hour' => 17, 'payment' => 'GCash', 'lines' => [[$rice, 2]], 'discount' => 0, 'fullRefund' => true],
            ['ref' => '025', 'daysAgo' => 5, 'hour' => 14, 'payment' => 'Cash', 'lines' => [[$fert, 5], [$pest, 1]], 'discount' => 40],
        ];
    }

    /**
     * @param  array<string, mixed>  $plan
     */
    private function createOrder(array $plan, int $cashierId): void
    {
        $soldAt = Carbon::today()
            ->subDays((int) $plan['daysAgo'])
            ->setTime((int) $plan['hour'], 0, 0);

        $lineRows = [];
        $grossItems = 0.0;

        foreach ($plan['lines'] as [$productName, $qty]) {
            $product = $this->catalog[$productName];
            $qty = (int) $qty;
            $price = $product['price'];
            $lineTotal = round($price * $qty, 2);
            $grossItems += $lineTotal;

            $lineRows[] = [
                'product_id' => $product['id'],
                'product_name' => $productName,
                'quantity' => $qty,
                'price' => $price,
                'unit_cost' => $product['cost'],
                'total' => $lineTotal,
            ];
        }

        $discount = round((float) ($plan['discount'] ?? 0), 2);
        $netMerchandise = max(0, round($grossItems - $discount, 2));
        [$vat, $totalAmount] = PosHelpers::saleVatAndTotal($netMerchandise);

        $orderData = [
            'customer_id' => null,
            'subtotal' => $netMerchandise,
            'vat' => $vat,
            'total_amount' => $totalAmount,
            'refunded_amount' => 0,
            'discount_amount' => $discount,
            'coupon_discount' => 0,
            'loyalty_discount' => 0,
            'loyalty_points_redeemed' => 0,
            'client_change' => 0,
            'payment_method' => (string) $plan['payment'],
            'reference' => self::REF_PREFIX.$plan['ref'],
            'status' => 'completed',
            'created_at' => $soldAt,
        ];

        if (Schema::hasColumn('orders', 'branch_id')) {
            $orderData['branch_id'] = 1;
        }
        if (Schema::hasColumn('orders', 'cashier_user_id')) {
            $orderData['cashier_user_id'] = $cashierId;
        }

        $orderId = DB::table('orders')->insertGetId($orderData);
        $itemIds = [];

        foreach ($lineRows as $line) {
            $itemData = [
                'order_id' => $orderId,
                'product_id' => $line['product_id'],
                'product_name' => $line['product_name'],
                'quantity' => $line['quantity'],
                'price' => $line['price'],
                'total' => $line['total'],
                'refunded_quantity' => 0,
                'created_at' => $soldAt,
            ];

            if (Schema::hasColumn('order_items', 'unit_cost')) {
                $itemData['unit_cost'] = $line['unit_cost'];
            }

            $itemIds[] = DB::table('order_items')->insertGetId($itemData);
        }

        if (! empty($plan['fullRefund'])) {
            $this->applyFullRefund($orderId, $itemIds, $lineRows, $soldAt);
        } elseif (! empty($plan['partialRefund'])) {
            [$productName, $qty] = $plan['partialRefund'];
            foreach ($lineRows as $idx => $line) {
                if ($line['product_name'] === $productName) {
                    $this->applyPartialRefund($orderId, $itemIds[$idx], $line, (int) $qty, $soldAt);
                    break;
                }
            }
        }
    }

    /**
     * @param  array<int, int>  $itemIds
     * @param  array<int, array<string, mixed>>  $lineRows
     */
    private function applyFullRefund(int $orderId, array $itemIds, array $lineRows, Carbon $soldAt): void
    {
        if (! Schema::hasTable('refunds')) {
            return;
        }

        $order = DB::table('orders')->where('id', $orderId)->first();
        if (! $order) {
            return;
        }

        $totalRefund = 0.0;
        $refundId = DB::table('refunds')->insertGetId([
            'order_id' => $orderId,
            'refund_type' => 'all',
            'amount' => 0,
            'reason' => '[Accuracy] Full refund test',
            'created_at' => $soldAt->copy()->addHour(),
        ]);

        foreach ($lineRows as $idx => $line) {
            $remaining = (int) $line['quantity'];
            if ($remaining <= 0) {
                continue;
            }

            $merchandise = round($remaining * (float) $line['price'], 2);
            $amount = PosHelpers::refundAmountIncludingVat($order, $merchandise);
            $totalRefund += $amount;

            if (Schema::hasTable('refund_items')) {
                DB::table('refund_items')->insert([
                    'refund_id' => $refundId,
                    'order_item_id' => $itemIds[$idx],
                    'quantity' => $remaining,
                    'amount' => $amount,
                    'created_at' => $soldAt->copy()->addHour(),
                ]);
            }

            DB::table('order_items')
                ->where('id', $itemIds[$idx])
                ->update(['refunded_quantity' => $remaining]);
        }

        DB::table('refunds')->where('id', $refundId)->update(['amount' => round($totalRefund, 2)]);
        DB::table('orders')->where('id', $orderId)->update([
            'refunded_amount' => round($totalRefund, 2),
            'status' => 'refunded',
        ]);
    }

    /**
     * @param  array{product_name: string, quantity: int, price: float}  $line
     */
    private function applyPartialRefund(
        int $orderId,
        int $itemId,
        array $line,
        int $refundQty,
        Carbon $soldAt,
    ): void {
        if (! Schema::hasTable('refunds')) {
            return;
        }

        $order = DB::table('orders')->where('id', $orderId)->first();
        if (! $order) {
            return;
        }

        $refundQty = min($refundQty, (int) $line['quantity']);
        $merchandise = round($refundQty * (float) $line['price'], 2);
        $amount = PosHelpers::refundAmountIncludingVat($order, $merchandise);

        $refundId = DB::table('refunds')->insertGetId([
            'order_id' => $orderId,
            'refund_type' => 'items',
            'amount' => $amount,
            'reason' => '[Accuracy] Partial refund test',
            'created_at' => $soldAt->copy()->addHour(),
        ]);

        if (Schema::hasTable('refund_items')) {
            DB::table('refund_items')->insert([
                'refund_id' => $refundId,
                'order_item_id' => $itemId,
                'quantity' => $refundQty,
                'amount' => $amount,
                'created_at' => $soldAt->copy()->addHour(),
            ]);
        }

        DB::table('order_items')->where('id', $itemId)->update(['refunded_quantity' => $refundQty]);
        DB::table('orders')->where('id', $orderId)->update(['refunded_amount' => $amount]);
    }

    private function printVerification(): void
    {
        $start = Carbon::today()->subDays(6)->format('Y-m-d');
        $end = Carbon::today()->format('Y-m-d');

        $request = Request::create('/pos/reports/summary', 'GET', [
            'start' => $start,
            'end' => $end,
        ]);

        $service = app(ReportService::class);
        [$startDt, $endDt] = $service->resolveRange($request);
        $summary = $service->summary($startDt, $endDt);

        $reconcile = round((float) ($summary['sales_reconcile'] ?? 0), 2);
        $netSales = round((float) $summary['net_sales'], 2);
        $match = abs($reconcile - $netSales) < 0.02;

        $this->command?->newLine();
        $this->command?->info('=== Report accuracy check (This Week: '.$start.' → '.$end.') ===');
        $this->command?->line('  Orders:          '.$summary['order_count']);
        $this->command?->line('  Net sales:       ₱'.number_format($netSales, 2));
        $this->command?->line('  Net merchandise: ₱'.number_format((float) $summary['net_merchandise'], 2));
        $this->command?->line('  VAT kept:        ₱'.number_format((float) $summary['vat_collected'], 2).' (tax_rate '.((float) ($summary['tax_rate'] ?? 0) * 100).'%)');
        $this->command?->line('  Refunds:         ₱'.number_format((float) $summary['refunded_amount'], 2));
        $this->command?->line('  COGS:            ₱'.number_format((float) $summary['cogs'], 2));
        $this->command?->line('  Tubo (profit):   ₱'.number_format((float) $summary['gross_profit'], 2));
        $this->command?->line('  Reconcile:       merch + VAT = ₱'.number_format($reconcile, 2).' → '.($match ? 'MATCHES net sales ✓' : 'MISMATCH ✗'));

        if (! $match) {
            $this->command?->warn('  Expected net sales ≈ net merchandise + VAT kept after refunds.');
        }

        $this->command?->newLine();
        $this->command?->info('Open Reports → This Week, or Dashboard, to verify in the UI.');
    }
}
