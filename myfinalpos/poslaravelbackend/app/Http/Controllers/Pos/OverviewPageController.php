<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Inertia\Inertia;
use Inertia\Response;

class OverviewPageController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('pos/overview');
    }

    public function liveWall(): Response
    {
        return Inertia::render('pos/live-wall');
    }

    public function health(): JsonResponse
    {
        $database = config('database.connections.mysql.database');
        $connected = false;
        $error = null;

        try {
            DB::connection()->getPdo();
            $connected = true;
        } catch (\Throwable $e) {
            $error = $e->getMessage();
        }

        return response()->json([
            'success' => $connected,
            'message' => $connected
                ? 'Muñoz Macam Agri backend is running'
                : 'App is up but database connection failed',
            'database' => $database,
            'database_connected' => $connected,
            'database_error' => $connected ? null : $error,
        ], $connected ? 200 : 503);
    }
}
