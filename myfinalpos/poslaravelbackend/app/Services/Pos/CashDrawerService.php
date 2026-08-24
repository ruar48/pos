<?php

namespace App\Services\Pos;

use App\Support\BusinessDay;
use App\Support\CashDrawerRevision;
use App\Support\PosDateTime;
use App\Support\PosHelpers;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class CashDrawerService
{
    public function __construct(private readonly ReportService $reportService) {}

    /**
     * @return array<string, mixed>
     */
    public function summary(Request $request): array
    {
        $businessDate = $this->resolveBusinessDate($request);
        [$startDt, $endDt, $start, $end] = BusinessDay::rangeFor(
            $businessDate,
            BusinessDay::isCurrent($businessDate),
        );
        $session = $this->resolveSession($businessDate);
        $sessionId = (int) $session['id'];
        $revision = CashDrawerRevision::ensure($businessDate);

        $sinceRevision = trim((string) $request->query('revision', ''));
        if ($sinceRevision !== '' && hash_equals($revision, $sinceRevision)) {
            return [
                'unchanged' => true,
                'revision' => $revision,
            ];
        }

        $sales = $this->salesTotalsForRange($startDt, $endDt);
        $cashAdded = $this->sumCashAdditions($sessionId);
        $cashExpenses = $this->sumExpenses($sessionId, 'cash');
        $nonCashExpenses = $this->sumNonCashExpenses($sessionId);

        $startingCash = round((float) $session['starting_cash'], 2);
        $cashSales = round($sales['cash_sales'], 2);
        $cashInDrawer = round(
            $startingCash + $cashAdded + $cashSales - $cashExpenses,
            2,
        );

        return [
            'business_date' => $businessDate,
            'session_id' => $sessionId,
            'revision' => $revision,
            'summary' => [
                'cash_in_drawer' => $cashInDrawer,
                'bank_transfer_sales' => round($sales['bank_transfer_sales'], 2),
                'gcash_sales' => round($sales['gcash_sales'], 2),
                'cheque_sales' => round($sales['cheque_sales'], 2),
                'starting_cash' => $startingCash,
                'cash_added' => round($cashAdded, 2),
                'cash_sales' => $cashSales,
                'cash_expenses' => round($cashExpenses, 2),
                'non_cash_expenses' => round($nonCashExpenses, 2),
            ],
            'cash_additions' => $this->listCashAdditions($sessionId),
            'expenses' => $this->listExpenses($sessionId),
            'next_series_no' => $this->nextSuggestedSeriesNo(),
            'range' => [
                'start' => $startDt,
                'end' => $endDt,
            ],
        ];
    }

    /**
     * Long-poll until the drawer revision changes (e.g. new POS sale).
     *
     * @return array{changed: bool, revision: string}
     */
    public function watch(Request $request): array
    {
        @set_time_limit(0);

        $businessDate = $this->resolveBusinessDate($request);
        $sinceRevision = trim((string) $request->query('revision', ''));
        $deadline = microtime(true) + 25.0;

        if ($sinceRevision === '') {
            return [
                'changed' => true,
                'revision' => CashDrawerRevision::ensure($businessDate),
            ];
        }

        do {
            $revision = CashDrawerRevision::ensure($businessDate);
            if (! hash_equals($revision, $sinceRevision)) {
                return [
                    'changed' => true,
                    'revision' => $revision,
                ];
            }

            usleep(500000);
        } while (microtime(true) < $deadline);

        return [
            'changed' => false,
            'revision' => CashDrawerRevision::current($businessDate) ?: $sinceRevision,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function updateStartingCash(Request $request, int $actorUserId): array
    {
        $this->requireCashDrawerPin($request);

        $amount = round((float) $request->input('starting_cash', 0), 2);
        if ($amount < 0) {
            throw new \InvalidArgumentException('Starting cash cannot be negative');
        }

        $businessDate = $this->resolveBusinessDate($request);
        $session = $this->resolveSession($businessDate);

        DB::table('cash_drawer_sessions')
            ->where('id', $session['id'])
            ->update([
                'starting_cash' => $amount,
                'updated_by_user_id' => $actorUserId,
                'updated_at' => now(),
            ]);

        PosHelpers::insertAuditLog(
            $actorUserId,
            'update',
            'cash_drawer',
            'cash_drawer_sessions',
            (int) $session['id'],
            'Updated starting cash for '.$businessDate,
            ['starting_cash' => $amount],
        );

        CashDrawerRevision::bump($businessDate);

        return $this->mutationPayload(
            $businessDate,
            (int) $session['id'],
            $amount,
        );
    }

    /**
     * @return array<string, mixed>
     */
    public function addCash(Request $request, int $actorUserId): array
    {
        $this->requireCashDrawerPin($request);

        $amount = round((float) $request->input('amount', 0), 2);
        if ($amount < 0) {
            throw new \InvalidArgumentException('Cash amount cannot be negative');
        }

        $remarks = trim((string) $request->input('remarks', ''));
        if ($amount === 0.0 && $remarks === '') {
            throw new \InvalidArgumentException('Remarks are required for a zero cash amount');
        }

        $businessDate = $this->resolveBusinessDate($request);
        $session = $this->resolveSession($businessDate);

        $id = PosHelpers::insertRow('cash_additions', [
            'session_id' => (int) $session['id'],
            'amount' => $amount,
            'remarks' => mb_substr($remarks, 0, 255),
            'created_by_user_id' => $actorUserId,
            'created_at' => now(),
        ]);

        PosHelpers::insertAuditLog(
            $actorUserId,
            'create',
            'cash_drawer',
            'cash_additions',
            $id,
            'Added cash to drawer',
            ['amount' => $amount, 'remarks' => $remarks],
        );

        CashDrawerRevision::bump($businessDate);

        return array_merge(
            $this->mutationPayload($businessDate, (int) $session['id'], (float) $session['starting_cash']),
            ['cash_addition' => $this->findCashAdditionById($id)],
        );
    }

    /**
     * @return array<string, mixed>
     */
    public function updateCashAddition(Request $request, int $additionId, int $actorUserId): array
    {
        $this->requireCashDrawerPin($request);

        $addition = DB::table('cash_additions')->where('id', $additionId)->first();
        if ($addition === null) {
            throw new \InvalidArgumentException('Cash addition not found');
        }

        $amount = round((float) $request->input('amount', $addition->amount), 2);
        if ($amount < 0) {
            throw new \InvalidArgumentException('Cash amount cannot be negative');
        }

        $remarks = trim((string) $request->input('remarks', $addition->remarks ?? ''));
        if ($amount === 0.0 && $remarks === '') {
            throw new \InvalidArgumentException('Remarks are required for a zero cash amount');
        }

        DB::table('cash_additions')
            ->where('id', $additionId)
            ->update([
                'amount' => $amount,
                'remarks' => mb_substr($remarks, 0, 255),
            ]);

        PosHelpers::insertAuditLog(
            $actorUserId,
            'update',
            'cash_drawer',
            'cash_additions',
            $additionId,
            'Updated cash addition',
            ['amount' => $amount, 'remarks' => $remarks],
        );

        $businessDate = $this->sessionBusinessDate((int) $addition->session_id);
        $session = $this->resolveSession($businessDate);
        CashDrawerRevision::bump($businessDate);

        return array_merge(
            $this->mutationPayload($businessDate, (int) $session['id'], (float) $session['starting_cash']),
            ['cash_addition' => $this->findCashAdditionById($additionId)],
        );
    }

    /**
     * @return array<string, mixed>
     */
    public function deleteCashAddition(Request $request, int $additionId, int $actorUserId): array
    {
        $this->requireCashDrawerPin($request);

        $addition = DB::table('cash_additions')->where('id', $additionId)->first();
        if ($addition === null) {
            throw new \InvalidArgumentException('Cash addition not found');
        }

        $businessDate = $this->sessionBusinessDate((int) $addition->session_id);

        DB::table('cash_additions')->where('id', $additionId)->delete();

        PosHelpers::insertAuditLog(
            $actorUserId,
            'delete',
            'cash_drawer',
            'cash_additions',
            $additionId,
            'Deleted cash addition',
            ['amount' => (float) $addition->amount, 'remarks' => (string) ($addition->remarks ?? '')],
        );

        CashDrawerRevision::bump($businessDate);

        $session = $this->resolveSession($businessDate);

        return array_merge(
            $this->mutationPayload($businessDate, (int) $session['id'], (float) $session['starting_cash']),
            ['deleted_cash_addition_id' => $additionId],
        );
    }

    /**
     * @return array<string, mixed>
     */
    public function addExpense(Request $request, int $actorUserId): array
    {
        $this->requireCashDrawerPin($request);

        $name = trim((string) $request->input('name', ''));
        if ($name === '') {
            throw new \InvalidArgumentException('Expense name is required');
        }

        $amount = round((float) $request->input('amount', 0), 2);
        if ($amount <= 0) {
            throw new \InvalidArgumentException('Expense amount must be greater than zero');
        }

        $paymentType = strtolower(trim((string) $request->input('payment_type', 'cash')));
        if (! in_array($paymentType, ['cash', 'gcash', 'bank'], true)) {
            throw new \InvalidArgumentException('Payment type must be cash, gcash, or bank');
        }

        $seriesNo = $this->parseSeriesNo($request);
        $this->assertSeriesNoUnique($seriesNo);

        $businessDate = $this->resolveBusinessDate($request);
        $session = $this->resolveSession($businessDate);
        $referenceNo = $this->allocateExpenseReferenceNo(
            (int) $session['id'],
            $businessDate,
        );

        $id = PosHelpers::insertRow('drawer_expenses', [
            'session_id' => (int) $session['id'],
            'name' => mb_substr($name, 0, 120),
            'amount' => $amount,
            'payment_type' => $paymentType,
            'reference_no' => $referenceNo,
            'series_no' => $seriesNo,
            'created_by_user_id' => $actorUserId,
            'updated_by_user_id' => $actorUserId,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        PosHelpers::insertAuditLog(
            $actorUserId,
            'create',
            'cash_drawer',
            'drawer_expenses',
            $id,
            'Added drawer expense',
            ['name' => $name, 'amount' => $amount, 'payment_type' => $paymentType, 'reference_no' => $referenceNo, 'series_no' => $seriesNo],
        );

        CashDrawerRevision::bump($businessDate);

        return array_merge(
            $this->mutationPayload($businessDate, (int) $session['id'], (float) $session['starting_cash']),
            ['expense' => $this->findExpenseById($id)],
        );
    }

    /**
     * @return array<string, mixed>
     */
    public function updateExpense(Request $request, int $expenseId, int $actorUserId): array
    {
        $this->requireCashDrawerPin($request);

        $expense = DB::table('drawer_expenses')->where('id', $expenseId)->first();
        if ($expense === null) {
            throw new \InvalidArgumentException('Expense not found');
        }

        $name = trim((string) $request->input('name', $expense->name));
        if ($name === '') {
            throw new \InvalidArgumentException('Expense name is required');
        }

        $amount = round((float) $request->input('amount', $expense->amount), 2);
        if ($amount <= 0) {
            throw new \InvalidArgumentException('Expense amount must be greater than zero');
        }

        $paymentType = strtolower(trim((string) $request->input('payment_type', $expense->payment_type)));
        if (! in_array($paymentType, ['cash', 'gcash', 'bank'], true)) {
            throw new \InvalidArgumentException('Payment type must be cash, gcash, or bank');
        }

        $seriesNo = $this->parseSeriesNo($request);
        $this->assertSeriesNoUnique($seriesNo, $expenseId);

        DB::table('drawer_expenses')
            ->where('id', $expenseId)
            ->update([
                'name' => mb_substr($name, 0, 120),
                'amount' => $amount,
                'payment_type' => $paymentType,
                'series_no' => $seriesNo,
                'updated_by_user_id' => $actorUserId,
                'updated_at' => now(),
            ]);

        PosHelpers::insertAuditLog(
            $actorUserId,
            'update',
            'cash_drawer',
            'drawer_expenses',
            $expenseId,
            'Updated drawer expense',
            ['name' => $name, 'amount' => $amount, 'payment_type' => $paymentType, 'series_no' => $seriesNo],
        );

        $businessDate = $this->sessionBusinessDate((int) $expense->session_id);
        $session = $this->resolveSession($businessDate);
        CashDrawerRevision::bump($businessDate);

        return array_merge(
            $this->mutationPayload($businessDate, (int) $session['id'], (float) $session['starting_cash']),
            ['expense' => $this->findExpenseById($expenseId)],
        );
    }

    /**
     * @return array<string, mixed>
     */
    public function deleteExpense(Request $request, int $expenseId, int $actorUserId): array
    {
        $this->requireCashDrawerPin($request);

        $expense = DB::table('drawer_expenses')->where('id', $expenseId)->first();
        if ($expense === null) {
            throw new \InvalidArgumentException('Expense not found');
        }

        $businessDate = $this->sessionBusinessDate((int) $expense->session_id);

        DB::table('drawer_expenses')->where('id', $expenseId)->delete();

        PosHelpers::insertAuditLog(
            $actorUserId,
            'delete',
            'cash_drawer',
            'drawer_expenses',
            $expenseId,
            'Deleted drawer expense',
            ['name' => $expense->name, 'amount' => (float) $expense->amount],
        );

        CashDrawerRevision::bump($businessDate);

        $session = $this->resolveSession($businessDate);

        return array_merge(
            $this->mutationPayload($businessDate, (int) $session['id'], (float) $session['starting_cash']),
            ['deleted_expense_id' => $expenseId],
        );
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function exportCashAdditions(Request $request): array
    {
        $businessDate = $this->resolveBusinessDate($request);
        $session = $this->resolveSession($businessDate);

        return $this->listCashAdditions($session['id']);
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function exportExpenses(Request $request): array
    {
        $businessDate = $this->resolveBusinessDate($request);
        $session = $this->resolveSession($businessDate);
        $filter = strtolower(trim((string) $request->query('filter', 'all')));

        return $this->listExpenses($session['id'], $filter);
    }

    private function resolveBusinessDate(Request $request): string
    {
        if ($request->filled('date')) {
            try {
                return Carbon::parse((string) $request->input('date'), BusinessDay::timezone())
                    ->format('Y-m-d');
            } catch (\Throwable) {
            }
        }

        if ($request->filled('start')) {
            try {
                return Carbon::parse((string) $request->input('start'), BusinessDay::timezone())
                    ->format('Y-m-d');
            } catch (\Throwable) {
            }
        }

        return BusinessDay::currentDate();
    }

    /**
     * @return array{id: int, starting_cash: float}
     */
    private function resolveSession(string $businessDate): array
    {
        if (! Schema::hasTable('cash_drawer_sessions')) {
            throw new \RuntimeException('Cash drawer tables are not installed. Run database migrations.');
        }

        $row = DB::table('cash_drawer_sessions')
            ->where('business_date', $businessDate)
            ->first();

        if ($row !== null) {
            return [
                'id' => (int) $row->id,
                'starting_cash' => (float) $row->starting_cash,
            ];
        }

        $id = PosHelpers::insertRow('cash_drawer_sessions', [
            'business_date' => $businessDate,
            'starting_cash' => 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return [
            'id' => $id,
            'starting_cash' => 0.0,
        ];
    }

    private function sessionBusinessDate(int $sessionId): string
    {
        $row = DB::table('cash_drawer_sessions')->where('id', $sessionId)->first();

        return $row ? (string) $row->business_date : BusinessDay::currentDate();
    }

    private function sumCashAdditions(int $sessionId): float
    {
        if (! Schema::hasTable('cash_additions')) {
            return 0.0;
        }

        $row = DB::selectOne(
            'SELECT COALESCE(SUM(amount), 0) AS total FROM cash_additions WHERE session_id = :session_id',
            ['session_id' => $sessionId],
        );

        return (float) ($row->total ?? 0);
    }

    private function sumNonCashExpenses(int $sessionId): float
    {
        if (! Schema::hasTable('drawer_expenses')) {
            return 0.0;
        }

        $row = DB::selectOne(
            "SELECT COALESCE(SUM(amount), 0) AS total
             FROM drawer_expenses
             WHERE session_id = :session_id
               AND payment_type IN ('gcash', 'bank')",
            ['session_id' => $sessionId],
        );

        return (float) ($row->total ?? 0);
    }

    private function sumExpenses(int $sessionId, string $paymentType): float
    {
        if (! Schema::hasTable('drawer_expenses')) {
            return 0.0;
        }

        $row = DB::selectOne(
            'SELECT COALESCE(SUM(amount), 0) AS total
             FROM drawer_expenses
             WHERE session_id = :session_id AND payment_type = :payment_type',
            ['session_id' => $sessionId, 'payment_type' => $paymentType],
        );

        return (float) ($row->total ?? 0);
    }

    public function forgetSalesCacheForRange(string $startDt, string $endDt): void
    {
        Cache::forget($this->salesCacheKey($startDt, $endDt));
    }

    public function forgetSalesCacheForToday(): void
    {
        $businessDate = BusinessDay::currentDate();
        [$startDt, $endDt] = BusinessDay::rangeFor($businessDate, true);

        $this->forgetSalesCacheForRange($startDt, $endDt);
    }

    /**
     * @return array{cash_sales: float, bank_transfer_sales: float, gcash_sales: float, cheque_sales: float}
     */
    private function salesTotalsForRange(string $startDt, string $endDt): array
    {
        return Cache::remember(
            $this->salesCacheKey($startDt, $endDt),
            60,
            fn () => $this->salesTotals($startDt, $endDt),
        );
    }

    private function salesCacheKey(string $startDt, string $endDt): string
    {
        return 'cash_drawer:sales:'.md5($startDt.'|'.$endDt);
    }

    /**
     * @return array{cash_sales: float, bank_transfer_sales: float, gcash_sales: float, cheque_sales: float}
     */
    private function salesTotals(string $startDt, string $endDt): array
    {
        if (! Schema::hasTable('orders')) {
            return [
                'cash_sales' => 0.0,
                'bank_transfer_sales' => 0.0,
                'gcash_sales' => 0.0,
                'cheque_sales' => 0.0,
            ];
        }

        $refundJoin = $this->refundJoin();
        $refundAmount = $this->refundAmountExpr();
        $netExpr = "(o.total_amount - {$refundAmount})";
        $methodExpr = 'LOWER(COALESCE(sales_lines.payment_method, \'\'))';
        $chequeExpr = "({$methodExpr} LIKE '%cheque%' OR {$methodExpr} LIKE '% check%' OR {$methodExpr} = 'check')";
        $hasOrderPayments = Schema::hasTable('order_payments');

        if ($hasOrderPayments) {
            $row = DB::selectOne(
                "SELECT
                    COALESCE(SUM(CASE
                        WHEN {$methodExpr} LIKE '%gcash%' THEN 0
                        WHEN {$chequeExpr} THEN 0
                        WHEN {$methodExpr} LIKE '%cash%' THEN sales_lines.amount
                        ELSE 0
                    END), 0) AS cash_sales,
                    COALESCE(SUM(CASE
                        WHEN {$methodExpr} LIKE '%gcash%' THEN sales_lines.amount
                        ELSE 0
                    END), 0) AS gcash_sales,
                    COALESCE(SUM(CASE
                        WHEN {$chequeExpr} THEN sales_lines.amount
                        ELSE 0
                    END), 0) AS cheque_sales,
                    COALESCE(SUM(CASE
                        WHEN {$methodExpr} LIKE '%gcash%' THEN 0
                        WHEN {$chequeExpr} THEN 0
                        WHEN {$methodExpr} LIKE '%bank%' OR {$methodExpr} LIKE '%transfer%' THEN sales_lines.amount
                        ELSE 0
                    END), 0) AS bank_transfer_sales
                 FROM (
                    SELECT
                        LOWER(COALESCE(op.payment_method, o.payment_method, '')) AS payment_method,
                        CASE
                            WHEN op.amount IS NOT NULL THEN op.amount - (
                                CASE WHEN o.total_amount > 0
                                    THEN (op.amount / o.total_amount) * {$refundAmount}
                                    ELSE 0
                                END
                            )
                            ELSE {$netExpr}
                        END AS amount
                    FROM orders o
                    {$refundJoin}
                    LEFT JOIN order_payments op ON op.order_id = o.id
                    WHERE o.created_at BETWEEN :start AND :end
                      AND LOWER(COALESCE(o.status, '')) IN ('completed', 'partial_refund', 'refunded')
                 ) sales_lines",
                ['start' => $startDt, 'end' => $endDt],
            );
        } else {
            $methodExpr = 'LOWER(COALESCE(o.payment_method, \'\'))';
            $chequeExpr = "({$methodExpr} LIKE '%cheque%' OR {$methodExpr} LIKE '% check%' OR {$methodExpr} = 'check')";

            $row = DB::selectOne(
                "SELECT
                    COALESCE(SUM(CASE
                        WHEN {$methodExpr} LIKE '%gcash%' THEN 0
                        WHEN {$chequeExpr} THEN 0
                        WHEN {$methodExpr} LIKE '%cash%' THEN {$netExpr}
                        ELSE 0
                    END), 0) AS cash_sales,
                    COALESCE(SUM(CASE
                        WHEN {$methodExpr} LIKE '%gcash%' THEN {$netExpr}
                        ELSE 0
                    END), 0) AS gcash_sales,
                    COALESCE(SUM(CASE
                        WHEN {$chequeExpr} THEN {$netExpr}
                        ELSE 0
                    END), 0) AS cheque_sales,
                    COALESCE(SUM(CASE
                        WHEN {$methodExpr} LIKE '%gcash%' THEN 0
                        WHEN {$chequeExpr} THEN 0
                        WHEN {$methodExpr} LIKE '%bank%' OR {$methodExpr} LIKE '%transfer%' THEN {$netExpr}
                        ELSE 0
                    END), 0) AS bank_transfer_sales
                 FROM orders o
                 {$refundJoin}
                 WHERE o.created_at BETWEEN :start AND :end
                   AND LOWER(COALESCE(o.status, '')) IN ('completed', 'partial_refund', 'refunded')",
                ['start' => $startDt, 'end' => $endDt],
            );
        }

        return [
            'cash_sales' => (float) ($row->cash_sales ?? 0),
            'bank_transfer_sales' => (float) ($row->bank_transfer_sales ?? 0),
            'gcash_sales' => (float) ($row->gcash_sales ?? 0),
            'cheque_sales' => (float) ($row->cheque_sales ?? 0),
        ];
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function listCashAdditions(int $sessionId): array
    {
        if (! Schema::hasTable('cash_additions')) {
            return [];
        }

        $rows = DB::select(
            'SELECT
                ca.id,
                ca.amount,
                ca.remarks,
                ca.created_at,
                COALESCE(u.full_name, u.username, "Staff") AS user_name
             FROM cash_additions ca
             LEFT JOIN users u ON u.id = ca.created_by_user_id
             WHERE ca.session_id = :session_id
             ORDER BY ca.created_at DESC, ca.id DESC',
            ['session_id' => $sessionId],
        );

        return array_map(static function ($row) {
            return [
                'id' => (int) $row->id,
                'amount' => round((float) $row->amount, 2),
                'remarks' => (string) ($row->remarks ?? ''),
                'user_name' => (string) ($row->user_name ?? 'Staff'),
                'created_at' => PosDateTime::formatIso((string) ($row->created_at ?? '')),
            ];
        }, $rows);
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function listExpenses(int $sessionId, string $filter = 'all'): array
    {
        if (! Schema::hasTable('drawer_expenses')) {
            return [];
        }

        $filterSql = '';
        $params = ['session_id' => $sessionId];

        if (in_array($filter, ['cash', 'gcash', 'bank'], true)) {
            $filterSql = 'AND de.payment_type = :payment_type';
            $params['payment_type'] = $filter;
        }

        $rows = DB::select(
            "SELECT
                de.id,
                de.name,
                de.amount,
                de.payment_type,
                de.reference_no,
                de.series_no,
                de.created_at,
                COALESCE(u.full_name, u.username, 'Staff') AS user_name
             FROM drawer_expenses de
             LEFT JOIN users u ON u.id = de.created_by_user_id
             WHERE de.session_id = :session_id
             {$filterSql}
             ORDER BY de.created_at DESC, de.id DESC",
            $params,
        );

        return array_map(function ($row) {
            return $this->formatExpenseRow($row);
        }, $rows);
    }

    /**
     * Lightweight drawer payload for create/update/delete actions.
     *
     * @return array<string, mixed>
     */
    private function mutationPayload(
        string $businessDate,
        int $sessionId,
        float $startingCash,
    ): array {
        [$startDt, $endDt] = BusinessDay::rangeFor(
            $businessDate,
            BusinessDay::isCurrent($businessDate),
        );

        $sales = $this->salesTotalsForRange($startDt, $endDt);
        $cashAdded = $this->sumCashAdditions($sessionId);
        $cashExpenses = $this->sumExpenses($sessionId, 'cash');
        $nonCashExpenses = $this->sumNonCashExpenses($sessionId);
        $cashSales = round($sales['cash_sales'], 2);
        $cashInDrawer = round(
            $startingCash + $cashAdded + $cashSales - $cashExpenses,
            2,
        );

        return [
            'business_date' => $businessDate,
            'session_id' => $sessionId,
            'revision' => CashDrawerRevision::ensure($businessDate),
            'summary' => [
                'cash_in_drawer' => $cashInDrawer,
                'bank_transfer_sales' => round($sales['bank_transfer_sales'], 2),
                'gcash_sales' => round($sales['gcash_sales'], 2),
                'cheque_sales' => round($sales['cheque_sales'], 2),
                'starting_cash' => round($startingCash, 2),
                'cash_added' => round($cashAdded, 2),
                'cash_sales' => $cashSales,
                'cash_expenses' => round($cashExpenses, 2),
                'non_cash_expenses' => round($nonCashExpenses, 2),
            ],
            'next_series_no' => $this->nextSuggestedSeriesNo(),
            'range' => [
                'start' => $startDt,
                'end' => $endDt,
            ],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function findExpenseById(int $expenseId): array
    {
        $row = DB::selectOne(
            "SELECT
                de.id,
                de.name,
                de.amount,
                de.payment_type,
                de.reference_no,
                de.series_no,
                de.created_at,
                COALESCE(u.full_name, u.username, 'Staff') AS user_name
             FROM drawer_expenses de
             LEFT JOIN users u ON u.id = de.created_by_user_id
             WHERE de.id = :id
             LIMIT 1",
            ['id' => $expenseId],
        );

        if ($row === null) {
            throw new \InvalidArgumentException('Expense not found');
        }

        return $this->formatExpenseRow($row);
    }

    /**
     * @return array<string, mixed>
     */
    private function findCashAdditionById(int $additionId): array
    {
        $row = DB::selectOne(
            'SELECT
                ca.id,
                ca.amount,
                ca.remarks,
                ca.created_at,
                COALESCE(u.full_name, u.username, "Staff") AS user_name
             FROM cash_additions ca
             LEFT JOIN users u ON u.id = ca.created_by_user_id
             WHERE ca.id = :id
             LIMIT 1',
            ['id' => $additionId],
        );

        if ($row === null) {
            throw new \InvalidArgumentException('Cash addition not found');
        }

        return [
            'id' => (int) $row->id,
            'amount' => round((float) $row->amount, 2),
            'remarks' => (string) ($row->remarks ?? ''),
            'user_name' => (string) ($row->user_name ?? 'Staff'),
            'created_at' => PosDateTime::formatIso((string) ($row->created_at ?? '')),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function formatExpenseRow(object $row): array
    {
        $seriesNo = isset($row->series_no) ? trim((string) $row->series_no) : '';
        $referenceNo = isset($row->reference_no) ? trim((string) $row->reference_no) : '';

        return [
            'id' => (int) $row->id,
            'reference_no' => $referenceNo !== ''
                ? $referenceNo
                : $this->formatReferenceNo((int) $row->id),
            'series_no' => $seriesNo !== '' ? $seriesNo : null,
            'name' => (string) $row->name,
            'amount' => round((float) $row->amount, 2),
            'payment_type' => (string) $row->payment_type,
            'payment_label' => match ((string) $row->payment_type) {
                'gcash' => 'GCash',
                'bank' => 'Bank',
                default => 'Cash',
            },
            'user_name' => (string) ($row->user_name ?? 'Staff'),
            'created_at' => PosDateTime::formatIso((string) ($row->created_at ?? '')),
        ];
    }

    private function formatReferenceNo(int $id): string
    {
        return (string) $id;
    }

    /**
     * Suggested next Series No. shown to the cashier as a prefilled (but
     * still editable) default, replacing the redundant auto Reference No.
     * field. Global across all sessions/dates - not date-based like
     * Reference No. - and floors at 4001 per the store's requested cutover,
     * so it never collides with historical free-text series numbers
     * (e.g. "CHK-88421") already on old records.
     */
    private function nextSuggestedSeriesNo(): string
    {
        $max = (int) (DB::table('drawer_expenses')
            ->whereRaw("series_no REGEXP '^[0-9]+$'")
            ->max(DB::raw('CAST(series_no AS UNSIGNED)')) ?? 0);

        return (string) (max(4000, $max) + 1);
    }

    private function allocateExpenseReferenceNo(int $sessionId, string $businessDate): string
    {
        $count = (int) DB::table('drawer_expenses')
            ->where('session_id', $sessionId)
            ->count();

        return sprintf('%s-%03d', $businessDate, $count + 1);
    }

    private function parseSeriesNo(Request $request): ?string
    {
        if (! $request->has('series_no')) {
            return null;
        }

        $series = trim((string) $request->input('series_no', ''));
        if ($series === '') {
            return null;
        }

        return mb_substr($series, 0, 60);
    }

    /**
     * Case-insensitive uniqueness check across all drawer expenses (not
     * scoped to a session/date - series numbers now double as the sole
     * reference identifier, so a duplicate anywhere would be ambiguous).
     * Blank/null series numbers are exempt since the field stays optional.
     */
    private function assertSeriesNoUnique(?string $seriesNo, ?int $excludeExpenseId = null): void
    {
        if ($seriesNo === null) {
            return;
        }

        $exists = DB::table('drawer_expenses')
            ->whereRaw('LOWER(series_no) = ?', [strtolower($seriesNo)])
            ->when(
                $excludeExpenseId !== null,
                fn ($query) => $query->where('id', '!=', $excludeExpenseId),
            )
            ->exists();

        if ($exists) {
            throw new \InvalidArgumentException("Series No. \"{$seriesNo}\" is already used by another expense.");
        }
    }

    /**
     * @return array{verified: bool}
     */
    public function verifyPin(Request $request): array
    {
        $this->requireCashDrawerPin($request);

        return ['verified' => true];
    }

    private function requireCashDrawerPin(Request $request): void
    {
        $pin = trim((string) ($request->input('cash_drawer_pin') ?? ''));
        if (! PosHelpers::verifyCashDrawerPin($pin)) {
            throw new \InvalidArgumentException('Invalid or missing cash drawer PIN');
        }
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
}
