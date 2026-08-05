<?php

namespace App\Services\Pos;

use App\Support\BusinessDay;
use App\Support\PosDateTime;
use App\Support\PosHelpers;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class TransactionReportService
{
    public function __construct(private readonly ReportService $reportService) {}

    /**
     * @return array<string, mixed>
     */
    public function fetch(Request $request): array
    {
        [$startDt, $endDt, $start, $end] = $this->reportService->resolveRange($request);
        $view = strtolower(trim((string) $request->query('view', 'details')));
        $page = max(1, (int) $request->query('page', 1));
        $perPage = max(5, min(100, (int) $request->query('per_page', 25)));
        $search = trim((string) $request->query('search', ''));

        if (! in_array($view, ['details', 'transactions', 'hourly', 'daily', 'monthly'], true)) {
            throw new \InvalidArgumentException('view must be details, transactions, hourly, daily, or monthly');
        }

        $this->assertRangeWithinTwoMonths($startDt, $endDt);

        if (in_array($view, ['details', 'transactions'], true)) {
            return $this->orderRows($startDt, $endDt, $start, $end, $view, $page, $perPage, $search);
        }

        return $this->periodRows($startDt, $endDt, $view, $page, $perPage);
    }

    private function assertRangeWithinTwoMonths(string $startDt, string $endDt): void
    {
        $start = Carbon::parse($startDt);
        $end = Carbon::parse($endDt);
        if ($start->diffInDays($end) > 62) {
            throw new \InvalidArgumentException('Transactions can be viewed for a maximum 2-month date range');
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function orderRows(
        string $startDt,
        string $endDt,
        Carbon $start,
        Carbon $end,
        string $view,
        int $page,
        int $perPage,
        string $search,
    ): array {
        if (! Schema::hasTable('orders')) {
            return $this->emptyPayload($view, $startDt, $endDt, $page, $perPage, 0);
        }

        $refundJoin = $this->refundJoin();
        $refundAmount = $this->refundAmountExpr();
        $netExpr = "(o.total_amount - {$refundAmount})";
        [$dateFilterSql, $dateParams] = $this->reportService->orderCreatedAtDateFilterSql($start, $end);
        $searchSql = '';
        $params = $dateParams;

        if ($search !== '') {
            $searchSql = 'AND (
                CAST(o.id AS CHAR) LIKE :search
                OR COALESCE(c.customer_name, "") LIKE :search
                OR COALESCE(cashier.full_name, "") LIKE :search
                OR COALESCE(o.payment_method, "") LIKE :search
                OR COALESCE(o.reference, "") LIKE :search
            )';
            $params['search'] = '%'.$search.'%';
        }

        $hasCashier = PosHelpers::columnExists('orders', 'cashier_user_id');
        $cashierJoin = $hasCashier ? 'LEFT JOIN users cashier ON cashier.id = o.cashier_user_id' : '';
        $cashierSelect = $hasCashier ? 'cashier.full_name AS cashier_name,' : 'NULL AS cashier_name,';

        $countRow = DB::selectOne(
            "SELECT COUNT(*) AS total
             FROM orders o
             LEFT JOIN customers c ON c.id = o.customer_id
             {$cashierJoin}
             {$refundJoin}
             WHERE {$dateFilterSql}
             {$searchSql}",
            $params,
        );
        $total = (int) ($countRow->total ?? 0);
        $offset = ($page - 1) * $perPage;

        $orders = DB::select(
            "SELECT
                o.id,
                o.created_at,
                o.payment_method,
                o.subtotal,
                o.vat,
                o.total_amount,
                COALESCE(o.discount_amount, 0) + COALESCE(o.coupon_discount, 0) + COALESCE(o.loyalty_discount, 0) AS discount_total,
                {$cashierSelect}
                COALESCE(c.customer_name, 'Walk In Farmer') AS customer_name,
                {$netExpr} AS net_total,
                {$refundAmount} AS refunded_amount,
                CASE
                    WHEN {$refundAmount} >= o.total_amount AND o.total_amount > 0 THEN 'refunded'
                    WHEN {$refundAmount} > 0 THEN 'partial_refund'
                    ELSE 'completed'
                END AS status
             FROM orders o
             LEFT JOIN customers c ON c.id = o.customer_id
             {$cashierJoin}
             {$refundJoin}
             WHERE {$dateFilterSql}
             {$searchSql}
             ORDER BY o.created_at DESC, o.id DESC
             LIMIT {$perPage} OFFSET {$offset}",
            $params,
        );

        $qtyExpr = $this->netQtyExpr();
        $costExpr = $this->unitCostExpr();
        $rows = [];

        foreach ($orders as $order) {
            $orderId = (int) $order->id;
            $items = DB::select(
                "SELECT
                    oi.id AS order_item_id,
                    oi.product_id,
                    oi.product_name,
                    ".($this->hasVarietyColumn() ? 'oi.variety_name,' : 'NULL AS variety_name,')."
                    oi.quantity,
                    ".(PosHelpers::columnExists('order_items', 'refunded_quantity')
                        ? 'COALESCE(oi.refunded_quantity, 0) AS refunded_quantity,'
                        : '0 AS refunded_quantity,')."
                    oi.price,
                    oi.total,
                    ({$qtyExpr} * {$costExpr}) AS line_cost
                 FROM order_items oi
                 INNER JOIN products p ON p.id = oi.product_id
                 WHERE oi.order_id = ?
                 ORDER BY oi.id ASC",
                [$orderId],
            );

            $itemRows = [];
            $itemsCount = 0;
            $costs = 0.0;
            $itemLabels = [];

            foreach ($items as $item) {
                $netQty = max(
                    (float) $item->quantity - (float) ($item->refunded_quantity ?? 0),
                    0,
                );
                $itemsCount += $netQty;
                $lineCost = round((float) $item->line_cost, 2);
                $costs += $lineCost;

                $label = (string) $item->product_name;
                if (! empty($item->variety_name)) {
                    $label .= ' · '.(string) $item->variety_name;
                }
                $itemLabels[] = $label.' x'.$netQty;

                $itemRows[] = [
                    'order_item_id' => (int) $item->order_item_id,
                    'product_id' => (int) $item->product_id,
                    'product_name' => (string) $item->product_name,
                    'variety_name' => $item->variety_name ? (string) $item->variety_name : null,
                    'quantity' => (float) $item->quantity,
                    'refunded_quantity' => (float) ($item->refunded_quantity ?? 0),
                    'price' => round((float) $item->price, 2),
                    'total' => round((float) $item->total, 2),
                ];
            }

            $created = PosDateTime::fromDatabase((string) $order->created_at) ?? BusinessDay::now();
            $netTotal = round((float) $order->net_total, 2);
            $refunded = round((float) $order->refunded_amount, 2);
            $grossTotal = round((float) $order->total_amount, 2);
            $orderVat = round((float) ($order->vat ?? 0), 2);

            $row = [
                'id' => $orderId,
                'receipt_number' => 'RCP-'.str_pad((string) $orderId, 6, '0', STR_PAD_LEFT),
                'date' => $created->format('d M Y'),
                'time' => strtolower($created->format('g:ia')),
                'created_at' => $created->toIso8601String(),
                'cashier_name' => (string) ($order->cashier_name ?? 'Staff'),
                'customer_name' => (string) $order->customer_name,
                'payment_method' => (string) ($order->payment_method ?: 'Cash'),
                'total' => $netTotal,
                'gross_total' => $grossTotal,
                'subtotal' => round((float) ($order->subtotal ?? 0), 2),
                'vat' => $orderVat,
                'vat_remaining' => $itemsCount <= 0 && $netTotal > 0.01
                    ? round($netTotal, 2)
                    : 0.0,
                'discount' => round((float) $order->discount_total, 2),
                'costs' => round($costs, 2),
                'profits' => round($netTotal - $costs, 2),
                'items_count' => $itemsCount,
                'items_summary' => implode(', ', $itemLabels),
                'status' => (string) $order->status,
                'refunded_amount' => $refunded,
                'can_refund' => $refunded < (float) $order->total_amount - 0.01,
                'items' => $itemRows,
                'payments' => PosHelpers::loadOrderPayments($orderId),
            ];

            $rows[] = $row;
        }

        return $this->payload($view, $startDt, $endDt, $page, $perPage, $total, $rows);
    }

    /**
     * @return array<string, mixed>
     */
    private function periodRows(
        string $startDt,
        string $endDt,
        string $view,
        int $page,
        int $perPage,
    ): array {
        if (! Schema::hasTable('orders')) {
            return $this->emptyPayload($view, $startDt, $endDt, $page, $perPage, 0);
        }

        $groupExpr = match ($view) {
            'hourly' => "DATE_FORMAT(o.created_at, '%Y-%m-%d %H:00:00')",
            'monthly' => "DATE_FORMAT(o.created_at, '%Y-%m')",
            default => 'DATE(o.created_at)',
        };

        $refundJoin = $this->refundJoin();
        $refundAmount = $this->refundAmountExpr();
        $netExpr = "(o.total_amount - {$refundAmount})";
        $qtyExpr = $this->netQtyExpr();
        $costExpr = $this->unitCostExpr();

        $buckets = DB::select(
            "SELECT
                {$groupExpr} AS bucket_key,
                COALESCE(SUM({$netExpr}), 0) AS total,
                COALESCE(SUM(o.total_amount), 0) AS gross_total,
                COALESCE(SUM({$refundAmount}), 0) AS refunded_amount,
                SUM(CASE WHEN {$refundAmount} > 0.009 THEN 1 ELSE 0 END) AS refunded_transactions,
                COUNT(o.id) AS transactions,
                COALESCE(SUM(
                    COALESCE(o.discount_amount, 0) + COALESCE(o.coupon_discount, 0) + COALESCE(o.loyalty_discount, 0)
                ), 0) AS discount
             FROM orders o
             {$refundJoin}
             WHERE o.created_at BETWEEN :start AND :end
             GROUP BY {$groupExpr}
             ORDER BY {$groupExpr} DESC",
            ['start' => $startDt, 'end' => $endDt],
        );

        $total = count($buckets);
        $offset = ($page - 1) * $perPage;
        $pageBuckets = array_slice($buckets, $offset, $perPage);

        $rows = [];
        foreach ($pageBuckets as $bucket) {
            $bucketKey = (string) $bucket->bucket_key;
            [$bucketStart, $bucketEnd] = $this->bucketBounds($view, $bucketKey);

            $metrics = DB::selectOne(
                "SELECT
                    COALESCE(SUM({$qtyExpr}), 0) AS items,
                    COALESCE(SUM({$qtyExpr} * {$costExpr}), 0) AS costs
                 FROM order_items oi
                 INNER JOIN orders o ON o.id = oi.order_id
                 INNER JOIN products p ON p.id = oi.product_id
                 WHERE o.created_at BETWEEN :start AND :end",
                ['start' => $bucketStart, 'end' => $bucketEnd],
            );

            $bankRow = DB::selectOne(
                "SELECT COALESCE(SUM({$netExpr}), 0) AS bank_transfer
                 FROM orders o
                 {$refundJoin}
                 WHERE o.created_at BETWEEN :start AND :end
                 AND (
                    LOWER(COALESCE(o.payment_method, '')) LIKE '%bank%'
                    OR LOWER(COALESCE(o.payment_method, '')) LIKE '%transfer%'
                    OR LOWER(COALESCE(o.payment_method, '')) LIKE '%gcash%'
                 )",
                ['start' => $bucketStart, 'end' => $bucketEnd],
            );

            $expenses = $this->expensesForRange($bucketStart, $bucketEnd);
            $totalSales = round((float) $bucket->total, 2);
            $grossTotal = round((float) ($bucket->gross_total ?? 0), 2);
            $refundedTotal = round((float) ($bucket->refunded_amount ?? 0), 2);
            $costs = round((float) ($metrics->costs ?? 0), 2);
            $netMerchandise = round($this->reportService->netMerchandiseForRange($bucketStart, $bucketEnd), 2);
            $profits = round($netMerchandise - $costs - $expenses, 2);
            $status = $this->resolvePeriodStatus($grossTotal, $refundedTotal, $totalSales);

            $varietyGroup = $this->hasVarietyColumn() ? ', oi.variety_name' : '';
            $varietyLabel = $this->hasVarietyColumn()
                ? "IF(oi.variety_name IS NOT NULL AND oi.variety_name <> '', CONCAT(' · ', oi.variety_name), '')"
                : "''";

            $bestSeller = DB::selectOne(
                "SELECT
                    TRIM(CONCAT(oi.product_name, {$varietyLabel})) AS name,
                    SUM({$qtyExpr}) AS qty
                 FROM order_items oi
                 INNER JOIN orders o ON o.id = oi.order_id
                 WHERE o.created_at BETWEEN :start AND :end
                 GROUP BY oi.product_name{$varietyGroup}
                 ORDER BY SUM({$qtyExpr}) DESC
                 LIMIT 1",
                ['start' => $bucketStart, 'end' => $bucketEnd],
            );

            $rows[] = [
                'period_key' => $bucketKey,
                'label' => $this->formatPeriodLabel($view, $bucketKey),
                'total' => $totalSales,
                'gross_total' => $grossTotal,
                'refunded_amount' => $refundedTotal,
                'refunded_transactions' => (int) ($bucket->refunded_transactions ?? 0),
                'status' => $status,
                'transactions' => (int) $bucket->transactions,
                'items' => round((float) ($metrics->items ?? 0), 1),
                'discount' => round((float) $bucket->discount, 2),
                'costs' => $costs,
                'expenses' => round($expenses, 2),
                'profits' => $profits,
                'bank_transfer' => round((float) ($bankRow->bank_transfer ?? 0), 2),
                'best_seller' => $bestSeller ? (string) $bestSeller->name : '',
            ];
        }

        return $this->payload($view, $startDt, $endDt, $page, $perPage, $total, $rows);
    }

    private function resolvePeriodStatus(float $grossTotal, float $refundedTotal, float $netTotal): string
    {
        if ($refundedTotal > 0 && $netTotal < 0.01 && $grossTotal > 0) {
            return 'refunded';
        }

        if ($refundedTotal > 0) {
            return 'partial_refund';
        }

        return 'completed';
    }

    private function formatPeriodLabel(string $view, string $bucketKey): string
    {
        $tz = BusinessDay::timezone();

        if ($view === 'hourly') {
            return Carbon::parse($bucketKey, 'UTC')->timezone($tz)->format('g:ia j M Y');
        }

        if ($view === 'monthly') {
            return Carbon::parse($bucketKey.'-01', 'UTC')->timezone($tz)->format('M Y');
        }

        return Carbon::parse($bucketKey, 'UTC')->timezone($tz)->format('j M Y');
    }

    /**
     * @return array{0: string, 1: string}
     */
    private function bucketBounds(string $view, string $bucketKey): array
    {
        $tz = BusinessDay::timezone();

        if ($view === 'hourly') {
            $start = Carbon::parse($bucketKey, 'UTC')->timezone($tz)->startOfHour();
            $end = $start->copy()->endOfHour();
        } elseif ($view === 'monthly') {
            $start = Carbon::parse($bucketKey.'-01', 'UTC')->timezone($tz)->startOfMonth();
            $end = $start->copy()->endOfMonth();
        } else {
            $start = Carbon::parse($bucketKey, 'UTC')->timezone($tz)->startOfDay();
            $end = $start->copy()->endOfDay();
        }

        return [
            PosDateTime::toDatabaseUtc($start),
            PosDateTime::toDatabaseUtc($end),
        ];
    }

    private function expensesForRange(string $startDt, string $endDt): float
    {
        if (! Schema::hasTable('staff_payments')) {
            return 0.0;
        }

        $row = DB::selectOne(
            'SELECT COALESCE(SUM(amount), 0) AS total
             FROM staff_payments
             WHERE created_at BETWEEN :start AND :end',
            ['start' => $startDt, 'end' => $endDt],
        );

        return (float) ($row->total ?? 0);
    }

    /**
     * @param  array<int, array<string, mixed>>  $rows
     * @return array<string, mixed>
     */
    private function payload(
        string $view,
        string $startDt,
        string $endDt,
        int $page,
        int $perPage,
        int $total,
        array $rows,
    ): array {
        return [
            'view' => $view,
            'range' => [
                'start' => substr($startDt, 0, 10),
                'end' => substr($endDt, 0, 10),
            ],
            'pagination' => [
                'page' => $page,
                'per_page' => $perPage,
                'total' => $total,
                'total_pages' => $perPage > 0 ? (int) ceil($total / $perPage) : 0,
            ],
            'rows' => $rows,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function emptyPayload(
        string $view,
        string $startDt,
        string $endDt,
        int $page,
        int $perPage,
        int $total,
    ): array {
        return $this->payload($view, $startDt, $endDt, $page, $perPage, $total, []);
    }

    private function refundJoin(): string
    {
        return PosHelpers::tableExists('refunds')
            ? 'LEFT JOIN (SELECT order_id, SUM(amount) AS refunded_amount FROM refunds GROUP BY order_id) rf ON rf.order_id = o.id'
            : '';
    }

    private function refundAmountExpr(): string
    {
        return PosHelpers::tableExists('refunds') ? 'COALESCE(rf.refunded_amount, 0)' : '0';
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
}
