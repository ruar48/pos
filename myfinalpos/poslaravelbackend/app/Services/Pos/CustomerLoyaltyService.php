<?php

namespace App\Services\Pos;

use App\Support\PosHelpers;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class CustomerLoyaltyService
{
    /**
     * @return array<string, mixed>
     */
    public function overview(): array
    {
        if (! Schema::hasTable('loyalty_cards')) {
            return [
                'members' => 0,
                'total_points' => 0,
                'active_cards' => 0,
                'tiers' => [],
            ];
        }

        $summary = DB::selectOne(
            'SELECT
                COUNT(*) AS members,
                COALESCE(SUM(points), 0) AS total_points,
                SUM(CASE WHEN status = "Active" THEN 1 ELSE 0 END) AS active_cards
             FROM loyalty_cards lc
             INNER JOIN customers c ON c.id = lc.customer_id
             WHERE '.PosHelpers::walkInCustomerSqlExclusion('c.customer_name'),
        );

        $tiers = DB::select(
            'SELECT lc.tier, COUNT(*) AS members, COALESCE(SUM(lc.points), 0) AS points
             FROM loyalty_cards lc
             INNER JOIN customers c ON c.id = lc.customer_id
             WHERE '.PosHelpers::walkInCustomerSqlExclusion('c.customer_name').'
             GROUP BY lc.tier
             ORDER BY points DESC',
        );

        return [
            'members' => (int) ($summary->members ?? 0),
            'total_points' => (int) ($summary->total_points ?? 0),
            'active_cards' => (int) ($summary->active_cards ?? 0),
            'tiers' => array_map(static fn ($row) => [
                'tier' => (string) $row->tier,
                'members' => (int) $row->members,
                'points' => (int) $row->points,
            ], $tiers),
        ];
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function customersWithPoints(?string $search = null): array
    {
        if (! Schema::hasTable('customers')) {
            return [];
        }

        $walkIn = PosHelpers::walkInCustomerSqlExclusion('c.customer_name');
        $searchSql = '';
        $params = [];

        $hasNfcUid = Schema::hasTable('loyalty_cards')
            && Schema::hasColumn('loyalty_cards', 'nfc_uid');

        if ($search !== null && trim($search) !== '') {
            $nfcSearch = $hasNfcUid ? ' OR lc.nfc_uid LIKE :search' : '';
            $searchSql = "AND (c.customer_name LIKE :search OR c.table_name LIKE :search OR lc.card_number LIKE :search{$nfcSearch})";
            $params['search'] = '%'.trim($search).'%';
        }

        $hasCards = Schema::hasTable('loyalty_cards');
        $hasOrders = Schema::hasTable('orders');

        $cardJoin = $hasCards
            ? 'LEFT JOIN loyalty_cards lc ON lc.customer_id = c.id'
            : '';
        $nfcSelect = $hasNfcUid ? 'lc.nfc_uid,' : 'NULL AS nfc_uid,';
        $cardSelect = $hasCards
            ? "{$nfcSelect} lc.card_number, lc.points, lc.tier, lc.status AS card_status, lc.updated_at AS card_updated_at"
            : 'NULL AS nfc_uid, NULL AS card_number, 0 AS points, NULL AS tier, NULL AS card_status, NULL AS card_updated_at';

        $orderJoin = $hasOrders
            ? 'LEFT JOIN (
                SELECT customer_id,
                       COUNT(*) AS order_count,
                       COALESCE(SUM(total_amount), 0) AS total_spent
                FROM orders
                WHERE customer_id IS NOT NULL
                GROUP BY customer_id
            ) os ON os.customer_id = c.id'
            : '';
        $orderSelect = $hasOrders
            ? 'COALESCE(os.order_count, 0) AS order_count, COALESCE(os.total_spent, 0) AS total_spent'
            : '0 AS order_count, 0 AS total_spent';

        $rows = DB::select(
            "SELECT
                c.id AS customer_id,
                c.customer_name,
                c.table_name,
                c.order_type,
                c.created_at,
                {$cardSelect},
                {$orderSelect}
             FROM customers c
             {$cardJoin}
             {$orderJoin}
             WHERE {$walkIn}
             {$searchSql}
             ORDER BY COALESCE(lc.points, 0) DESC, c.customer_name ASC",
            $params,
        );

        return array_map(static function ($row) {
            $orderCount = (int) ($row->order_count ?? 0);
            $totalSpent = round((float) ($row->total_spent ?? 0), 2);

            return [
                'customer_id' => (int) $row->customer_id,
                'customer_name' => (string) $row->customer_name,
                'table_name' => (string) ($row->table_name ?? ''),
                'order_type' => (string) ($row->order_type ?? 'Retail'),
                'created_at' => $row->created_at,
                'card_number' => $row->card_number,
                'nfc_uid' => $row->nfc_uid !== null ? (string) $row->nfc_uid : null,
                'points' => (int) ($row->points ?? 0),
                'tier' => $row->tier !== null ? (string) $row->tier : null,
                'card_status' => $row->card_status !== null ? (string) $row->card_status : null,
                'card_updated_at' => $row->card_updated_at,
                'order_count' => $orderCount,
                'total_spent' => $totalSpent,
                'avg_transaction' => $orderCount > 0 ? round($totalSpent / $orderCount, 2) : 0,
                'has_loyalty_card' => $row->card_number !== null,
            ];
        }, $rows);
    }

    /**
     * @return array<string, mixed>
     */
    public function loyaltySettings(): array
    {
        if (! Schema::hasTable('app_settings')) {
            return [
                'loyalty_enabled' => true,
                'loyalty_points_per_unit' => 50,
                'loyalty_spend_unit' => 1000,
                'loyalty_redeem_points_per_peso' => 10,
            ];
        }

        $row = DB::selectOne(
            'SELECT loyalty_enabled, loyalty_points_per_unit, loyalty_spend_unit, loyalty_redeem_points_per_peso
             FROM app_settings
             ORDER BY id ASC
             LIMIT 1',
        );

        return [
            'loyalty_enabled' => ((int) ($row->loyalty_enabled ?? 1)) === 1,
            'loyalty_points_per_unit' => (int) ($row->loyalty_points_per_unit ?? 50),
            'loyalty_spend_unit' => (float) ($row->loyalty_spend_unit ?? 1000),
            'loyalty_redeem_points_per_peso' => (int) ($row->loyalty_redeem_points_per_peso ?? 10),
        ];
    }

    /**
     * @param  array<string, mixed>  $input
     * @return array<string, mixed>
     */
    public function updateLoyaltySettings(array $input, ?int $actorUserId = null): array
    {
        if (! Schema::hasTable('app_settings')) {
            throw new \RuntimeException('POS settings are not ready.');
        }

        $enabled = ! empty($input['loyalty_enabled']);
        $pointsPerUnit = max(0, (int) ($input['loyalty_points_per_unit'] ?? 50));
        $spendUnit = max(0.01, round((float) ($input['loyalty_spend_unit'] ?? 1000), 2));
        $redeemPerPeso = max(1, (int) ($input['loyalty_redeem_points_per_peso'] ?? 10));

        $row = DB::selectOne('SELECT id FROM app_settings ORDER BY id ASC LIMIT 1');

        if ($row) {
            DB::table('app_settings')
                ->where('id', (int) $row->id)
                ->update([
                    'loyalty_enabled' => $enabled ? 1 : 0,
                    'loyalty_points_per_unit' => $pointsPerUnit,
                    'loyalty_spend_unit' => $spendUnit,
                    'loyalty_redeem_points_per_peso' => $redeemPerPeso,
                    'updated_by' => $actorUserId,
                    'updated_at' => now(),
                ]);
        } else {
            DB::table('app_settings')->insert([
                'tax_rate' => PosHelpers::taxRate(),
                'auto_print_receipt' => 1,
                'allow_negative_stock' => 0,
                'loyalty_enabled' => $enabled ? 1 : 0,
                'loyalty_points_per_unit' => $pointsPerUnit,
                'loyalty_spend_unit' => $spendUnit,
                'loyalty_redeem_points_per_peso' => $redeemPerPeso,
                'currency_symbol' => 'PHP',
                'updated_by' => $actorUserId,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        return $this->loyaltySettings();
    }
}
