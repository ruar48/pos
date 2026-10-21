<?php

namespace App\Services\Pos;

use App\Support\PosHelpers;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Every customer's point movements (earn / redeem / open_card) for the admin
 * Points Activity tab and its Excel download. Totals use the same
 * customer/date filters but ignore the action filter so earned vs redeemed
 * stay comparable.
 */
class LoyaltyActivityService
{
    public const MAX_ROWS = 5000;

    private const ACTION_LABELS = [
        'earn' => 'Earned',
        'redeem' => 'Redeemed',
        'open_card' => 'Card opened',
    ];

    /**
     * @param  array{action?: string, q?: string, from?: string, to?: string}  $filters
     * @return array{data: array<int, array<string, mixed>>, totals: array<string, int>}
     */
    public function activity(array $filters, int $limit): array
    {
        $result = [
            'data' => [],
            'totals' => ['earned' => 0, 'redeemed' => 0, 'earn_count' => 0, 'redeem_count' => 0],
        ];

        if (! PosHelpers::tableExists('loyalty_point_logs')) {
            return $result;
        }

        $where = [];
        $bindings = [];

        $search = trim((string) ($filters['q'] ?? ''));
        if ($search !== '') {
            $where[] = 'c.customer_name LIKE ?';
            $bindings[] = '%'.$search.'%';
        }

        $from = $this->validDate($filters['from'] ?? null);
        if ($from !== null) {
            $where[] = 'lpl.created_at >= ?';
            $bindings[] = $from.' 00:00:00';
        }

        $to = $this->validDate($filters['to'] ?? null);
        if ($to !== null) {
            $where[] = 'lpl.created_at <= ?';
            $bindings[] = $to.' 23:59:59';
        }

        $baseFrom = 'FROM loyalty_point_logs lpl
             LEFT JOIN customers c ON c.id = lpl.customer_id
             LEFT JOIN users u ON u.id = lpl.actor_user_id';

        $totalsWhere = $where === [] ? '' : 'WHERE '.implode(' AND ', $where);
        $totals = (array) DB::selectOne(
            "SELECT
                COALESCE(SUM(CASE WHEN lpl.action = 'earn' THEN lpl.points_change ELSE 0 END), 0) AS earned,
                COALESCE(SUM(CASE WHEN lpl.action = 'redeem' THEN -lpl.points_change ELSE 0 END), 0) AS redeemed,
                COALESCE(SUM(lpl.action = 'earn'), 0) AS earn_count,
                COALESCE(SUM(lpl.action = 'redeem'), 0) AS redeem_count
             {$baseFrom}
             {$totalsWhere}",
            $bindings,
        );

        $action = strtolower(trim((string) ($filters['action'] ?? '')));
        if (array_key_exists($action, self::ACTION_LABELS)) {
            $where[] = 'lpl.action = ?';
            $bindings[] = $action;
        }

        $limit = max(1, min(self::MAX_ROWS, $limit));
        $rowsWhere = $where === [] ? '' : 'WHERE '.implode(' AND ', $where);

        $rows = DB::select(
            "SELECT
                lpl.id, lpl.customer_id, lpl.loyalty_card_id, lpl.order_id, lpl.action,
                lpl.points_change, lpl.points_balance_after, lpl.order_amount,
                lpl.description, lpl.actor_user_id, u.full_name AS actor_name,
                lpl.created_at, c.customer_name
             {$baseFrom}
             {$rowsWhere}
             ORDER BY lpl.created_at DESC, lpl.id DESC
             LIMIT {$limit}",
            $bindings,
        );

        $result['data'] = array_map(function ($row) {
            $data = (array) $row;
            $orderId = isset($data['order_id']) ? (int) $data['order_id'] : 0;

            return PosHelpers::loyaltyPointLogRowToArray($data) + [
                'customer_name' => $data['customer_name'] ?? null,
                'receipt_number' => $orderId > 0
                    ? 'RCP-'.str_pad((string) $orderId, 6, '0', STR_PAD_LEFT)
                    : null,
            ];
        }, $rows);

        $result['totals'] = [
            'earned' => (int) ($totals['earned'] ?? 0),
            'redeemed' => (int) ($totals['redeemed'] ?? 0),
            'earn_count' => (int) ($totals['earn_count'] ?? 0),
            'redeem_count' => (int) ($totals['redeem_count'] ?? 0),
        ];

        return $result;
    }

    /**
     * @param  array{action?: string, q?: string, from?: string, to?: string}  $filters
     */
    public function downloadExcel(array $filters): StreamedResponse
    {
        $activity = $this->activity($filters, self::MAX_ROWS);

        $spreadsheet = new Spreadsheet;
        $sheet = $spreadsheet->getActiveSheet();
        $sheet->setTitle('Points Activity');

        $sheet->setCellValue('A1', 'Loyalty Points Activity');
        $sheet->setCellValue('A2', 'Period: '.$this->periodLabel($filters));
        $sheet->setCellValue('A3', sprintf(
            'Points earned: %s (%s purchases)    Points redeemed: %s (%s redemptions)',
            number_format($activity['totals']['earned']),
            number_format($activity['totals']['earn_count']),
            number_format($activity['totals']['redeemed']),
            number_format($activity['totals']['redeem_count']),
        ));
        $sheet->getStyle('A1')->getFont()->setBold(true)->setSize(14);

        $headers = ['Date', 'Time', 'Customer', 'Type', 'Points', 'Balance After', 'Receipt', 'Cashier', 'Description'];
        $sheet->fromArray($headers, null, 'A5');
        $sheet->getStyle('A5:I5')->getFont()->setBold(true);

        $rowNumber = 6;
        foreach ($activity['data'] as $row) {
            $created = $this->parseDate($row['created_at']);
            $sheet->fromArray([
                $created?->format('M j, Y') ?? $row['created_at'],
                $created?->format('g:i A') ?? '',
                $row['customer_name'] ?? 'Customer #'.$row['customer_id'],
                self::ACTION_LABELS[$row['action']] ?? $row['action'],
                $row['points_change'],
                $row['points_balance_after'],
                $row['receipt_number'] ?? '',
                $row['actor_name'] ?? '',
                $row['description'],
            ], null, 'A'.$rowNumber);
            $rowNumber++;
        }

        foreach (range('A', 'I') as $column) {
            $sheet->getColumnDimension($column)->setAutoSize(true);
        }
        $sheet->freezePane('A6');

        $filename = 'loyalty_points_activity_'.CarbonImmutable::now()->format('Y-m-d').'.xlsx';

        return new StreamedResponse(function () use ($spreadsheet) {
            $writer = new Xlsx($spreadsheet);
            $writer->save('php://output');
        }, 200, [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'Content-Disposition' => 'attachment; filename="'.$filename.'"',
            'Cache-Control' => 'max-age=0',
        ]);
    }

    private function periodLabel(array $filters): string
    {
        $from = $this->validDate($filters['from'] ?? null);
        $to = $this->validDate($filters['to'] ?? null);
        $format = fn (string $date) => CarbonImmutable::parse($date)->format('M j, Y');

        if ($from !== null && $to !== null) {
            return $format($from).' to '.$format($to);
        }
        if ($from !== null) {
            return 'From '.$format($from);
        }
        if ($to !== null) {
            return 'Up to '.$format($to);
        }

        return 'All dates';
    }

    private function validDate(mixed $value): ?string
    {
        $value = (string) ($value ?? '');

        return preg_match('/^\d{4}-\d{2}-\d{2}$/', $value) ? $value : null;
    }

    private function parseDate(string $value): ?CarbonImmutable
    {
        try {
            return $value === '' ? null : CarbonImmutable::parse($value);
        } catch (\Throwable) {
            return null;
        }
    }
}
