<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Api\Pos\RefundController;
use App\Http\Controllers\Controller;
use App\Services\Pos\TransactionReportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;

class TransactionsPageController extends Controller
{
    public function __construct(
        private readonly TransactionReportService $reports,
    ) {}

    public function index(): Response
    {
        return Inertia::render('pos/transactions');
    }

    public function data(Request $request): JsonResponse
    {
        try {
            return response()->json([
                'success' => true,
                'data' => $this->reports->fetch($request),
            ]);
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 400);
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to load transaction report',
            ], 500);
        }
    }

    public function refund(Request $request): JsonResponse
    {
        $request->merge([
            'actor_user_id' => Auth::id(),
            'action' => $request->input('action', 'refund'),
        ]);

        return app(RefundController::class)->handle($request);
    }
}
