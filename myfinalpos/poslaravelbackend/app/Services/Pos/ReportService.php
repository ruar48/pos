<?php

namespace App\Services\Pos;

use App\Support\BusinessDay;
use App\Support\PosDateTime;
use App\Support\PosHelpers;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class ReportService
{
    /**
     * @return array{0: string, 1: string, 2: Carbon, 3: Carbon}
     */
    public function resolveRange(Request $request): array
    {
        $tz = BusinessDay::timezone();
        $today = BusinessDay::now();

        try {
            $start = $request->filled('start')
                ? Carbon::parse((string) $request->query('start'), $tz)->startOfDay()
                : $today->copy()->startOfDay();
        } catch (\Throwable) {
            $start = $today->copy()->startOfDay();
        }

        try {
            $end = $request->filled('end')
                ? Carbon::parse((string) $request->query('end'), $tz)->endOfDay()
                : $today->copy()->endOfDay();
        } catch (\Throwable) {
            $end = $today->copy()->endOfDay();
        }

        if ($end->lessThan($start)) {
            [$start, $end] = [$end->copy()->startOfDay(), $start->copy()->endOfDay()];
        }

        return [
            PosDateTime::toDatabaseUtc($start),
            PosDateTime::toDatabaseUtc($end),
            $start,
            $end,
        ];
    }

    /**
     * Filter orders by calendar date in the app DB timezone (+08:00 session).
     * Do not use CONVERT_TZ from UTC — created_at is stored as Philippines local time.
     *
     * @return array{0: string, 1: array<string, string>}
     */
    public function orderCreatedAtDateFilterSql(Carbon $start, Carbon $end): array
    {
        return [
            'DATE(o.created_at) BETWEEN :order_date_start AND :order_date_end',
            [
                'order_date_start' => $start->toDateString(),
                'order_date_end' => $end->toDateString(),
            ],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function summary(string $startDt, string $endDt): array
    {
        if (! Schema::hasTable('orders')) {
            return $this->emptySummary($startDt, $endDt);
        }

        $refundJoin = $this->refundJoin();
        $refundAmount = $this->refundAmountExpr();
        $netExpr = "(o.total_amount - {$refundAmount})";

        $row = DB::selectOne(
            "SELECT
                COUNT(*) AS order_count,
                COALESCE(SUM(o.total_amount), 0) AS gross_sales,
                COALESCE(SUM({$netExpr}), 0) AS net_sales,
                COALESCE(SUM(o.vat), 0) AS vat_collected,
                COALESCE(SUM(COALESCE(o.discount_amount, 0) + COALESCE(o.coupon_discount, 0) + COALESCE(o.loyalty_discount, 0)), 0) AS total_discounts
             FROM orders o
             {$refundJoin}
             WHERE o.created_at BETWEEN :start AND :end",
            ['start' => $startDt, 'end' => $endDt],
        );

        $refundedAmount = $this->refundsProcessedInRange($startDt, $endDt);
        $profit = $this->profitTotals($startDt, $endDt);
        $orderCount = (int) ($row->order_count ?? 0);
        $netSales = round((float) ($row->net_sales ?? 0), 2);
        $itemSubtotal = $profit['item_subtotal'];
        $netMerchandise = $profit['revenue'];
        $netVat = $profit['net_vat'];

        $payments = DB::select(
            Schema::hasTable('order_payments')
                ? "SELECT payment_method, COUNT(*) AS order_count, COALESCE(SUM(net_total), 0) AS net_total
                   FROM (
                      SELECT COALESCE(NULLIF(TRIM(COALESCE(op.payment_method, o.payment_method)), ''), 'Cash') AS payment_method,
                             CASE
                                 WHEN op.amount IS NOT NULL THEN op.amount - (
                                     CASE WHEN o.total_amount > 0
                                         THEN (op.amount / o.total_amount) * {$refundAmount}
                                         ELSE 0
                                     END
                                 )
                                 ELSE (o.total_amount - {$refundAmount})
                             END AS net_total
                      FROM orders o
                      {$refundJoin}
                      LEFT JOIN order_payments op ON op.order_id = o.id
                      WHERE o.created_at BETWEEN :start AND :end
                   ) payment_rows
                   GROUP BY payment_method
                   ORDER BY net_total DESC"
                : "SELECT payment_method, COUNT(*) AS order_count, COALESCE(SUM(net_total), 0) AS net_total
                   FROM (
                      SELECT COALESCE(NULLIF(TRIM(o.payment_method), ''), 'Cash') AS payment_method,
                             (o.total_amount - {$refundAmount}) AS net_total
                      FROM orders o
                      {$refundJoin}
                      WHERE o.created_at BETWEEN :start AND :end
                   ) payment_rows
                   GROUP BY payment_method
                   ORDER BY net_total DESC",
            ['start' => $startDt, 'end' => $endDt],
        );

        $trend = DB::select(
            "SELECT DATE(o.created_at) AS sale_date,
                    COALESCE(SUM({$netExpr}), 0) AS net_sales,
                    COUNT(*) AS order_count
             FROM orders o
             {$refundJoin}
             WHERE o.created_at BETWEEN :start AND :end
             GROUP BY DATE(o.created_at)
             ORDER BY DATE(o.created_at) ASC",
            ['start' => $startDt, 'end' => $endDt],
        );

        return [
            'range' => ['start' => substr($startDt, 0, 10), 'end' => substr($endDt, 0, 10)],
            'order_count' => $orderCount,
            'gross_sales' => round((float) ($row->gross_sales ?? 0), 2),
            'net_sales' => $netSales,
            'vat_collected' => $netVat,
            'vat_gross' => round((float) ($row->vat_collected ?? 0), 2),
            'tax_rate' => PosHelpers::taxRate(),
            'total_discounts' => round((float) ($row->total_discounts ?? 0), 2),
            'refunded_amount' => round($refundedAmount, 2),
            'average_order_value' => $orderCount > 0 ? round($netSales / $orderCount, 2) : 0,
            'item_subtotal' => $itemSubtotal,
            'net_merchandise' => $netMerchandise,
            'revenue' => $netMerchandise,
            'cogs' => $profit['cogs'],
            'gross_profit' => $profit['gross_profit'],
            'margin_percent' => $profit['margin_percent'],
            'sales_reconcile' => round($netMerchandise + $netVat, 2),
            'payment_methods' => array_map(static fn ($p) => [
                'payment_method' => (string) $p->payment_method,
                'order_count' => (int) $p->order_count,
                'net_total' => round((float) $p->net_total, 2),
            ], $payments),
            'daily_trend' => array_map(static fn ($t) => [
                'date' => (string) $t->sale_date,
                'net_sales' => round((float) $t->net_sales, 2),
                'order_count' => (int) $t->order_count,
            ], $trend),
        ];
    }

    /**
     * Live wall monitor — today's sales by cashier plus store totals.
     *
     * @return array<string, mixed>
     */
    public function liveWallSales(string $startDt, string $endDt): array
    {
        $summary = $this->summary($startDt, $endDt);

        if (! Schema::hasTable('orders')) {
            return [
                'range' => $summary['range'],
                'overall' => [
                    'order_count' => 0,
                    'gross_sales' => 0,
                    'net_sales' => 0,
                    'average_order_value' => 0,
                ],
                'cashiers' => [],
                'recent_sales' => [],
            ];
        }

        $refundJoin = $this->refundJoin();
        $refundAmount = $this->refundAmountExpr();
        $netExpr = "(o.total_amount - {$refundAmount})";
        $hasCashier = PosHelpers::columnExists('orders', 'cashier_user_id');
        $hasReference = PosHelpers::columnExists('orders', 'reference');

        $cashiers = [];
        if ($hasCashier) {
            $cashierRows = DB::select(
                "SELECT o.cashier_user_id AS cashier_id,
                        COALESCE(NULLIF(TRIM(cashier.full_name), ''), 'Staff') AS cashier_name,
                        COUNT(*) AS order_count,
                        COALESCE(SUM(o.total_amount), 0) AS gross_sales,
                        COALESCE(SUM({$netExpr}), 0) AS net_sales,
                        MAX(o.created_at) AS last_sale_at
                 FROM orders o
                 LEFT JOIN users cashier ON cashier.id = o.cashier_user_id
                 {$refundJoin}
                 WHERE o.created_at BETWEEN :start AND :end
                 GROUP BY o.cashier_user_id, cashier.full_name
                 ORDER BY net_sales DESC, cashier_name ASC",
                ['start' => $startDt, 'end' => $endDt],
            );

            $cashiers = array_map(static fn ($row) => [
                'cashier_id' => (int) ($row->cashier_id ?? 0),
                'cashier_name' => (string) ($row->cashier_name ?? 'Staff'),
                'order_count' => (int) ($row->order_count ?? 0),
                'gross_sales' => round((float) ($row->gross_sales ?? 0), 2),
                'net_sales' => round((float) ($row->net_sales ?? 0), 2),
                'last_sale_at' => PosDateTime::formatIso((string) ($row->last_sale_at ?? '')),
            ], $cashierRows);
        }

        $receiptSelect = $hasReference
            ? "COALESCE(NULLIF(TRIM(o.reference), ''), CONCAT('#', o.id)) AS receipt_number,"
            : "CONCAT('#', o.id) AS receipt_number,";
        $cashierNameSelect = $hasCashier
            ? "COALESCE(NULLIF(TRIM(cashier.full_name), ''), 'Staff') AS cashier_name,"
            : "'Staff' AS cashier_name,";
        $cashierJoin = $hasCashier
            ? 'LEFT JOIN users cashier ON cashier.id = o.cashier_user_id'
            : '';

        $recentRows = DB::select(
            "SELECT o.id,
                    {$receiptSelect}
                    {$cashierNameSelect}
                    COALESCE(NULLIF(TRIM(o.payment_method), ''), 'Cash') AS payment_method,
                    o.total_amount AS gross_total,
                    ({$netExpr}) AS net_total,
                    o.created_at
             FROM orders o
             {$cashierJoin}
             {$refundJoin}
             WHERE o.created_at BETWEEN :start AND :end
             ORDER BY o.created_at DESC
             LIMIT 25",
            ['start' => $startDt, 'end' => $endDt],
        );

        $recentSales = array_map(static fn ($row) => [
            'id' => (int) ($row->id ?? 0),
            'receipt_number' => (string) ($row->receipt_number ?? ''),
            'cashier_name' => (string) ($row->cashier_name ?? 'Staff'),
            'payment_method' => (string) ($row->payment_method ?? 'Cash'),
            'gross_total' => round((float) ($row->gross_total ?? 0), 2),
            'net_total' => round((float) ($row->net_total ?? 0), 2),
            'created_at' => PosDateTime::formatIso((string) ($row->created_at ?? '')),
        ], $recentRows);

        return [
            'range' => $summary['range'],
            'overall' => [
                'order_count' => (int) ($summary['order_count'] ?? 0),
                'gross_sales' => (float) ($summary['gross_sales'] ?? 0),
                'net_sales' => (float) ($summary['net_sales'] ?? 0),
                'average_order_value' => (float) ($summary['average_order_value'] ?? 0),
            ],
            'cashiers' => $cashiers,
            'recent_sales' => $recentSales,
        ];
    }

    /**
     * @param  'profit'|'name'|'category'  $sort
     * @return array<int, array<string, mixed>>
     */
    public function profitByItem(string $startDt, string $endDt, string $sort = 'profit'): array
    {
        if (! Schema::hasTable('order_items')) {
            return [];
        }

        $qtyExpr = $this->netQtyExpr();
        $costExpr = $this->unitCostExpr();

        $orderBy = match ($sort) {
            'name' => 'oi.product_name ASC',
            'category' => "COALESCE(c.name, 'Uncategorized') ASC, oi.product_name ASC",
            default => "(SUM({$qtyExpr} * oi.price) - SUM({$qtyExpr} * {$costExpr})) DESC",
        };

        // No LIMIT here - the store wants the full item list, not just a
        // top-N slice; sort controls (profit/name/category) let them find
        // what they need instead.
        $rows = DB::select(
            "SELECT
                oi.product_id,
                oi.product_name,
                ".($this->hasVarietyColumn() ? 'oi.variety_name,' : 'NULL AS variety_name,')."
                COALESCE(c.name, 'Uncategorized') AS category_name,
                SUM({$qtyExpr}) AS quantity_sold,
                SUM({$qtyExpr} * oi.price) AS revenue,
                SUM({$qtyExpr} * {$costExpr}) AS cogs
             FROM order_items oi
             INNER JOIN orders o ON o.id = oi.order_id
             INNER JOIN products p ON p.id = oi.product_id
             LEFT JOIN categories c ON c.id = p.category_id
             WHERE o.created_at BETWEEN :start AND :end
             GROUP BY oi.product_id, oi.product_name, COALESCE(c.name, 'Uncategorized')
             ".($this->hasVarietyColumn() ? ', oi.variety_name' : '')."
             HAVING quantity_sold > 0
             ORDER BY {$orderBy}",
            ['start' => $startDt, 'end' => $endDt],
        );

        return array_map(function ($row) {
            $revenue = round((float) $row->revenue, 2);
            $cogs = round((float) $row->cogs, 2);
            $profit = round($revenue - $cogs, 2);

            return [
                'product_id' => (int) $row->product_id,
                'name' => trim(
                    (string) $row->product_name
                    .($row->variety_name ? ' · '.(string) $row->variety_name : ''),
                ),
                'category' => (string) $row->category_name,
                'quantity_sold' => (float) $row->quantity_sold,
                'revenue' => $revenue,
                'cogs' => $cogs,
                'profit' => $profit,
                'margin_percent' => $revenue > 0 ? round(($profit / $revenue) * 100, 1) : 0,
                'markup_percent' => $cogs > 0 ? round(($profit / $cogs) * 100, 1) : 0,
            ];
        }, $rows);
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function productMix(string $startDt, string $endDt): array
    {
        if (! Schema::hasTable('order_items')) {
            return [];
        }

        $qtyExpr = $this->netQtyExpr();
        $costExpr = $this->unitCostExpr();

        $rows = DB::select(
            "SELECT
                COALESCE(c.name, 'Uncategorized') AS category_name,
                oi.product_name,
                ".($this->hasVarietyColumn() ? 'oi.variety_name,' : 'NULL AS variety_name,')."
                SUM({$qtyExpr}) AS quantity_sold,
                SUM({$qtyExpr} * oi.price) AS revenue,
                SUM({$qtyExpr} * {$costExpr}) AS cogs
             FROM order_items oi
             INNER JOIN orders o ON o.id = oi.order_id
             INNER JOIN products p ON p.id = oi.product_id
             LEFT JOIN categories c ON c.id = p.category_id
             WHERE o.created_at BETWEEN :start AND :end
             GROUP BY COALESCE(c.name, 'Uncategorized'), oi.product_name
             ".($this->hasVarietyColumn() ? ', oi.variety_name' : '')."
             HAVING quantity_sold > 0
             ORDER BY category_name ASC, revenue DESC",
            ['start' => $startDt, 'end' => $endDt],
        );

        $categories = [];
        foreach ($rows as $row) {
            $cat = (string) $row->category_name;
            $revenue = round((float) $row->revenue, 2);
            $cogs = round((float) $row->cogs, 2);
            $profit = round($revenue - $cogs, 2);

            if (! isset($categories[$cat])) {
                $categories[$cat] = [
                    'category' => $cat,
                    'items' => [],
                    'quantity_sold' => 0,
                    'revenue' => 0.0,
                    'cogs' => 0.0,
                    'profit' => 0.0,
                ];
            }

            $label = (string) $row->product_name;
            if ($row->variety_name) {
                $label .= ' · '.(string) $row->variety_name;
            }

            $categories[$cat]['items'][] = [
                'name' => $label,
                'quantity_sold' => (float) $row->quantity_sold,
                'revenue' => $revenue,
                'cogs' => $cogs,
                'profit' => $profit,
            ];
            $categories[$cat]['quantity_sold'] += (float) $row->quantity_sold;
            $categories[$cat]['revenue'] += $revenue;
            $categories[$cat]['cogs'] += $cogs;
            $categories[$cat]['profit'] += $profit;
        }

        $result = array_values($categories);
        usort($result, static fn ($a, $b) => $b['revenue'] <=> $a['revenue']);

        foreach ($result as &$cat) {
            $cat['revenue'] = round($cat['revenue'], 2);
            $cat['cogs'] = round($cat['cogs'], 2);
            $cat['profit'] = round($cat['profit'], 2);
            $cat['margin_percent'] = $cat['revenue'] > 0
                ? round(($cat['profit'] / $cat['revenue']) * 100, 1)
                : 0;
            $cat['markup_percent'] = $cat['cogs'] > 0
                ? round(($cat['profit'] / $cat['cogs']) * 100, 1)
                : 0;
        }

        return $result;
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function customers(string $startDt, string $endDt, ?string $search = null): array
    {
        if (! Schema::hasTable('orders')) {
            return [];
        }

        $refundJoin = $this->refundJoin();
        $refundAmount = $this->refundAmountExpr();
        $netExpr = "(o.total_amount - {$refundAmount})";
        $searchSql = '';
        $params = ['start' => $startDt, 'end' => $endDt];

        if ($search !== null && trim($search) !== '') {
            $searchSql = 'AND (c.customer_name LIKE :search OR c.table_name LIKE :search)';
            $params['search'] = '%'.trim($search).'%';
        }

        $rows = DB::select(
            "SELECT
                COALESCE(c.id, 0) AS customer_id,
                COALESCE(MAX(c.customer_name), 'Walk In Farmer') AS customer_name,
                COALESCE(MAX(c.table_name), '') AS note,
                COALESCE(MAX(c.order_type), 'Retail') AS order_type,
                COUNT(o.id) AS order_count,
                COALESCE(SUM({$netExpr}), 0) AS total_spent
             FROM orders o
             LEFT JOIN customers c ON c.id = o.customer_id
             {$refundJoin}
             WHERE o.created_at BETWEEN :start AND :end
             {$searchSql}
             GROUP BY COALESCE(c.id, 0)
             ORDER BY total_spent DESC, order_count DESC",
            $params,
        );

        return array_map(static function ($row) {
            $total = round((float) $row->total_spent, 2);
            $count = (int) $row->order_count;

            return [
                'customer_id' => (int) $row->customer_id,
                'customer_name' => (string) $row->customer_name,
                'note' => (string) $row->note,
                'order_type' => (string) $row->order_type,
                'order_count' => $count,
                'total_spent' => $total,
                'avg_transaction' => $count > 0 ? round($total / $count, 2) : 0,
            ];
        }, $rows);
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function auditTrail(string $startDt, string $endDt, ?string $search = null): array
    {
        if (! Schema::hasTable('audit_logs')) {
            return [];
        }

        $searchSql = '';
        $params = ['start' => $startDt, 'end' => $endDt];

        if ($search !== null && trim($search) !== '') {
            $searchSql = 'AND (a.description LIKE :search OR a.module LIKE :search OR a.action LIKE :search OR u.full_name LIKE :search)';
            $params['search'] = '%'.trim($search).'%';
        }

        $rows = DB::select(
            "SELECT a.id, a.action, a.module, a.entity_type, a.entity_id,
                    a.description, a.created_at,
                    COALESCE(u.full_name, u.username, 'System') AS user_name
             FROM audit_logs a
             LEFT JOIN users u ON u.id = a.user_id
             WHERE a.created_at BETWEEN :start AND :end
             {$searchSql}
             ORDER BY a.created_at DESC, a.id DESC
             LIMIT 500",
            $params,
        );

        return array_map(static fn ($row) => [
            'id' => (int) $row->id,
            'action' => (string) $row->action,
            'module' => (string) $row->module,
            'entity_type' => (string) $row->entity_type,
            'entity_id' => $row->entity_id !== null ? (int) $row->entity_id : null,
            'title' => ucfirst((string) $row->action).' · '.(string) $row->module,
            'message' => (string) $row->description,
            'user_name' => (string) $row->user_name,
            'created_at' => PosDateTime::formatIso((string) ($row->created_at ?? '')),
        ], $rows);
    }

    /**
     * Donut charts + hourly heatmap payload for the reports overview.
     *
     * @return array<string, mixed>
     */
    public function salesVisuals(string $startDt, string $endDt, Carbon $rangeStart, Carbon $rangeEnd): array
    {
        return [
            'range' => ['start' => substr($startDt, 0, 10), 'end' => substr($endDt, 0, 10)],
            'cashiers' => $this->salesByCashier($startDt, $endDt),
            'payments' => $this->salesByPayment($startDt, $endDt),
            'customer_activity' => $this->salesByCustomerActivity($startDt, $endDt),
            'hourly' => $this->hourlySalesGrid($startDt, $endDt, $rangeStart, $rangeEnd),
        ];
    }

    /**
     * @return array<int, array{label: string, net_total: float, order_count: int}>
     */
    public function salesByCashier(string $startDt, string $endDt): array
    {
        if (! Schema::hasTable('orders') || ! PosHelpers::columnExists('orders', 'cashier_user_id')) {
            return [];
        }

        $refundJoin = $this->refundJoin();
        $refundAmount = $this->refundAmountExpr();
        $netExpr = "(o.total_amount - {$refundAmount})";

        $rows = DB::select(
            "SELECT COALESCE(NULLIF(TRIM(cashier.full_name), ''), 'Staff') AS label,
                    COUNT(*) AS order_count,
                    COALESCE(SUM({$netExpr}), 0) AS net_total
             FROM orders o
             LEFT JOIN users cashier ON cashier.id = o.cashier_user_id
             {$refundJoin}
             WHERE o.created_at BETWEEN :start AND :end
             GROUP BY o.cashier_user_id, cashier.full_name
             HAVING net_total > 0
             ORDER BY net_total DESC, label ASC",
            ['start' => $startDt, 'end' => $endDt],
        );

        return array_map(static fn ($row) => [
            'label' => (string) ($row->label ?? 'Staff'),
            'order_count' => (int) ($row->order_count ?? 0),
            'net_total' => round((float) ($row->net_total ?? 0), 2),
        ], $rows);
    }

    /**
     * @return array<int, array{label: string, net_total: float, order_count: int}>
     */
    public function salesByPayment(string $startDt, string $endDt): array
    {
        if (! Schema::hasTable('orders')) {
            return [];
        }

        $refundJoin = $this->refundJoin();
        $refundAmount = $this->refundAmountExpr();

        $rows = DB::select(
            Schema::hasTable('order_payments')
                ? "SELECT payment_method AS label,
                          COUNT(*) AS order_count,
                          COALESCE(SUM(net_total), 0) AS net_total
                   FROM (
                      SELECT COALESCE(NULLIF(TRIM(COALESCE(op.payment_method, o.payment_method)), ''), 'Cash') AS payment_method,
                             CASE
                                 WHEN op.amount IS NOT NULL THEN op.amount - (
                                     CASE WHEN o.total_amount > 0
                                         THEN (op.amount / o.total_amount) * {$refundAmount}
                                         ELSE 0
                                     END
                                 )
                                 ELSE (o.total_amount - {$refundAmount})
                             END AS net_total
                      FROM orders o
                      {$refundJoin}
                      LEFT JOIN order_payments op ON op.order_id = o.id
                      WHERE o.created_at BETWEEN :start AND :end
                   ) payment_rows
                   GROUP BY payment_method
                   HAVING net_total > 0
                   ORDER BY net_total DESC"
                : "SELECT payment_method AS label,
                          COUNT(*) AS order_count,
                          COALESCE(SUM(net_total), 0) AS net_total
                   FROM (
                      SELECT COALESCE(NULLIF(TRIM(o.payment_method), ''), 'Cash') AS payment_method,
                             (o.total_amount - {$refundAmount}) AS net_total
                      FROM orders o
                      {$refundJoin}
                      WHERE o.created_at BETWEEN :start AND :end
                   ) payment_rows
                   GROUP BY payment_method
                   HAVING net_total > 0
                   ORDER BY net_total DESC",
            ['start' => $startDt, 'end' => $endDt],
        );

        return array_map(static fn ($row) => [
            'label' => (string) ($row->label ?? 'Cash'),
            'order_count' => (int) ($row->order_count ?? 0),
            'net_total' => round((float) ($row->net_total ?? 0), 2),
        ], $rows);
    }

    /**
     * @return array<int, array{label: string, net_total: float, order_count: int, share_percent: float}>
     */
    public function salesByCustomerActivity(string $startDt, string $endDt): array
    {
        if (! Schema::hasTable('orders')) {
            return [];
        }

        $refundJoin = $this->refundJoin();
        $refundAmount = $this->refundAmountExpr();
        $netExpr = "(o.total_amount - {$refundAmount})";
        $hasCustomers = Schema::hasTable('customers');

        $rows = DB::select(
            $hasCustomers
                ? "SELECT activity.label,
                          COUNT(*) AS order_count,
                          COALESCE(SUM(activity.net_total), 0) AS net_total
                   FROM (
                       SELECT CASE
                           WHEN o.customer_id IS NULL OR o.customer_id = 0 THEN 'Walk-in'
                           ELSE 'Registered'
                       END AS label,
                       {$netExpr} AS net_total
                       FROM orders o
                       {$refundJoin}
                       WHERE o.created_at BETWEEN :start AND :end
                   ) activity
                   GROUP BY activity.label
                   HAVING net_total > 0
                   ORDER BY net_total DESC"
                : "SELECT 'Walk-in' AS label,
                          COUNT(*) AS order_count,
                          COALESCE(SUM({$netExpr}), 0) AS net_total
                   FROM orders o
                   {$refundJoin}
                   WHERE o.created_at BETWEEN :start AND :end
                   HAVING net_total > 0",
            ['start' => $startDt, 'end' => $endDt],
        );

        $total = array_sum(array_map(static fn ($row) => (float) ($row->net_total ?? 0), $rows));

        return array_map(static function ($row) use ($total) {
            $net = round((float) ($row->net_total ?? 0), 2);

            return [
                'label' => (string) ($row->label ?? 'Walk-in'),
                'order_count' => (int) ($row->order_count ?? 0),
                'net_total' => $net,
                'share_percent' => $total > 0 ? round(($net / $total) * 100, 1) : 0,
            ];
        }, $rows);
    }

    /**
     * @return array{
     *     days: list<string>,
     *     day_labels: list<string>,
     *     hours: list<int>,
     *     hour_labels: list<string>,
     *     cells: list<array{date: string, hour: int, units: float, amount: float}>
     * }
     */
    public function hourlySalesGrid(
        string $startDt,
        string $endDt,
        Carbon $rangeStart,
        Carbon $rangeEnd,
    ): array {
        $hours = range(0, 23);
        $hourLabels = array_map(
            static fn (int $hour) => match (true) {
                $hour === 0 => '12am',
                $hour < 12 => "{$hour}am",
                $hour === 12 => '12pm',
                default => ($hour - 12).'pm',
            },
            $hours,
        );

        $days = [];
        $dayLabels = [];
        $cursor = $rangeStart->copy()->startOfDay();
        $last = $rangeEnd->copy()->startOfDay();
        while ($cursor->lessThanOrEqualTo($last)) {
            $iso = $cursor->format('Y-m-d');
            $days[] = $iso;
            $dayLabels[] = $cursor->format('M j');
            $cursor->addDay();
        }

        $cells = [];
        foreach ($days as $day) {
            foreach ($hours as $hour) {
                $cells[] = [
                    'date' => $day,
                    'hour' => $hour,
                    'units' => 0.0,
                    'amount' => 0.0,
                ];
            }
        }

        if (! Schema::hasTable('order_items')) {
            return [
                'days' => $days,
                'day_labels' => $dayLabels,
                'hours' => $hours,
                'hour_labels' => $hourLabels,
                'cells' => $cells,
            ];
        }

        $qtyExpr = $this->netQtyExpr();

        // Do not use CONVERT_TZ from UTC - created_at is stored as
        // Philippines local time already (see comment above in this file).
        $rows = DB::select(
            "SELECT DATE(o.created_at) AS sale_date,
                    HOUR(o.created_at) AS sale_hour,
                    COALESCE(SUM({$qtyExpr}), 0) AS units,
                    COALESCE(SUM({$qtyExpr} * oi.price), 0) AS amount
             FROM order_items oi
             INNER JOIN orders o ON o.id = oi.order_id
             WHERE o.created_at BETWEEN :start AND :end
             GROUP BY sale_date, sale_hour",
            ['start' => $startDt, 'end' => $endDt],
        );

        $index = [];
        foreach ($cells as $idx => $cell) {
            $index[$cell['date'].'|'.$cell['hour']] = $idx;
        }

        foreach ($rows as $row) {
            $date = (string) ($row->sale_date ?? '');
            $hour = (int) ($row->sale_hour ?? 0);
            $key = $date.'|'.$hour;
            if (! isset($index[$key])) {
                continue;
            }
            $cells[$index[$key]] = [
                'date' => $date,
                'hour' => $hour,
                'units' => round((float) ($row->units ?? 0), 1),
                'amount' => round((float) ($row->amount ?? 0), 2),
            ];
        }

        return [
            'days' => $days,
            'day_labels' => $dayLabels,
            'hours' => $hours,
            'hour_labels' => $hourLabels,
            'cells' => $cells,
        ];
    }

    public function netMerchandiseForRange(string $startDt, string $endDt): float
    {
        return $this->profitTotals($startDt, $endDt)['revenue'];
    }

    /**
     * @return array{item_subtotal: float, revenue: float, net_vat: float, cogs: float, gross_profit: float, margin_percent: float}
     */
    private function profitTotals(string $startDt, string $endDt): array
    {
        if (! Schema::hasTable('order_items')) {
            return [
                'item_subtotal' => 0,
                'revenue' => 0,
                'net_vat' => 0,
                'cogs' => 0,
                'gross_profit' => 0,
                'margin_percent' => 0,
            ];
        }

        $refundJoin = $this->refundJoin();
        $qtyExpr = $this->netQtyExpr();
        $costExpr = $this->unitCostExpr();
        $merchAtSale = $this->merchandiseAtSaleExpr();
        $remainingRatio = $this->remainingRatioExpr();

        $itemRow = DB::selectOne(
            "SELECT
                COALESCE(SUM({$qtyExpr} * oi.price), 0) AS item_subtotal,
                COALESCE(SUM({$qtyExpr} * {$costExpr}), 0) AS cogs
             FROM order_items oi
             INNER JOIN orders o ON o.id = oi.order_id
             INNER JOIN products p ON p.id = oi.product_id
             WHERE o.created_at BETWEEN :start AND :end",
            ['start' => $startDt, 'end' => $endDt],
        );

        $orderRow = DB::selectOne(
            "SELECT
                COALESCE(SUM({$merchAtSale} * {$remainingRatio}), 0) AS net_merchandise,
                COALESCE(SUM(COALESCE(o.vat, 0) * {$remainingRatio}), 0) AS net_vat
             FROM orders o
             {$refundJoin}
             WHERE o.created_at BETWEEN :start AND :end",
            ['start' => $startDt, 'end' => $endDt],
        );

        $itemSubtotal = round((float) ($itemRow->item_subtotal ?? 0), 2);
        $netMerchandise = round((float) ($orderRow->net_merchandise ?? 0), 2);
        $netVat = round((float) ($orderRow->net_vat ?? 0), 2);
        $cogs = round((float) ($itemRow->cogs ?? 0), 2);
        $profit = round($netMerchandise - $cogs, 2);

        return [
            'item_subtotal' => $itemSubtotal,
            'revenue' => $netMerchandise,
            'net_vat' => $netVat,
            'cogs' => $cogs,
            'gross_profit' => $profit,
            'margin_percent' => $netMerchandise > 0
                ? round(($profit / $netMerchandise) * 100, 1)
                : 0,
        ];
    }

    private function orderDiscountExpr(): string
    {
        return '(COALESCE(o.discount_amount, 0) + COALESCE(o.coupon_discount, 0) + COALESCE(o.loyalty_discount, 0))';
    }

    /**
     * Merchandise ex-VAT at sale time (handles legacy rows where subtotal was pre-discount).
     */
    private function merchandiseAtSaleExpr(): string
    {
        $discountExpr = $this->orderDiscountExpr();

        return "CASE
            WHEN ABS(o.subtotal + COALESCE(o.vat, 0) - o.total_amount) < 0.05
                THEN GREATEST(o.subtotal, 0)
            ELSE GREATEST(o.subtotal - {$discountExpr}, 0)
        END";
    }

    /**
     * Share of the order still kept after refunds (0–1).
     */
    private function remainingRatioExpr(): string
    {
        $refundAmount = $this->refundAmountExpr();

        return "CASE
            WHEN o.total_amount > 0.009
                THEN GREATEST(o.total_amount - {$refundAmount}, 0) / o.total_amount
            ELSE 0
        END";
    }

    private function refundJoin(): string
    {
        return PosHelpers::tableExists('refunds')
            ? 'LEFT JOIN (SELECT order_id, SUM(amount) AS refunded_amount FROM refunds GROUP BY order_id) rf ON rf.order_id = o.id'
            : '';
    }

    /**
     * Refunds actually processed within the range, keyed by the refund's own
     * created_at — matches the Dashboard's "Total Refunds" tile so the two
     * screens agree even when a refund is issued on a different day than the
     * original order.
     */
    private function refundsProcessedInRange(string $startDt, string $endDt): float
    {
        if (! PosHelpers::tableExists('refunds')) {
            return 0.0;
        }

        $row = DB::selectOne(
            'SELECT COALESCE(SUM(amount), 0) AS refunded_amount
             FROM refunds
             WHERE created_at BETWEEN :start AND :end',
            ['start' => $startDt, 'end' => $endDt],
        );

        return (float) ($row->refunded_amount ?? 0);
    }

    private function refundAmountExpr(): string
    {
        $fromRefunds = PosHelpers::tableExists('refunds')
            ? 'COALESCE(rf.refunded_amount, 0)'
            : '0';
        $fromOrder = PosHelpers::columnExists('orders', 'refunded_amount')
            ? 'COALESCE(o.refunded_amount, 0)'
            : '0';

        return "GREATEST({$fromRefunds}, {$fromOrder})";
    }

    private function netQtyExpr(): string
    {
        return PosHelpers::columnExists('order_items', 'refunded_quantity')
            ? 'GREATEST(oi.quantity - COALESCE(oi.refunded_quantity, 0), 0)'
            : 'oi.quantity';
    }

    private function unitCostExpr(): string
    {
        if (PosHelpers::columnExists('order_items', 'unit_cost')) {
            return 'COALESCE(oi.unit_cost, p.cost_price, 0)';
        }

        return 'COALESCE(p.cost_price, 0)';
    }

    private function hasVarietyColumn(): bool
    {
        return PosHelpers::columnExists('order_items', 'variety_name');
    }

    /**
     * @return array<string, mixed>
     */
    private function emptySummary(string $startDt, string $endDt): array
    {
        return [
            'range' => ['start' => substr($startDt, 0, 10), 'end' => substr($endDt, 0, 10)],
            'order_count' => 0,
            'gross_sales' => 0,
            'net_sales' => 0,
            'vat_collected' => 0,
            'vat_gross' => 0,
            'tax_rate' => PosHelpers::taxRate(),
            'total_discounts' => 0,
            'sales_reconcile' => 0,
            'refunded_amount' => 0,
            'average_order_value' => 0,
            'item_subtotal' => 0,
            'net_merchandise' => 0,
            'revenue' => 0,
            'cogs' => 0,
            'gross_profit' => 0,
            'margin_percent' => 0,
            'payment_methods' => [],
            'daily_trend' => [],
        ];
    }
}
