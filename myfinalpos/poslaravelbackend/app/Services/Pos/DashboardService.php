<?php

namespace App\Services\Pos;

use App\Support\PosHelpers;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class DashboardService
{
    public function __construct(
        private readonly ReportService $reports,
        private readonly AttendanceService $attendance,
    ) {}

    /**
     * @return array<string, mixed>
     */
    public function payload(Request $request): array
    {
        [$startDt, $endDt, $start, $end] = $this->reports->resolveRange($request);
        $granularity = strtolower(trim((string) $request->query('granularity', 'daily')));
        if (! in_array($granularity, ['hourly', 'daily', 'monthly'], true)) {
            $granularity = 'daily';
        }

        $summary = $this->reports->summary($startDt, $endDt);
        $itemsSold = $this->itemsSold($startDt, $endDt);
        $onlineOrders = $this->onlineOrderCount($startDt, $endDt);
        $lastSynced = $this->lastOrderAt();
        $grossSales = (float) $summary['gross_sales'];
        $refundedAmount = $this->refundsProcessedInRange($startDt, $endDt);
        $netSales = round($grossSales - $refundedAmount, 2);
        $orderCount = (int) $summary['order_count'];

        return [
            'store_name' => config('app.name'),
            'last_synced_at' => $lastSynced,
            'range' => $summary['range'],
            'granularity' => $granularity,
            'metrics' => [
                'net_sales' => $netSales,
                'total_discounts' => $summary['total_discounts'],
                'order_count' => $orderCount,
                'cogs' => $summary['cogs'],
                'items_sold' => $itemsSold,
                'profit' => $summary['gross_profit'],
                'refunded_amount' => $refundedAmount,
                'unpaid_orders' => 0.0,
                'online_orders' => $onlineOrders,
                'gross_sales' => $grossSales,
                'average_order_value' => $orderCount > 0
                    ? round($netSales / $orderCount, 2)
                    : 0,
                'margin_percent' => $summary['margin_percent'],
            ],
            'payment_types' => $this->normalizePaymentTypes($summary['payment_methods']),
            'sales_series' => $this->salesSeries($startDt, $endDt, $granularity, $start, $end),
            'attendance_today' => $this->attendance->dailyBoard(Carbon::today()->toDateString()),
        ];
    }

    private function itemsSold(string $startDt, string $endDt): float
    {
        if (! Schema::hasTable('order_items')) {
            return 0.0;
        }

        $qtyExpr = PosHelpers::columnExists('order_items', 'refunded_quantity')
            ? 'GREATEST(oi.quantity - COALESCE(oi.refunded_quantity, 0), 0)'
            : 'oi.quantity';

        $row = DB::selectOne(
            "SELECT COALESCE(SUM({$qtyExpr}), 0) AS items_sold
             FROM order_items oi
             INNER JOIN orders o ON o.id = oi.order_id
             WHERE o.created_at BETWEEN :start AND :end",
            ['start' => $startDt, 'end' => $endDt],
        );

        return round((float) ($row->items_sold ?? 0), 1);
    }

    private function onlineOrderCount(string $startDt, string $endDt): int
    {
        if (! Schema::hasTable('orders')) {
            return 0;
        }

        $row = DB::selectOne(
            "SELECT COUNT(*) AS total
             FROM orders o
             WHERE o.created_at BETWEEN :start AND :end
             AND (
                LOWER(COALESCE(o.payment_method, '')) LIKE '%online%'
                OR LOWER(COALESCE(o.payment_method, '')) LIKE '%gcash%'
                OR LOWER(COALESCE(o.payment_method, '')) LIKE '%bank%'
                OR LOWER(COALESCE(o.payment_method, '')) LIKE '%transfer%'
             )",
            ['start' => $startDt, 'end' => $endDt],
        );

        return (int) ($row->total ?? 0);
    }

    private function lastOrderAt(): ?string
    {
        if (! Schema::hasTable('orders')) {
            return null;
        }

        $row = DB::selectOne('SELECT MAX(created_at) AS last_at FROM orders');

        return $row?->last_at ? (string) $row->last_at : null;
    }

    /**
     * @param  array<int, array<string, mixed>>  $methods
     * @return array<int, array<string, mixed>>
     */
    private function normalizePaymentTypes(array $methods): array
    {
        return array_map(static function (array $row) {
            $method = strtolower((string) ($row['payment_method'] ?? 'cash'));
            $type = 'other';
            if (str_contains($method, 'cash')) {
                $type = 'cash';
            } elseif (
                str_contains($method, 'bank')
                || str_contains($method, 'transfer')
                || str_contains($method, 'gcash')
                || str_contains($method, 'online')
            ) {
                $type = 'bank';
            }

            return [
                'label' => (string) ($row['payment_method'] ?? 'Cash'),
                'type' => $type,
                'order_count' => (int) ($row['order_count'] ?? 0),
                'amount' => round((float) ($row['net_total'] ?? 0), 2),
            ];
        }, $methods);
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function salesSeries(
        string $startDt,
        string $endDt,
        string $granularity,
        Carbon $start,
        Carbon $end,
    ): array {
        if (! Schema::hasTable('orders')) {
            return [];
        }

        $orderGroupExpr = match ($granularity) {
            'hourly' => "DATE_FORMAT(o.created_at, '%Y-%m-%d %H:00:00')",
            'monthly' => "DATE_FORMAT(o.created_at, '%Y-%m')",
            default => 'DATE(o.created_at)',
        };

        $refundGroupExpr = match ($granularity) {
            'hourly' => "DATE_FORMAT(r.created_at, '%Y-%m-%d %H:00:00')",
            'monthly' => "DATE_FORMAT(r.created_at, '%Y-%m')",
            default => 'DATE(r.created_at)',
        };

        $grossRows = DB::select(
            "SELECT
                {$orderGroupExpr} AS bucket_key,
                COALESCE(SUM(o.total_amount), 0) AS gross_sales,
                COUNT(o.id) AS order_count
             FROM orders o
             WHERE o.created_at BETWEEN :start AND :end
             GROUP BY {$orderGroupExpr}
             ORDER BY {$orderGroupExpr} ASC",
            ['start' => $startDt, 'end' => $endDt],
        );

        /** @var array<string, array{gross_sales: float, order_count: int, refunded_amount: float}> $buckets */
        $buckets = [];
        foreach ($grossRows as $row) {
            $key = (string) $row->bucket_key;
            $buckets[$key] = [
                'gross_sales' => (float) ($row->gross_sales ?? 0),
                'order_count' => (int) ($row->order_count ?? 0),
                'refunded_amount' => 0.0,
            ];
        }

        if (Schema::hasTable('refunds')) {
            $refundRows = DB::select(
                "SELECT
                    {$refundGroupExpr} AS bucket_key,
                    COALESCE(SUM(r.amount), 0) AS refunded_amount
                 FROM refunds r
                 WHERE r.created_at BETWEEN :start AND :end
                 GROUP BY {$refundGroupExpr}
                 ORDER BY {$refundGroupExpr} ASC",
                ['start' => $startDt, 'end' => $endDt],
            );

            foreach ($refundRows as $row) {
                $key = (string) $row->bucket_key;
                if (! isset($buckets[$key])) {
                    $buckets[$key] = [
                        'gross_sales' => 0.0,
                        'order_count' => 0,
                        'refunded_amount' => 0.0,
                    ];
                }
                $buckets[$key]['refunded_amount'] = (float) ($row->refunded_amount ?? 0);
            }
        }

        ksort($buckets);

        $series = [];
        foreach ($buckets as $key => $bucket) {
            $series[] = [
                'key' => $key,
                'label' => $this->formatBucketLabel($granularity, $key),
                'net_sales' => round($bucket['gross_sales'] - $bucket['refunded_amount'], 2),
                'order_count' => $bucket['order_count'],
            ];
        }

        if ($granularity === 'hourly' && count($series) === 0 && $start->isSameDay($end)) {
            return $this->emptyHourlySlots($start);
        }

        return $series;
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function emptyHourlySlots(Carbon $day): array
    {
        $slots = [];
        for ($h = 0; $h < 24; $h++) {
            $slot = $day->copy()->startOfDay()->addHours($h);
            $slots[] = [
                'key' => $slot->format('Y-m-d H:00:00'),
                'label' => $slot->format('ga'),
                'net_sales' => 0.0,
                'order_count' => 0,
            ];
        }

        return $slots;
    }

    private function formatBucketLabel(string $granularity, string $key): string
    {
        if ($granularity === 'hourly') {
            return Carbon::parse($key)->format('ga');
        }

        if ($granularity === 'monthly') {
            return Carbon::parse($key.'-01')->format('M Y');
        }

        return Carbon::parse($key)->format('M j');
    }

    private function refundsProcessedInRange(string $startDt, string $endDt): float
    {
        if (! Schema::hasTable('refunds')) {
            return 0.0;
        }

        $row = DB::selectOne(
            'SELECT COALESCE(SUM(amount), 0) AS refunded_amount
             FROM refunds
             WHERE created_at BETWEEN :start AND :end',
            ['start' => $startDt, 'end' => $endDt],
        );

        return round((float) ($row->refunded_amount ?? 0), 2);
    }
}
