<?php

namespace Database\Seeders;

use Carbon\Carbon;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Demo customers, loyalty cards, and today's cash drawer activity.
 */
class PosDemoDataSeeder extends Seeder
{
    private const DEMO_PREFIX = '[Demo] ';

    public function run(): void
    {
        if (! Schema::hasTable('customers')) {
            $this->command?->warn('Customer tables missing. Run migrations first.');

            return;
        }

        if (! DB::table('users')->exists()) {
            $this->call(PosDatabaseSeeder::class);
        }

        $this->purgeDemoData();
        $customers = $this->seedCustomers();
        $this->seedLoyaltyCards($customers);
        $this->seedCashDrawer();

        $this->command?->info('Demo customers, loyalty cards, and cash drawer seeded.');
    }

    private function purgeDemoData(): void
    {
        $demoCustomerIds = DB::table('customers')
            ->where('customer_name', 'like', self::DEMO_PREFIX.'%')
            ->pluck('id')
            ->all();

        if ($demoCustomerIds !== [] && Schema::hasTable('loyalty_cards')) {
            DB::table('loyalty_cards')->whereIn('customer_id', $demoCustomerIds)->delete();
        }

        DB::table('customers')
            ->where('customer_name', 'like', self::DEMO_PREFIX.'%')
            ->delete();

        if (! Schema::hasTable('cash_drawer_sessions')) {
            return;
        }

        $sessionIds = DB::table('cash_drawer_sessions')
            ->where('business_date', '>=', Carbon::today()->subDays(7)->toDateString())
            ->pluck('id')
            ->all();

        if ($sessionIds === []) {
            return;
        }

        if (Schema::hasTable('drawer_expenses')) {
            DB::table('drawer_expenses')->whereIn('session_id', $sessionIds)->delete();
        }
        if (Schema::hasTable('cash_additions')) {
            DB::table('cash_additions')->whereIn('session_id', $sessionIds)->delete();
        }
        DB::table('cash_drawer_sessions')->whereIn('id', $sessionIds)->delete();
    }

    /**
     * @return list<array{id: int, name: string, order_type: string}>
     */
    private function seedCustomers(): array
    {
        $rows = [
            ['Dinah De Vera', 'Dealer — San Simon', 'Wholesale'],
            ['Vincent Caragan', 'Regular suki', 'Retail'],
            ['Mary Salvador', 'San Gabriel, Pampanga', 'Retail'],
            ['Juan Dela Cruz', 'Poultry farm — Bacolor', 'Wholesale'],
            ['Rosa Mendoza', 'Rice & vegetable farm', 'Retail'],
            ['Pedro Aguilar', 'Egg producer — Mexico', 'Wholesale'],
        ];

        $customers = [];
        foreach ($rows as $index => [$name, $note, $type]) {
            $label = self::DEMO_PREFIX.$name;
            $id = DB::table('customers')->insertGetId([
                'customer_name' => $label,
                'table_name' => $note,
                'order_type' => $type,
                'created_at' => now()->subDays(45 + ($index * 12)),
            ]);

            $customers[] = ['id' => $id, 'name' => $label, 'order_type' => $type];
        }

        return $customers;
    }

    /**
     * @param  list<array{id: int, name: string, order_type: string}>  $customers
     */
    private function seedLoyaltyCards(array $customers): void
    {
        if (! Schema::hasTable('loyalty_cards')) {
            return;
        }

        $hasNfc = Schema::hasColumn('loyalty_cards', 'nfc_uid');
        $nfcUids = ['04A1B2C3D4E5F6', '04112233445566', '04FFEEDDCCBBAA'];

        foreach ($customers as $index => $customer) {
            $points = match ($customer['order_type']) {
                'Wholesale' => 850 + ($index * 120),
                default => 180 + ($index * 45),
            };

            $tier = $points >= 800 ? 'Gold' : ($points >= 400 ? 'Silver' : 'Bronze');
            $cardNumber = 'GFM-'.str_pad((string) ($index + 1), 5, '0', STR_PAD_LEFT);

            $row = [
                'customer_id' => $customer['id'],
                'card_number' => $cardNumber,
                'points' => $points,
                'tier' => $tier,
                'status' => 'Active',
                'created_at' => now()->subDays(20 - $index),
                'updated_at' => now(),
            ];

            if ($hasNfc && isset($nfcUids[$index])) {
                $row['nfc_uid'] = $nfcUids[$index];
            }

            DB::table('loyalty_cards')->insert($row);
        }
    }

    private function seedCashDrawer(): void
    {
        if (! Schema::hasTable('cash_drawer_sessions')) {
            return;
        }

        $cashierId = (int) (DB::table('users')->where('role', 'cashier')->value('id') ?? 1);
        $managerId = (int) (DB::table('users')->where('role', 'admin')->value('id') ?? $cashierId);
        $businessDate = Carbon::today()->toDateString();

        $sessionId = DB::table('cash_drawer_sessions')->insertGetId([
            'business_date' => $businessDate,
            'starting_cash' => 5000.00,
            'created_by_user_id' => $managerId,
            'updated_by_user_id' => $managerId,
            'created_at' => Carbon::today()->setTime(6, 30),
            'updated_at' => now(),
        ]);

        if (Schema::hasTable('cash_additions')) {
            DB::table('cash_additions')->insert([
                [
                    'session_id' => $sessionId,
                    'amount' => 2000.00,
                    'remarks' => 'Additional float from vault',
                    'created_by_user_id' => $managerId,
                    'created_at' => Carbon::today()->setTime(7, 15),
                ],
                [
                    'session_id' => $sessionId,
                    'amount' => 500.00,
                    'remarks' => 'Change coins refill',
                    'created_by_user_id' => $cashierId,
                    'created_at' => Carbon::today()->setTime(10, 45),
                ],
            ]);
        }

        if (! Schema::hasTable('drawer_expenses')) {
            return;
        }

        $hasReference = Schema::hasColumn('drawer_expenses', 'reference_no');
        $hasSeries = Schema::hasColumn('drawer_expenses', 'series_no');

        $expenses = [
            ['Delivery fee — feeds truck', 450.00, 'cash', 'CHK-88421'],
            ['Office supplies (receipt book)', 185.00, 'cash', null],
            ['Water bill partial payment', 320.00, 'gcash', null],
            ['Broom & cleaning supplies', 95.00, 'cash', null],
        ];

        foreach ($expenses as $index => [$name, $amount, $paymentType, $seriesNo]) {
            $row = [
                'session_id' => $sessionId,
                'name' => $name,
                'amount' => $amount,
                'payment_type' => $paymentType,
                'created_by_user_id' => $cashierId,
                'updated_by_user_id' => $cashierId,
                'created_at' => Carbon::today()->setTime(8 + $index, 20 + ($index * 10)),
                'updated_at' => now(),
            ];

            if ($hasReference) {
                $row['reference_no'] = sprintf('%s-%03d', $businessDate, $index + 1);
            }
            if ($hasSeries) {
                $row['series_no'] = $seriesNo;
            }

            DB::table('drawer_expenses')->insert($row);
        }
    }
}
