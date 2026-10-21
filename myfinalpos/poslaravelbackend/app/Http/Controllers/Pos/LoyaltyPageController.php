<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Api\Pos\CustomerController;
use App\Http\Controllers\Api\Pos\LoyaltyCardController;
use App\Http\Controllers\Controller;
use App\Services\Pos\CustomerLoyaltyService;
use App\Services\Pos\LoyaltyActivityService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;
use Symfony\Component\HttpFoundation\StreamedResponse;

class LoyaltyPageController extends Controller
{
    public function loyalty(): Response
    {
        return Inertia::render('pos/loyalty');
    }

    public function overview(): JsonResponse
    {
        $service = app(CustomerLoyaltyService::class);

        return response()->json([
            'overview' => $service->overview(),
            'settings' => $service->loyaltySettings(),
        ]);
    }

    public function cards(Request $request): JsonResponse
    {
        return app(LoyaltyCardController::class)->handle($request);
    }

    public function activity(Request $request): JsonResponse
    {
        return response()->json(app(LoyaltyActivityService::class)->activity(
            $request->only(['action', 'q', 'from', 'to']),
            (int) $request->query('limit', 200),
        ));
    }

    public function exportActivity(Request $request): StreamedResponse
    {
        return app(LoyaltyActivityService::class)->downloadExcel(
            $request->only(['action', 'q', 'from', 'to']),
        );
    }

    public function customerList(Request $request): JsonResponse
    {
        $rows = app(CustomerLoyaltyService::class)->customersWithPoints(
            $request->query('q'),
        );

        return response()->json(['data' => $rows]);
    }

    public function storeCustomer(Request $request): JsonResponse
    {
        $request->merge(['actor_user_id' => Auth::id()]);

        return app(CustomerController::class)->handle($request);
    }

    public function issueCard(Request $request): JsonResponse
    {
        $request->merge(['actor_user_id' => Auth::id()]);

        return app(LoyaltyCardController::class)->handle($request);
    }

    public function linkNfc(Request $request): JsonResponse
    {
        $request->merge([
            'actor_user_id' => Auth::id(),
            'action' => 'link_nfc',
        ]);

        return app(LoyaltyCardController::class)->handle($request);
    }

    public function updateSettings(Request $request): JsonResponse
    {
        $settings = app(CustomerLoyaltyService::class)->updateLoyaltySettings(
            $request->all(),
            Auth::id(),
        );

        return response()->json([
            'message' => 'Loyalty program settings saved',
            'settings' => $settings,
        ]);
    }
}
