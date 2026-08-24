<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\AttendanceService;
use App\Services\Pos\ReportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class ReportsPageController extends Controller
{
    public function __construct(
        private readonly ReportService $reports,
        private readonly AttendanceService $attendance,
    ) {}

    public function index(): Response
    {
        return Inertia::render('pos/reports');
    }

    public function summary(Request $request): JsonResponse
    {
        [$start, $end] = $this->range($request);

        return response()->json([
            'success' => true,
            ...$this->reports->summary($start, $end),
        ]);
    }

    public function salesVisuals(Request $request): JsonResponse
    {
        [$start, $end, $rangeStart, $rangeEnd] = $this->reports->resolveRange($request);

        return response()->json([
            'success' => true,
            ...$this->reports->salesVisuals($start, $end, $rangeStart, $rangeEnd),
        ]);
    }

    public function charts(Request $request): JsonResponse
    {
        [$start, $end] = $this->range($request);

        $sort = (string) $request->query('sort', 'profit');
        if (! in_array($sort, ['profit', 'name', 'category'], true)) {
            $sort = 'profit';
        }

        $items = $this->reports->profitByItem($start, $end, $sort);

        // Compute independently of the requested sort so "top earner" stays
        // correct even when the list itself is sorted alphabetically.
        $top = null;
        foreach ($items as $row) {
            if ($top === null || $row['profit'] > $top['profit']) {
                $top = $row;
            }
        }

        return response()->json([
            'success' => true,
            'range' => ['start' => substr($start, 0, 10), 'end' => substr($end, 0, 10)],
            'items' => $items,
            'top_profit_item' => $top,
        ]);
    }

    public function productMix(Request $request): JsonResponse
    {
        [$start, $end] = $this->range($request);

        return response()->json([
            'success' => true,
            'range' => ['start' => substr($start, 0, 10), 'end' => substr($end, 0, 10)],
            'categories' => $this->reports->productMix($start, $end),
        ]);
    }

    public function customers(Request $request): JsonResponse
    {
        [$start, $end] = $this->range($request);

        return response()->json([
            'success' => true,
            'range' => ['start' => substr($start, 0, 10), 'end' => substr($end, 0, 10)],
            'rows' => $this->reports->customers(
                $start,
                $end,
                $request->query('search'),
            ),
        ]);
    }

    public function auditTrail(Request $request): JsonResponse
    {
        [$start, $end] = $this->range($request);

        return response()->json([
            'success' => true,
            'range' => ['start' => substr($start, 0, 10), 'end' => substr($end, 0, 10)],
            'rows' => $this->reports->auditTrail(
                $start,
                $end,
                $request->query('search'),
            ),
        ]);
    }

    public function attendancePunctuality(Request $request): JsonResponse
    {
        [$start, $end] = $this->range($request);

        return response()->json([
            'success' => true,
            'range' => ['start' => substr($start, 0, 10), 'end' => substr($end, 0, 10)],
            'schedule' => $this->attendance->schedule(),
            'rows' => $this->attendance->punctualityReport(
                substr($start, 0, 10),
                substr($end, 0, 10),
            ),
        ]);
    }

    /**
     * @return array{0: string, 1: string}
     */
    private function range(Request $request): array
    {
        [$start, $end] = $this->reports->resolveRange($request);

        return [$start, $end];
    }
}
