<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Api\Pos\InventoryController as PosInventoryApiController;
use App\Http\Controllers\Api\Pos\InventoryReportController;
use App\Http\Controllers\Controller;
use App\Services\Pos\StockEntryFixService;
use App\Services\Pos\StockUpdateService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;

class InventoryPageController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('pos/inventory');
    }

    public function report(Request $request): JsonResponse
    {
        return app(InventoryReportController::class)->handle($request);
    }

    public function updateStockWithPin(Request $request): JsonResponse
    {
        $varietyId = (int) $request->input('variety_id', 0);

        try {
            $result = app(StockUpdateService::class)->update(
                productId: (int) $request->input('product_id', 0),
                varietyId: $varietyId > 0 ? $varietyId : null,
                newStock: (float) $request->input('stock', -1),
                reason: (string) $request->input('reason', ''),
                pin: (string) $request->input('pin', ''),
                actorUserId: Auth::id(),
            );
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['message' => 'Stock updated', 'data' => $result]);
    }

    public function stockEntries(Request $request): JsonResponse
    {
        return response()->json([
            'data' => app(StockEntryFixService::class)->recentEntries(
                (int) $request->query('product_id', 0),
            ),
        ]);
    }

    public function fixStockEntry(Request $request): JsonResponse
    {
        try {
            $result = app(StockEntryFixService::class)->fix(
                entryId: (int) $request->input('entry_id', 0),
                newDelta: (float) $request->input('quantity', 0),
                reason: (string) $request->input('reason', ''),
                pin: (string) $request->input('pin', ''),
                actorUserId: Auth::id(),
            );
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['message' => 'Stock entry corrected', 'data' => $result]);
    }

    public function adjustStock(Request $request): JsonResponse
    {
        $request->merge(['actor_user_id' => Auth::id()]);

        return app(PosInventoryApiController::class)->handle($request);
    }
}
