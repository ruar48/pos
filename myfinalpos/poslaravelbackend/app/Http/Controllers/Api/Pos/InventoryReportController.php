<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\ProductPriceHistory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Builds the advanced inventory report: per-item Beginning / Added / Deducted /
 * Ending balances plus live inventory valuation, category roll-ups and grand
 * totals for a selected date range. Balances are reconstructed from the
 * stock_movements ledger anchored on the live product stock so any historical
 * window stays consistent (ending = beginning + added - deducted).
 */
class InventoryReportController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        if ($request->isMethod('OPTIONS')) {
            return $this->posSuccess();
        }

        if (! $request->isMethod('get')) {
            return $this->posError('Method not allowed', 405);
        }

        if (! Schema::hasTable('products')) {
            return $this->posError('POS database is not ready.', 503);
        }

        [$start, $end] = $this->resolveRange($request);
        $startDt = $start->format('Y-m-d').' 00:00:00';
        $endDt = $end->format('Y-m-d').' 23:59:59';

        $products = $this->fetchProducts();
        $movements = $this->fetchMovementAggregates($startDt, $endDt);
        $priceMap = ProductPriceHistory::pricesAsOf($endDt);
        $valuationAsOf = $end->format('Y-m-d');

        $rows = [];
        $catMap = [];
        $totals = [
            'beginning' => 0,
            'added' => 0,
            'deducted' => 0,
            'ending' => 0,
            'sold' => 0,
            'value_cost' => 0.0,
            'value_retail' => 0.0,
            'items' => 0,
            'low_stock' => 0,
            'out_of_stock' => 0,
        ];

        foreach ($products as $p) {
            $productId = (int) $p->id;
            $live = (int) ($p->stock ?? 0);

            $m = $movements[$productId] ?? null;
            $deltaFromStart = $m ? (int) $m->delta_from_start : 0;
            $deltaAfterEnd = $m ? (int) $m->delta_after_end : 0;
            $added = $m ? (int) $m->added : 0;
            $deducted = $m ? (int) $m->deducted : 0;
            $sold = $m ? (int) $m->sold : 0;

            $beginning = $live - $deltaFromStart;
            $ending = $live - $deltaAfterEnd;

            $fallbackCost = $p->cost_price !== null ? (float) $p->cost_price : 0.0;
            $fallbackPrice = (float) ($p->price ?? 0);
            [$cost, $price] = ProductPriceHistory::resolve(
                $priceMap,
                $productId,
                null,
                $fallbackCost,
                $fallbackPrice,
            );

            $valueCost = $ending * $cost;
            $valueRetail = $ending * $price;

            $reorder = (int) ($p->reorder_level ?? 0);
            $effectiveReorder = $reorder > 0 ? $reorder : 5;
            $isOut = $ending <= 0;
            $isLow = ! $isOut && $ending <= $effectiveReorder;

            $categoryName = (string) ($p->category_name ?? 'Uncategorized');

            $rows[] = [
                'product_id' => $productId,
                'name' => (string) $p->name,
                'category' => $categoryName,
                'image_url' => $p->image_url,
                'beginning' => $beginning,
                'added' => $added,
                'deducted' => $deducted,
                'sold' => $sold,
                'ending' => $ending,
                'live_stock' => $live,
                'reorder_level' => $reorder,
                'cost_price' => $cost,
                'price' => $price,
                'value_cost' => round($valueCost, 2),
                'value_retail' => round($valueRetail, 2),
                'is_low_stock' => $isLow,
                'is_out_of_stock' => $isOut,
            ];

            if (! isset($catMap[$categoryName])) {
                $catMap[$categoryName] = [
                    'category' => $categoryName,
                    'beginning' => 0,
                    'added' => 0,
                    'deducted' => 0,
                    'ending' => 0,
                    'sold' => 0,
                    'value_cost' => 0.0,
                    'value_retail' => 0.0,
                    'items' => 0,
                ];
            }
            $catMap[$categoryName]['beginning'] += $beginning;
            $catMap[$categoryName]['added'] += $added;
            $catMap[$categoryName]['deducted'] += $deducted;
            $catMap[$categoryName]['ending'] += $ending;
            $catMap[$categoryName]['sold'] += $sold;
            $catMap[$categoryName]['value_cost'] += $valueCost;
            $catMap[$categoryName]['value_retail'] += $valueRetail;
            $catMap[$categoryName]['items']++;

            $totals['beginning'] += $beginning;
            $totals['added'] += $added;
            $totals['deducted'] += $deducted;
            $totals['ending'] += $ending;
            $totals['sold'] += $sold;
            $totals['value_cost'] += $valueCost;
            $totals['value_retail'] += $valueRetail;
            $totals['items']++;
            if ($isLow) {
                $totals['low_stock']++;
            }
            if ($isOut) {
                $totals['out_of_stock']++;
            }
        }

        $categories = array_values(array_map(static function ($c) {
            $c['value_cost'] = round($c['value_cost'], 2);
            $c['value_retail'] = round($c['value_retail'], 2);
            $c['value_margin'] = round($c['value_retail'] - $c['value_cost'], 2);

            return $c;
        }, $catMap));

        usort($categories, static fn ($a, $b) => $b['value_retail'] <=> $a['value_retail']);

        $totals['value_cost'] = round($totals['value_cost'], 2);
        $totals['value_retail'] = round($totals['value_retail'], 2);
        $totals['value_margin'] = round($totals['value_retail'] - $totals['value_cost'], 2);

        $page = (int) $request->query('page', 0);

        if ($page <= 0) {
            return $this->posSuccess([
                'range' => [
                    'start' => $start->format('Y-m-d'),
                    'end' => $end->format('Y-m-d'),
                ],
                'valuation_as_of' => $valuationAsOf,
                'rows' => $rows,
                'categories' => $categories,
                'totals' => $totals,
                'generated_at' => now()->toIso8601String(),
            ]);
        }

        $search = trim((string) $request->query('search', ''));
        $categoryFilter = trim((string) $request->query('category', ''));
        $statusFilter = trim((string) $request->query('status', ''));

        $filteredRows = array_values(array_filter($rows, static function ($row) use ($search, $categoryFilter, $statusFilter) {
            if ($search !== '' && ! str_contains(strtolower($row['name']), strtolower($search))) {
                return false;
            }
            if ($categoryFilter !== '' && $row['category'] !== $categoryFilter) {
                return false;
            }
            if ($statusFilter === 'low_stock' && ! $row['is_low_stock']) {
                return false;
            }
            if ($statusFilter === 'out_of_stock' && ! $row['is_out_of_stock']) {
                return false;
            }

            return true;
        }));

        $perPage = max(1, min(200, (int) $request->query('per_page', 100)));
        $total = count($filteredRows);
        $pageRows = array_slice($filteredRows, ($page - 1) * $perPage, $perPage);

        $filteredTotals = [
            'beginning' => 0,
            'added' => 0,
            'deducted' => 0,
            'sold' => 0,
            'ending' => 0,
            'value_cost' => 0.0,
            'value_retail' => 0.0,
        ];
        foreach ($filteredRows as $row) {
            $filteredTotals['beginning'] += $row['beginning'];
            $filteredTotals['added'] += $row['added'];
            $filteredTotals['deducted'] += $row['deducted'];
            $filteredTotals['sold'] += $row['sold'];
            $filteredTotals['ending'] += $row['ending'];
            $filteredTotals['value_cost'] += $row['value_cost'];
            $filteredTotals['value_retail'] += $row['value_retail'];
        }
        $filteredTotals['value_cost'] = round($filteredTotals['value_cost'], 2);
        $filteredTotals['value_retail'] = round($filteredTotals['value_retail'], 2);

        return $this->posSuccess([
            'range' => [
                'start' => $start->format('Y-m-d'),
                'end' => $end->format('Y-m-d'),
            ],
            'valuation_as_of' => $valuationAsOf,
            'rows' => $pageRows,
            'categories' => $categories,
            'totals' => $totals,
            'generated_at' => now()->toIso8601String(),
            'meta' => [
                'page' => $page,
                'per_page' => $perPage,
                'total' => $total,
                'has_more' => $page * $perPage < $total,
                'filtered_totals' => $filteredTotals,
            ],
        ]);
    }

    /**
     * @return array{0: Carbon, 1: Carbon}
     */
    private function resolveRange(Request $request): array
    {
        $today = Carbon::today();

        try {
            $start = $request->filled('start')
                ? Carbon::parse((string) $request->query('start'))->startOfDay()
                : $today->copy();
        } catch (\Throwable) {
            $start = $today->copy();
        }

        try {
            $end = $request->filled('end')
                ? Carbon::parse((string) $request->query('end'))->startOfDay()
                : $today->copy();
        } catch (\Throwable) {
            $end = $today->copy();
        }

        if ($end->lessThan($start)) {
            [$start, $end] = [$end, $start];
        }

        return [$start, $end];
    }

    private function fetchProducts(): array
    {
        return DB::select(
            'SELECT p.id, p.name, p.price, p.cost_price, p.stock,
                    p.reorder_level, p.image_url, c.name AS category_name
             FROM products p
             LEFT JOIN categories c ON c.id = p.category_id
             WHERE p.status = "active"
             ORDER BY c.name ASC, p.name ASC',
        );
    }

    /**
     * @return array<int, object>
     */
    private function fetchMovementAggregates(string $startDt, string $endDt): array
    {
        if (! Schema::hasTable('stock_movements')) {
            return [];
        }

        $rows = DB::select(
            'SELECT product_id,
                    SUM(CASE WHEN created_at >= :start1 THEN quantity_delta ELSE 0 END) AS delta_from_start,
                    SUM(CASE WHEN created_at > :end1 THEN quantity_delta ELSE 0 END) AS delta_after_end,
                    SUM(CASE WHEN created_at BETWEEN :start2 AND :end2 AND quantity_delta > 0 THEN quantity_delta ELSE 0 END) AS added,
                    SUM(CASE WHEN created_at BETWEEN :start3 AND :end3 AND quantity_delta < 0 THEN -quantity_delta ELSE 0 END) AS deducted,
                    SUM(CASE WHEN created_at BETWEEN :start4 AND :end4 AND type = "sale" THEN -quantity_delta ELSE 0 END) AS sold
             FROM stock_movements
             GROUP BY product_id',
            [
                'start1' => $startDt,
                'end1' => $endDt,
                'start2' => $startDt,
                'end2' => $endDt,
                'start3' => $startDt,
                'end3' => $endDt,
                'start4' => $startDt,
                'end4' => $endDt,
            ],
        );

        $map = [];
        foreach ($rows as $row) {
            $map[(int) $row->product_id] = $row;
        }

        return $map;
    }
}
