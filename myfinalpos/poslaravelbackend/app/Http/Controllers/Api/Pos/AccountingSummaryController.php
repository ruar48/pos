<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class AccountingSummaryController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        if (! $request->isMethod('get')) {
            return $this->posError('Method not allowed', 405);
        }

        try {
            $period = strtolower(trim((string) $request->query('period', 'all')));
            if (! in_array($period, ['all', 'today', 'month'], true)) {
                $period = 'all';
            }

            if (! PosHelpers::tableExists('orders')) {
                return $this->posSuccess(['data' => $this->emptyPayload($period)]);
            }

            $useRefunds = PosHelpers::tableExists('refunds');
            $refundJoin = $useRefunds
                ? 'LEFT JOIN (SELECT order_id, SUM(amount) AS refunded_amount FROM refunds GROUP BY order_id) rf ON rf.order_id = o.id'
                : '';
            $refundSelect = $useRefunds ? 'COALESCE(rf.refunded_amount, 0)' : '0';
            $periodSql = $this->periodSql($period);

            $summary = DB::selectOne(
                "SELECT
                    COUNT(*) AS order_count,
                    COALESCE(SUM(o.total_amount), 0) AS gross_sales,
                    COALESCE(SUM(o.total_amount - {$refundSelect}), 0) AS net_sales,
                    COALESCE(SUM(o.vat), 0) AS vat_collected,
                    COALESCE(SUM(COALESCE(o.discount_amount, 0)), 0) AS manual_discounts,
                    COALESCE(SUM(COALESCE(o.coupon_discount, 0)), 0) AS coupon_discounts,
                    COALESCE(SUM(COALESCE(o.loyalty_discount, 0)), 0) AS loyalty_discounts,
                    COALESCE(SUM(
                        COALESCE(o.discount_amount, 0) +
                        COALESCE(o.coupon_discount, 0) +
                        COALESCE(o.loyalty_discount, 0)
                    ), 0) AS total_discounts,
                    COALESCE(SUM({$refundSelect}), 0) AS refunded_amount
                 FROM orders o
                 {$refundJoin}
                 WHERE 1 = 1 {$periodSql}",
            );

            $summaryRow = (array) ($summary ?? []);
            $orderCount = (int) ($summaryRow['order_count'] ?? 0);
            $netSales = round((float) ($summaryRow['net_sales'] ?? 0), 2);

            $refundCount = 0;
            if ($useRefunds) {
                $refundCountRow = DB::selectOne(
                    "SELECT COUNT(*) AS refund_count
                     FROM refunds r
                     INNER JOIN orders o ON o.id = r.order_id
                     WHERE 1 = 1 {$periodSql}",
                );
                $refundCount = (int) (((array) ($refundCountRow ?? []))['refund_count'] ?? 0);
            }

            $paymentRows = DB::select(
                "SELECT
                    payment_method,
                    COUNT(*) AS order_count,
                    COALESCE(SUM(net_total), 0) AS net_total
                 FROM (
                    SELECT
                        COALESCE(NULLIF(TRIM(o.payment_method), ''), 'Cash') AS payment_method,
                        (o.total_amount - {$refundSelect}) AS net_total
                    FROM orders o
                    {$refundJoin}
                    WHERE 1 = 1 {$periodSql}
                 ) AS payment_rows
                 GROUP BY payment_method
                 ORDER BY net_total DESC, order_count DESC",
            );

            $recentOrders = DB::select(
                "SELECT
                    o.id,
                    COALESCE(c.customer_name, 'Walk In Farmer') AS customer_name,
                    o.subtotal,
                    o.vat,
                    COALESCE(o.discount_amount, 0) AS discount_amount,
                    COALESCE(o.coupon_discount, 0) AS coupon_discount,
                    COALESCE(o.loyalty_discount, 0) AS loyalty_discount,
                    o.total_amount,
                    COALESCE(NULLIF(TRIM(o.payment_method), ''), 'Cash') AS payment_method,
                    o.created_at,
                    {$refundSelect} AS refunded_amount
                 FROM orders o
                 LEFT JOIN customers c ON c.id = o.customer_id
                 {$refundJoin}
                 WHERE 1 = 1 {$periodSql}
                 ORDER BY o.created_at DESC, o.id DESC
                 LIMIT 10",
            );

            $trendRows = DB::select(
                "SELECT
                    DATE(o.created_at) AS sale_date,
                    COALESCE(SUM(o.total_amount - {$refundSelect}), 0) AS daily_total,
                    COUNT(*) AS order_count
                 FROM orders o
                 {$refundJoin}
                 WHERE DATE(o.created_at) >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
                 GROUP BY DATE(o.created_at)
                 ORDER BY DATE(o.created_at) ASC",
            );

            $trendMap = [];
            foreach ($trendRows as $row) {
                $rowArr = (array) $row;
                $trendMap[(string) $rowArr['sale_date']] = [
                    'total' => round((float) $rowArr['daily_total'], 2),
                    'order_count' => (int) $rowArr['order_count'],
                ];
            }

            $todaySnapshot = $this->periodSnapshot('today', $refundJoin, $refundSelect);
            $monthSnapshot = $this->periodSnapshot('month', $refundJoin, $refundSelect);

            return $this->posSuccess([
                'data' => [
                    'period' => $period,
                    'gross_sales' => round((float) ($summaryRow['gross_sales'] ?? 0), 2),
                    'net_sales' => $netSales,
                    'vat_collected' => round((float) ($summaryRow['vat_collected'] ?? 0), 2),
                    'total_discounts' => round((float) ($summaryRow['total_discounts'] ?? 0), 2),
                    'manual_discounts' => round((float) ($summaryRow['manual_discounts'] ?? 0), 2),
                    'coupon_discounts' => round((float) ($summaryRow['coupon_discounts'] ?? 0), 2),
                    'loyalty_discounts' => round((float) ($summaryRow['loyalty_discounts'] ?? 0), 2),
                    'order_count' => $orderCount,
                    'average_order_value' => $orderCount > 0
                        ? round($netSales / $orderCount, 2)
                        : 0,
                    'refunded_amount' => round((float) ($summaryRow['refunded_amount'] ?? 0), 2),
                    'refund_count' => $refundCount,
                    'today_net_sales' => $todaySnapshot['net_sales'],
                    'today_order_count' => $todaySnapshot['order_count'],
                    'month_net_sales' => $monthSnapshot['net_sales'],
                    'month_order_count' => $monthSnapshot['order_count'],
                    'payment_methods' => array_map(
                        fn ($row) => [
                            'payment_method' => (string) (((array) $row)['payment_method'] ?? 'Cash'),
                            'order_count' => (int) (((array) $row)['order_count'] ?? 0),
                            'net_total' => round((float) (((array) $row)['net_total'] ?? 0), 2),
                        ],
                        $paymentRows,
                    ),
                    'recent_orders' => array_map(
                        fn ($row) => $this->recentOrderRow((array) $row),
                        $recentOrders,
                    ),
                    'trend' => $this->buildTrend($trendMap),
                ],
            ]);
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }

    private function periodSql(string $period): string
    {
        return match ($period) {
            'today' => 'AND DATE(o.created_at) = CURDATE()',
            'month' => 'AND YEAR(o.created_at) = YEAR(CURDATE()) AND MONTH(o.created_at) = MONTH(CURDATE())',
            default => '',
        };
    }

    private function periodSnapshot(string $period, string $refundJoin, string $refundSelect): array
    {
        $periodSql = $this->periodSql($period);
        $row = DB::selectOne(
            "SELECT
                COUNT(*) AS order_count,
                COALESCE(SUM(o.total_amount - {$refundSelect}), 0) AS net_sales
             FROM orders o
             {$refundJoin}
             WHERE 1 = 1 {$periodSql}",
        );
        $data = (array) ($row ?? []);

        return [
            'order_count' => (int) ($data['order_count'] ?? 0),
            'net_sales' => round((float) ($data['net_sales'] ?? 0), 2),
        ];
    }

    private function recentOrderRow(array $row): array
    {
        $refunded = round((float) ($row['refunded_amount'] ?? 0), 2);
        $total = round((float) ($row['total_amount'] ?? 0), 2);
        $status = $refunded <= 0
            ? 'completed'
            : ($refunded >= $total ? 'refunded' : 'partial_refund');

        return [
            'order_id' => (int) ($row['id'] ?? 0),
            'customer_name' => (string) ($row['customer_name'] ?? 'Walk In Farmer'),
            'subtotal' => round((float) ($row['subtotal'] ?? 0), 2),
            'vat' => round((float) ($row['vat'] ?? 0), 2),
            'discount_total' => round(
                (float) ($row['discount_amount'] ?? 0) +
                (float) ($row['coupon_discount'] ?? 0) +
                (float) ($row['loyalty_discount'] ?? 0),
                2,
            ),
            'total' => $total,
            'payment_method' => (string) ($row['payment_method'] ?? 'Cash'),
            'status' => $status,
            'created_at' => (string) ($row['created_at'] ?? ''),
        ];
    }

    private function buildTrend(array $trendMap): array
    {
        $trend = [];

        for ($offset = 6; $offset >= 0; $offset--) {
            $date = now()->subDays($offset);
            $key = $date->format('Y-m-d');
            $point = $trendMap[$key] ?? ['total' => 0.0, 'order_count' => 0];

            $trend[] = [
                'date' => $key,
                'label' => $date->format('m/d'),
                'total' => round((float) $point['total'], 2),
                'order_count' => (int) $point['order_count'],
            ];
        }

        return $trend;
    }

    private function emptyPayload(string $period): array
    {
        return [
            'period' => $period,
            'gross_sales' => 0,
            'net_sales' => 0,
            'vat_collected' => 0,
            'total_discounts' => 0,
            'manual_discounts' => 0,
            'coupon_discounts' => 0,
            'loyalty_discounts' => 0,
            'order_count' => 0,
            'average_order_value' => 0,
            'refunded_amount' => 0,
            'refund_count' => 0,
            'today_net_sales' => 0,
            'today_order_count' => 0,
            'month_net_sales' => 0,
            'month_order_count' => 0,
            'payment_methods' => [],
            'recent_orders' => [],
            'trend' => $this->buildTrend([]),
        ];
    }
}
