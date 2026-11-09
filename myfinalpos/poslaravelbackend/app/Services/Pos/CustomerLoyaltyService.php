<?php

namespace App\Services\Pos;

use App\Support\PosHelpers;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use PhpOffice\PhpSpreadsheet\Cell\DataType;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use Symfony\Component\HttpFoundation\StreamedResponse;

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
            // One placeholder per use - with native prepares MySQL rejects a
            // named parameter bound more than once.
            $term = '%'.trim($search).'%';
            $nfcSearch = $hasNfcUid ? ' OR lc.nfc_uid LIKE :search_nfc' : '';
            $searchSql = "AND (c.customer_name LIKE :search_name OR c.table_name LIKE :search_location OR lc.card_number LIKE :search_card{$nfcSearch})";
            $params['search_name'] = $term;
            $params['search_location'] = $term;
            $params['search_card'] = $term;
            if ($hasNfcUid) {
                $params['search_nfc'] = $term;
            }
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
     * Excel of every loyalty member's points balance, with lifetime earned /
     * redeemed (net of refunds, same rules as the Points Activity totals) and
     * a grand-total row.
     */
    public function downloadMembersExcel(?string $search = null): StreamedResponse
    {
        $members = array_values(array_filter(
            $this->customersWithPoints($search),
            static fn (array $row) => $row['has_loyalty_card'],
        ));

        $lifetime = [];
        if (Schema::hasTable('loyalty_point_logs')) {
            $logRows = DB::select(
                "SELECT customer_id,
                    COALESCE(SUM(CASE
                        WHEN action = 'earn' THEN points_change
                        WHEN action = 'refund' AND points_change < 0 THEN points_change
                        ELSE 0 END), 0) AS earned,
                    COALESCE(SUM(CASE
                        WHEN action = 'redeem' THEN -points_change
                        WHEN action = 'refund' AND points_change > 0 THEN -points_change
                        ELSE 0 END), 0) AS redeemed
                 FROM loyalty_point_logs
                 GROUP BY customer_id",
            );
            foreach ($logRows as $log) {
                $lifetime[(int) $log->customer_id] = [
                    'earned' => (int) $log->earned,
                    'redeemed' => (int) $log->redeemed,
                ];
            }
        }

        $spreadsheet = new Spreadsheet;
        $sheet = $spreadsheet->getActiveSheet();
        $sheet->setTitle('Member Points');

        $totalPoints = array_sum(array_column($members, 'points'));
        $sheet->setCellValue('A1', 'Loyalty Members — Points Summary');
        $sheet->setCellValue('A2', 'Generated: '.CarbonImmutable::now()->format('M j, Y g:i A'));
        $sheet->setCellValue('A3', sprintf(
            'Members: %s    Total points on file: %s',
            number_format(count($members)),
            number_format($totalPoints),
        ));
        $sheet->getStyle('A1')->getFont()->setBold(true)->setSize(14);

        $headers = [
            'Customer', 'Card Number', 'RFID', 'Tier', 'Status',
            'Current Points', 'Lifetime Earned', 'Lifetime Redeemed',
            'Orders', 'Total Spent (₱)', 'Last Card Update',
        ];
        $sheet->fromArray($headers, null, 'A5');
        $sheet->getStyle('A5:K5')->getFont()->setBold(true);

        $firstDataRow = 6;
        $rowNumber = $firstDataRow;
        foreach ($members as $row) {
            $life = $lifetime[$row['customer_id']] ?? ['earned' => 0, 'redeemed' => 0];
            $sheet->fromArray([
                $row['customer_name'],
                (string) ($row['card_number'] ?? ''),
                (string) ($row['nfc_uid'] ?? ''),
                $row['tier'] ?? '',
                $row['card_status'] ?? '',
                $row['points'],
                $life['earned'],
                $life['redeemed'],
                $row['order_count'],
                $row['total_spent'],
                $row['card_updated_at'] ?? '',
            ], null, 'A'.$rowNumber);
            // Card numbers / RFID UIDs are identifiers, not numbers.
            $sheet->setCellValueExplicit('B'.$rowNumber, (string) ($row['card_number'] ?? ''), DataType::TYPE_STRING);
            $sheet->setCellValueExplicit('C'.$rowNumber, (string) ($row['nfc_uid'] ?? ''), DataType::TYPE_STRING);
            $rowNumber++;
        }

        $lastDataRow = $rowNumber - 1;
        $sheet->setCellValue('A'.$rowNumber, 'TOTAL');
        if ($lastDataRow >= $firstDataRow) {
            foreach (['F', 'G', 'H', 'I', 'J'] as $column) {
                $sheet->setCellValue(
                    $column.$rowNumber,
                    "=SUM({$column}{$firstDataRow}:{$column}{$lastDataRow})",
                );
            }
        }
        $sheet->getStyle("A{$rowNumber}:K{$rowNumber}")->getFont()->setBold(true);

        $sheet->getStyle("F{$firstDataRow}:I{$rowNumber}")->getNumberFormat()->setFormatCode('#,##0');
        $sheet->getStyle("J{$firstDataRow}:J{$rowNumber}")->getNumberFormat()->setFormatCode('#,##0.00');

        foreach (range('A', 'K') as $column) {
            $sheet->getColumnDimension($column)->setAutoSize(true);
        }
        $sheet->freezePane('A6');

        $filename = 'loyalty_member_points_'.CarbonImmutable::now()->format('Y-m-d').'.xlsx';

        return new StreamedResponse(function () use ($spreadsheet) {
            $writer = new Xlsx($spreadsheet);
            $writer->save('php://output');
        }, 200, [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'Content-Disposition' => 'attachment; filename="'.$filename.'"',
            'Cache-Control' => 'max-age=0',
        ]);
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
