<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Api\Pos\CouponController;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;

class PromotionsPageController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('pos/promotions');
    }

    public function coupons(Request $request): JsonResponse
    {
        if (! $request->has('include_inactive')) {
            $request->query->set('include_inactive', '1');
        }

        return app(CouponController::class)->handle($request);
    }

    public function storeCoupon(Request $request): JsonResponse
    {
        $request->merge(['actor_user_id' => Auth::id()]);

        return app(CouponController::class)->handle($request);
    }
}
