<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Api\Pos\InventoryController as PosInventoryApiController;
use App\Http\Controllers\Api\Pos\InventoryReportController;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
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

    public function adjustStock(Request $request): JsonResponse
    {
        return app(PosInventoryApiController::class)->handle($request);
    }
}
