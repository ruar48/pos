<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Api\Pos\CustomerController;
use App\Http\Controllers\Api\Pos\LoyaltyCardController;
use App\Http\Controllers\Controller;
use App\Services\Pos\CustomerLoyaltyService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;

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
