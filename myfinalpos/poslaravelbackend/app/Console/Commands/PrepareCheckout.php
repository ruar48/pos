<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class PrepareCheckout extends Command
{
    protected $signature = 'pos:prepare-checkout
                            {--test-order : Save one demo walk-in sale through the orders API}';

    protected $description = 'Verify checkout schema, refresh demo stock, and optionally post a test sale';

    public function handle(): int
    {
        if (! Schema::hasTable('orders') || ! Schema::hasTable('order_items')) {
            $this->error('Order tables missing. Run: php artisan migrate --force');

            return self::FAILURE;
        }

        $issues = $this->auditSchema();
        if ($issues !== []) {
            $this->error('Checkout schema is incomplete. Run: php artisan migrate --force');
            foreach ($issues as $issue) {
                $this->line("  - {$issue}");
            }

            return self::FAILURE;
        }

        $this->ensureBranch();
        $this->refreshCheckoutStock();
        $this->info('Checkout stock refreshed on in-stock products.');

        if ($this->option('test-order')) {
            return $this->postTestOrder();
        }

        $this->info('Ready for tablet checkout. Run with --test-order to save one demo sale.');

        return self::SUCCESS;
    }

    /**
     * @return list<string>
     */
    private function auditSchema(): array
    {
        $issues = [];

        foreach ([
            'branch_id',
            'cashier_user_id',
            'subtotal',
            'vat',
            'total_amount',
            'client_change',
            'payment_method',
            'status',
            'refunded_amount',
            'discount_amount',
            'coupon_discount',
            'loyalty_discount',
            'loyalty_points_redeemed',
            'created_at',
        ] as $column) {
            if (! Schema::hasColumn('orders', $column)) {
                $issues[] = "orders.{$column} is missing";
            }
        }

        foreach ([
            'order_id',
            'product_id',
            'product_name',
            'quantity',
            'price',
            'total',
            'refunded_quantity',
            'created_at',
        ] as $column) {
            if (! Schema::hasColumn('order_items', $column)) {
                $issues[] = "order_items.{$column} is missing";
            }
        }

        return $issues;
    }

    private function ensureBranch(): void
    {
        if (! Schema::hasTable('branches')) {
            return;
        }

        DB::table('branches')->updateOrInsert(
            ['id' => 1],
            [
                'name' => 'Green Farm Mart — San Fernando',
                'code' => 'GFM-SF',
                'location' => 'McArthur Highway, San Fernando, Pampanga',
                'latitude' => 15.0319000,
                'longitude' => 120.6895000,
                'geofence_radius_km' => 0.50,
                'is_active' => 1,
                'created_at' => now(),
            ],
        );
    }

    private function refreshCheckoutStock(): void
    {
        if (! Schema::hasTable('products')) {
            return;
        }

        DB::table('products')
            ->where('stock', '<', 10)
            ->update([
                'stock' => DB::raw('GREATEST(stock, 25)'),
                'updated_at' => now(),
            ]);
    }

    private function postTestOrder(): int
    {
        $product = DB::table('products')
            ->where('stock', '>', 0)
            ->orderBy('id')
            ->first(['id', 'name', 'price', 'stock']);

        if ($product === null) {
            $this->error('No product with stock found. Import products first.');

            return self::FAILURE;
        }

        $price = round((float) $product->price, 2);
        $payload = [
            'is_walk_in' => true,
            'items' => [
                [
                    'product_id' => (int) $product->id,
                    'quantity' => 1,
                ],
            ],
            'subtotal' => $price,
            'vat' => 0,
            'total_amount' => $price,
            'client_change' => 0,
            'payment_method' => 'Cash',
            'reference' => '',
            'discount_amount' => 0,
            'coupon_discount' => 0,
            'loyalty_discount' => 0,
            'loyalty_points_redeemed' => 0,
            'branch_id' => 1,
            'actor_user_id' => 1,
            'receipt_note' => '[Demo] Tablet checkout test',
        ];

        $request = Request::create('/pos_app/orders.php', 'POST', $payload);
        $response = app()->handle($request);
        $body = json_decode($response->getContent(), true);

        if ($response->getStatusCode() === 201 && ($body['success'] ?? false) === true) {
            $orderId = (int) ($body['order_id'] ?? 0);
            $this->info("Demo order saved: INV-".str_pad((string) $orderId, 6, '0', STR_PAD_LEFT));
            $this->line("Product: {$product->name} (PHP {$price})");

            return self::SUCCESS;
        }

        $this->error('Test order failed: '.($body['message'] ?? 'Unknown error'));

        return self::FAILURE;
    }
}
