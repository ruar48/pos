<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Support\BusinessDay;
use App\Services\Pos\AppSettingsService;
use App\Services\Pos\CashDrawerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;

class CashDrawerPageController extends Controller
{
    public function __construct(
        private readonly CashDrawerService $cashDrawer,
        private readonly AppSettingsService $settings,
    ) {}

    public function index(): Response
    {
        $settings = $this->settings->read();

        return Inertia::render('pos/cash-drawer', [
            'businessDayResetHour' => BusinessDay::resetHour(),
            'hasCashDrawerPin' => (bool) ($settings['has_cash_drawer_pin'] ?? false),
            'printSettings' => [
                'currency_symbol' => (string) ($settings['currency_symbol'] ?? 'PHP'),
                'double_print_receipt' => (bool) ($settings['double_print_receipt'] ?? false),
                'receipt_store' => $settings['receipt_store'] ?? [],
            ],
        ]);
    }

    public function verifyPin(Request $request): JsonResponse
    {
        return $this->jsonResponse(fn () => $this->cashDrawer->verifyPin($request));
    }

    public function summary(Request $request): JsonResponse
    {
        return $this->jsonResponse(fn () => $this->cashDrawer->summary($request));
    }

    public function watch(Request $request): JsonResponse
    {
        return $this->jsonResponse(fn () => $this->cashDrawer->watch($request));
    }

    public function updateStartingCash(Request $request): JsonResponse
    {
        return $this->jsonResponse(
            fn () => $this->cashDrawer->updateStartingCash($request, (int) Auth::id()),
        );
    }

    public function addCash(Request $request): JsonResponse
    {
        return $this->jsonResponse(
            fn () => $this->cashDrawer->addCash($request, (int) Auth::id()),
        );
    }

    public function updateCashAddition(Request $request, int $additionId): JsonResponse
    {
        return $this->jsonResponse(
            fn () => $this->cashDrawer->updateCashAddition($request, $additionId, (int) Auth::id()),
        );
    }

    public function deleteCashAddition(Request $request, int $additionId): JsonResponse
    {
        return $this->jsonResponse(
            fn () => $this->cashDrawer->deleteCashAddition($request, $additionId, (int) Auth::id()),
        );
    }

    public function addExpense(Request $request): JsonResponse
    {
        return $this->jsonResponse(
            fn () => $this->cashDrawer->addExpense($request, (int) Auth::id()),
        );
    }

    public function updateExpense(Request $request, int $expenseId): JsonResponse
    {
        return $this->jsonResponse(
            fn () => $this->cashDrawer->updateExpense($request, $expenseId, (int) Auth::id()),
        );
    }

    public function deleteExpense(Request $request, int $expenseId): JsonResponse
    {
        return $this->jsonResponse(
            fn () => $this->cashDrawer->deleteExpense($request, $expenseId, (int) Auth::id()),
        );
    }

    public function exportCashAdditions(Request $request): JsonResponse
    {
        return $this->jsonResponse(function () use ($request) {
            return [
                'rows' => $this->cashDrawer->exportCashAdditions($request),
            ];
        });
    }

    public function exportExpenses(Request $request): JsonResponse
    {
        return $this->jsonResponse(function () use ($request) {
            return [
                'rows' => $this->cashDrawer->exportExpenses($request),
            ];
        });
    }

    /**
     * @param  callable(): array<string, mixed>  $action
     */
    private function jsonResponse(callable $action): JsonResponse
    {
        try {
            return response()->json([
                'success' => true,
                'data' => $action(),
            ]);
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 400);
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to process cash drawer request',
            ], 500);
        }
    }
}
