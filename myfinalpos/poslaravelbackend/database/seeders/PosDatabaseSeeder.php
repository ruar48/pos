<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class PosDatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $passwordHash = password_hash('password', PASSWORD_BCRYPT);

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

        $users = [
            ['Ricardo Santos', 'admin', 'admin@agriculture.local', 'admin'],
            ['Ana Reyes', 'cashier', 'cashier@agriculture.local', 'cashier'],
            ['Pedro Santos', 'labor_pedro', 'labor+pedro@no-login.local', 'labor'],
        ];

        foreach ($users as [$fullName, $username, $email, $role]) {
            DB::table('users')->updateOrInsert(
                ['email' => $email],
                [
                    'full_name' => $fullName,
                    'username' => $username,
                    'password_hash' => $passwordHash,
                    'role' => $role,
                    'status' => 1,
                    'branch_id' => 1,
                    'email_verified_at' => now(),
                    'created_at' => now(),
                ],
            );
        }

        $receiptStore = [
            'logo_text' => '[ Green Farm Mart ]',
            'logo_image_url' => null,
            'logo_image_base64' => null,
            'store_name' => 'GREEN FARM MART',
            'store_subtitle' => 'FEEDS · FERTILIZERS · FARM SUPPLIES',
            'address_line1' => 'McArthur Highway, Brgy. San Juan,',
            'address_line2' => 'San Fernando City, Pampanga 2000',
            'tin' => '123-456-789-000',
            'tax_status' => 'NON-VAT REGISTERED',
            'pos_terminal_id' => 'POS-TAB-01',
            'ptu_no' => 'PTU-123456789',
            'atp_no' => 'ATP-987654321',
            'atp_date_issued' => '01/15/2026',
            'series_range' => '0000001 - 9999999',
        ];

        $settings = [
            'tax_rate' => 0,
            'auto_print_receipt' => 1,
            'double_print_receipt' => 0,
            'printer_host' => '192.168.1.50',
            'printer_type' => 'network',
            'printer_device' => '',
            'printer_port' => 9100,
            'allow_negative_stock' => 0,
            'loyalty_enabled' => 1,
            'loyalty_points_per_unit' => 50,
            'loyalty_spend_unit' => 1000,
            'loyalty_redeem_points_per_peso' => 10,
            'currency_symbol' => 'PHP',
            'settings_pin' => '1234',
            'default_branch_id' => 1,
            'attendance_start_time' => '08:00',
            'attendance_grace_minutes' => 15,
            'attendance_lunch_out_time' => '12:00',
            'attendance_afternoon_in_time' => '13:30',
            'attendance_day_end_time' => '16:30',
            'attendance_morning_absent_after_time' => '09:00',
            'attendance_morning_accept_start' => '06:30',
            'attendance_morning_official_start' => '08:00',
            'attendance_morning_grace_end' => '08:15',
            'attendance_morning_late_start' => '08:16',
            'attendance_morning_cutoff' => '09:00',
            'attendance_break_out_start' => '11:00',
            'attendance_break_out_end' => '12:00',
            'attendance_afternoon_accept_start' => '12:50',
            'attendance_afternoon_on_time_end' => '13:30',
            'attendance_afternoon_late_start' => '13:31',
            'attendance_afternoon_cutoff' => '14:00',
            'attendance_timeout_start' => '16:30',
            'updated_by' => 1,
            'created_at' => now(),
            'updated_at' => now(),
        ];

        if (Schema::hasColumn('app_settings', 'receipt_store_json')) {
            $settings['receipt_store_json'] = json_encode($receiptStore, JSON_UNESCAPED_UNICODE);
        }

        DB::table('app_settings')->updateOrInsert(['id' => 1], $settings);

        $categories = [
            ['Seeds', 'eco', 'Hybrid corn, rice, and vegetable seeds'],
            ['Fertilizers', 'compost', 'Complete, urea, organic, and foliar fertilizers'],
            ['Pesticides', 'shield', 'Insecticides, fungicides, and organic crop protection'],
            ['Tools & Equipment', 'build', 'Hand tools, sprayers, and field equipment'],
            ['Irrigation', 'water_drop', 'Drip lines, sprinklers, and hoses'],
            ['Animal Feed', 'pets', 'Poultry, swine, and livestock feeds'],
            ['Seedlings', 'local_florist', 'Vegetable and crop seedlings'],
            ['Harvest Supplies', 'inventory_2', 'Crates, sacks, and post-harvest materials'],
        ];

        foreach ($categories as [$name, $icon, $description]) {
            DB::table('categories')->updateOrInsert(
                ['name' => $name],
                ['icon' => $icon, 'description' => $description],
            );
        }

        $hasDeal = Schema::hasColumn('products', 'deal');

        /** @var list<array{0: string, 1: string, 2: float, 3: float, 4: int, 5: int, 6: ?string}> */
        $products = [
            ['Animal Feed', 'ACC Feeds 40kg', 1280.00, 985.00, 478, 80, null],
            ['Animal Feed', 'ACC Rice 25kg', 890.00, 695.00, 75, 20, null],
            ['Animal Feed', 'Layer Mash 50kg', 1650.00, 1280.00, 42, 15, null],
            ['Animal Feed', 'Broiler Starter 40kg', 1420.00, 1105.00, 38, 12, 'Free measuring scoop'],
            ['Fertilizers', 'Complete 14-14-14 (50kg)', 1920.00, 1485.00, 64, 20, null],
            ['Fertilizers', 'Urea 46-0-0 (50kg)', 1850.00, 1430.00, 52, 18, null],
            ['Fertilizers', 'Organic Compost (25kg)', 185.00, 125.00, 120, 30, null],
            ['Seeds', 'Hybrid Corn Seed (9kg)', 2850.00, 2200.00, 28, 8, null],
            ['Seeds', 'Rice Seed NSIC Rc222 (20kg)', 1650.00, 1280.00, 35, 10, null],
            ['Pesticides', 'Neem Oil 1L', 395.00, 265.00, 48, 12, null],
            ['Pesticides', 'Lambda-Cyhalothrin 1L', 520.00, 385.00, 22, 8, null],
            ['Tools & Equipment', 'Steel Hand Hoe', 385.00, 245.00, 18, 5, null],
            ['Tools & Equipment', 'Pruning Shears 8"', 295.00, 185.00, 24, 6, null],
            ['Irrigation', 'Drip Tape Roll 1000m', 3200.00, 2480.00, 8, 2, null],
            ['Irrigation', 'Sprinkler Head', 85.00, 52.00, 110, 25, null],
            ['Seedlings', 'Tomato Seedlings (128-cell)', 145.00, 95.00, 65, 15, null],
            ['Seedlings', 'Pepper Seedlings (128-cell)', 135.00, 88.00, 58, 15, null],
            ['Harvest Supplies', 'Plastic Produce Crate', 220.00, 145.00, 140, 30, null],
            ['Harvest Supplies', 'Jute Sack 50kg', 28.00, 16.00, 400, 100, null],
        ];

        foreach ($products as [$categoryName, $name, $price, $cost, $stock, $reorder, $deal]) {
            $categoryId = DB::table('categories')->where('name', $categoryName)->value('id');
            if (! $categoryId) {
                continue;
            }

            $row = [
                'category_id' => $categoryId,
                'name' => $name,
                'description' => "Farm supply: {$name}",
                'price' => $price,
                'cost_price' => $cost,
                'stock' => $stock,
                'reorder_level' => $reorder,
                'image_url' => null,
                'status' => 'active',
                'created_at' => now(),
                'updated_at' => now(),
            ];

            if ($hasDeal) {
                $row['deal'] = $deal;
            }

            DB::table('products')->updateOrInsert(
                ['category_id' => $categoryId, 'name' => $name],
                $row,
            );
        }

        $today = now()->toDateString();
        $endDate = now()->addMonths(6)->toDateString();

        $coupons = [
            ['SUKI50', 'Suki discount — ₱50 off feed or fertilizer purchase', 'fixed', 50.00, 500.00],
            ['GROWMORE100', 'Planting season promo — ₱100 off', 'fixed', 100.00, 1500.00],
            ['HARVEST20', 'Harvest month special — ₱20 off any order', 'fixed', 20.00, 0.00],
        ];

        foreach ($coupons as [$code, $description, $type, $value, $minOrder]) {
            DB::table('coupons')->updateOrInsert(
                ['code' => $code],
                [
                    'description' => $description,
                    'discount_type' => $type,
                    'discount_value' => $value,
                    'min_order_amount' => $minOrder,
                    'start_date' => $today,
                    'end_date' => $endDate,
                    'max_uses' => null,
                    'usage_count' => 0,
                    'status' => 1,
                    'created_at' => now(),
                ],
            );
        }

        $this->command?->info('Seeded branch, users, settings, categories, products, and coupons (PHP prices).');
    }
}
