<?php

namespace App\Http\Controllers;

use App\Services\Pos\DashboardService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class DashboardPageController extends Controller
{
    public function __construct(
        private readonly DashboardService $dashboard,
    ) {}

    public function index(): Response
    {
        return Inertia::render('dashboard');
    }

    public function data(Request $request): JsonResponse
    {
        try {
            return response()->json([
                'success' => true,
                'data' => $this->dashboard->payload($request),
            ]);
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to load dashboard: '.$e->getMessage(),
            ], 500);
        }
    }
}
