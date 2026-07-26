<?php

namespace Database\Seeders;

use App\Support\PosHelpers;
use Carbon\Carbon;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class ReportSampleSeeder extends Seeder
{
    private const REF_PREFIX = 'SAMPLE-RPT-';

    public function run(): void
    {
        if (! Schema::hasTable('orders') || ! Schema::hasTable('order_items')) {
            $this->command?->warn('Order tables missing. Run migrations first.');

            return;
        }

        if (! DB::table('products')->exists()) {
            $this->call(PosDatabaseSeeder::class);
        }

        $this->purgeSampleData();

        $cashierId = (int) (DB::table('users')->where('role', 'cashier')->value('id')
            ?? DB::table('users')->value('id')
            ?? 1);

        $products = DB::table('products')
            ->select('id', 'name', 'price', 'cost_price')
            ->where('status', 'active')
            ->orderBy('id')
            ->get()
            ->all();

        if ($products === []) {
            $this->command?->warn('No products found. Run PosDatabaseSeeder first.');

            return;
        }

        $customers = $this->seedCustomers();
        $orderCount = $this->seedOrders($products, $customers, $cashierId);
        $this->seedAuditLogs($cashierId);

        $this->command?->info("Report sample data ready: {$orderCount} orders across the last 14 days.");
        $this->command?->info('Open Reports → This Week or This Month to preview charts and tubo.');
    }

    private function purgeSampleData(): void
    {
        $sampleOrderIds = DB::table('orders')
            ->where('reference', 'like', self::REF_PREFIX.'%')
            ->pluck('id')
            ->all();

        if ($sampleOrderIds !== []) {
            if (Schema::hasTable('refund_items') && Schema::hasTable('refunds')) {
                $refundIds = DB::table('refunds')
                    ->whereIn('order_id', $sampleOrderIds)
                    ->pluck('id')
                    ->all();

                if ($refundIds !== []) {
                    DB::table('refund_items')->whereIn('refund_id', $refundIds)->delete();
                    DB::table('refunds')->whereIn('id', $refundIds)->delete();
                }
            }

            DB::table('order_items')->whereIn('order_id', $sampleOrderIds)->delete();
            DB::table('orders')->whereIn('id', $sampleOrderIds)->delete();
        }

        DB::table('customers')
            ->where('customer_name', 'like', '[Sample]%')
            ->delete();

        if (Schema::hasTable('audit_logs')) {
            DB::table('audit_logs')
                ->where('description', 'like', '[Sample]%')
                ->delete();
        }
    }

    /**
     * @return array<int, array{id: int, name: string}>
     */
    private function seedCustomers(): array
    {
        $rows = [
            ['Dinah De Vera', 'Dealer', 'Retail'],
            ['Vincent Caragan', 'Suki', 'Retail'],
            ['MARY SALVADOR', 'San Gabriel 1st', 'Retail'],
            ['Tad', 'BLO', 'Retail'],
            ['Juan Dela Cruz', 'Wholesale', 'Wholesale'],
            ['Rosa Mendoza', 'Regular', 'Retail'],
        ];

        $customers = [];
        foreach ($rows as [$name, $note, $type]) {
            $label = '[Sample] '.$name;
            $existingId = DB::table('customers')->where('customer_name', $label)->value('id');

            if ($existingId) {
                $customers[] = ['id' => (int) $existingId, 'name' => $label];

                continue;
            }

            $id = DB::table('customers')->insertGetId([
                'customer_name' => $label,
                'table_name' => $note,
                'order_type' => $type,
                'created_at' => now(),
            ]);

            $customers[] = ['id' => $id, 'name' => $label];
        }

        return $customers;
    }

    /**
     * @param  array<int, object>  $products
     * @param  array<int, array{id: int, name: string}>  $customers
     */
    private function seedOrders(array $products, array $customers, int $cashierId): int
    {
        $hasBranch = Schema::hasColumn('orders', 'branch_id');
        $hasCashier = Schema::hasColumn('orders', 'cashier_user_id');
        $hasUnitCost = Schema::hasColumn('order_items', 'unit_cost');
        $hasVariety = Schema::hasColumn('order_items', 'variety_id');

        $paymentMethods = ['Cash', 'Cash', 'Cash', 'GCash', 'GCash', 'Bank Transfer'];
        $productCount = count($products);
        $created = 0;

        $plans = [
            ['daysAgo' => 0, 'hour' => 10, 'customer' => 0, 'lines' => [0, 2], 'payment' => 0, 'discount' => 0],
            ['daysAgo' => 0, 'hour' => 14, 'customer' => null, 'lines' => [1, 5], 'payment' => 1, 'discount' => 0],
            ['daysAgo' => 1, 'hour' => 9, 'customer' => 1, 'lines' => [2, 3, 7], 'payment' => 0, 'discount' => 50],
            ['daysAgo' => 1, 'hour' => 16, 'customer' => 2, 'lines' => [4, 8], 'payment' => 3, 'discount' => 0],
            ['daysAgo' => 2, 'hour' => 11, 'customer' => 3, 'lines' => [0, 1, 9], 'payment' => 0, 'discount' => 0],
            ['daysAgo' => 3, 'hour' => 8, 'customer' => 4, 'lines' => [5, 6, 10, 11], 'payment' => 5, 'discount' => 100],
            ['daysAgo' => 3, 'hour' => 15, 'customer' => null, 'lines' => [12], 'payment' => 0, 'discount' => 0],
            ['daysAgo' => 4, 'hour' => 10, 'customer' => 5, 'lines' => [3, 13], 'payment' => 4, 'discount' => 0],
            ['daysAgo' => 5, 'hour' => 13, 'customer' => 0, 'lines' => [2, 14], 'payment' => 1, 'discount' => 0, 'refundLine' => 0],
            ['daysAgo' => 6, 'hour' => 9, 'customer' => 1, 'lines' => [7, 8, 15], 'payment' => 0, 'discount' => 0],
            ['daysAgo' => 7, 'hour' => 17, 'customer' => null, 'lines' => [0, 4], 'payment' => 2, 'discount' => 0],
            ['daysAgo' => 8, 'hour' => 10, 'customer' => 2, 'lines' => [6, 9, 10], 'payment' => 3, 'discount' => 25],
            ['daysAgo' => 9, 'hour' => 12, 'customer' => 3, 'lines' => [1, 11], 'payment' => 0, 'discount' => 0],
            ['daysAgo' => 10, 'hour' => 8, 'customer' => 4, 'lines' => [5, 12, 13, 14], 'payment' => 5, 'discount' => 0],
            ['daysAgo' => 11, 'hour' => 14, 'customer' => 5, 'lines' => [2], 'payment' => 4, 'discount' => 0],
            ['daysAgo' => 12, 'hour' => 11, 'customer' => 0, 'lines' => [3, 4, 8], 'payment' => 0, 'discount' => 0],
            ['daysAgo' => 13, 'hour' => 16, 'customer' => null, 'lines' => [0, 15], 'payment' => 1, 'discount' => 0],
            ['daysAgo' => 6, 'hour' => 15, 'customer' => 2, 'lines' => [10, 11, 12], 'payment' => 2, 'discount' => 0],
            ['daysAgo' => 2, 'hour' => 18, 'customer' => 5, 'lines' => [0, 6], 'payment' => 0, 'discount' => 0],
            ['daysAgo' => 4, 'hour' => 12, 'customer' => 1, 'lines' => [7, 9, 14, 15], 'payment' => 3, 'discount' => 75],
        ];

        foreach ($plans as $index => $plan) {
            $productIndexes = array_map(
                static fn (int $i) => $i % $productCount,
                $plan['lines'],
            );

            $soldAt = Carbon::today()
                ->subDays($plan['daysAgo'])
                ->setTime($plan['hour'], ($index % 5) * 7, 0);

            $customerId = $plan['customer'] !== null
                ? $customers[$plan['customer']]['id']
                : null;

            $paymentMethod = $paymentMethods[$plan['payment'] % count($paymentMethods)];
            $discount = (float) ($plan['discount'] ?? 0);

            $lineRows = [];
            $subtotal = 0.0;

            foreach ($productIndexes as $lineIdx => $pIndex) {
                $product = $products[$pIndex];
                $qty = 1 + (($index + $lineIdx) % 4);
                $price = round((float) $product->price, 2);
                $unitCost = round((float) ($product->cost_price ?? $price * 0.72), 2);
                $lineTotal = round($price * $qty, 2);
                $subtotal += $lineTotal;

                $lineRows[] = [
                    'product_id' => (int) $product->id,
                    'product_name' => (string) $product->name,
                    'quantity' => $qty,
                    'price' => $price,
                    'unit_cost' => $unitCost,
                    'total' => $lineTotal,
                    'refunded_quantity' => 0,
                ];
            }

            $grossItems = round($subtotal, 2);
            $netMerchandise = max(0, round($grossItems - $discount, 2));
            [$vat, $totalAmount] = PosHelpers::saleVatAndTotal($netMerchandise);

            $orderData = [
                'customer_id' => $customerId,
                'subtotal' => $netMerchandise,
                'vat' => $vat,
                'total_amount' => $totalAmount,
                'refunded_amount' => 0,
                'discount_amount' => $discount,
                'coupon_discount' => 0,
                'loyalty_discount' => 0,
                'loyalty_points_redeemed' => 0,
                'client_change' => $paymentMethod === 'Cash' ? round(max(0, ceil($totalAmount / 10) * 10 - $totalAmount), 2) : 0,
                'payment_method' => $paymentMethod,
                'reference' => self::REF_PREFIX.str_pad((string) ($index + 1), 3, '0', STR_PAD_LEFT),
                'status' => 'completed',
                'created_at' => $soldAt,
            ];

            if ($hasBranch) {
                $orderData['branch_id'] = 1;
            }
            if ($hasCashier) {
                $orderData['cashier_user_id'] = $cashierId;
            }

            $orderId = DB::table('orders')->insertGetId($orderData);

            foreach ($lineRows as $lineIdx => $line) {
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

                if ($hasUnitCost) {
                    $itemData['unit_cost'] = $line['unit_cost'];
                }
                if ($hasVariety) {
                    $itemData['variety_id'] = null;
                    $itemData['variety_name'] = null;
                }

                $itemId = DB::table('order_items')->insertGetId($itemData);

                if (isset($plan['refundLine']) && (int) $plan['refundLine'] === $lineIdx) {
                    $this->applyPartialRefund($orderId, $itemId, $line, $soldAt);
                }
            }

            $created++;
        }

        return $created;
    }

    /**
     * @param  array{quantity: int, price: float, total: float, product_name: string}  $line
     */
    private function applyPartialRefund(int $orderId, int $itemId, array $line, Carbon $soldAt): void
    {
        if (! Schema::hasTable('refunds')) {
            return;
        }

        $refundQty = min(1, (int) $line['quantity']);
        $order = DB::table('orders')->where('id', $orderId)->first();
        $merchandise = round($refundQty * (float) $line['price'], 2);
        $refundAmount = $order
            ? PosHelpers::refundAmountIncludingVat($order, $merchandise)
            : $merchandise;

        $refundId = DB::table('refunds')->insertGetId([
            'order_id' => $orderId,
            'refund_type' => 'items',
            'amount' => $refundAmount,
            'reason' => '[Sample] Customer returned damaged item',
            'created_at' => $soldAt->copy()->addHours(2),
        ]);

        if (Schema::hasTable('refund_items')) {
            DB::table('refund_items')->insert([
                'refund_id' => $refundId,
                'order_item_id' => $itemId,
                'quantity' => $refundQty,
                'amount' => $refundAmount,
                'created_at' => $soldAt->copy()->addHours(2),
            ]);
        }

        DB::table('order_items')
            ->where('id', $itemId)
            ->update(['refunded_quantity' => $refundQty]);

        DB::table('orders')
            ->where('id', $orderId)
            ->update(['refunded_amount' => $refundAmount]);
    }

    private function seedAuditLogs(int $userId): void
    {
        if (! Schema::hasTable('audit_logs')) {
            return;
        }

        $entries = [
            ['adjust', 'inventory', 'product', 1, '[Sample] Stock adjusted +25 bags for Hybrid Corn Seed'],
            ['update', 'items', 'product', 2, '[Sample] Updated retail price for Rice Seed Premium'],
            ['create', 'orders', 'order', null, '[Sample] Completed walk-in sale at register 1'],
            ['adjust', 'inventory', 'product', 4, '[Sample] Received fertilizer delivery (+40 bags)'],
            ['login', 'auth', 'user', $userId, '[Sample] Cashier signed in for morning shift'],
        ];

        foreach ($entries as $idx => [$action, $module, $entityType, $entityId, $description]) {
            DB::table('audit_logs')->insert([
                'user_id' => $userId,
                'action' => $action,
                'module' => $module,
                'entity_type' => $entityType,
                'entity_id' => $entityId,
                'description' => $description,
                'payload_json' => null,
                'created_at' => Carbon::now()->subDays(13 - $idx)->setTime(8 + $idx, 15, 0),
            ]);
        }
    }
}
