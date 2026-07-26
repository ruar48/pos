<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\PosMonitorService;
use App\Services\Pos\ReportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PosMonitorPageController extends Controller
{
    public function __construct(
        private readonly PosMonitorService $monitor,
        private readonly ReportService $reports,
    ) {}

    public function subscribe(Request $request): JsonResponse
    {
        $userId = (int) $request->user()?->id;
        if ($userId <= 0) {
            return response()->json(['success' => false, 'message' => 'Unauthorized'], 401);
        }

        $terminalId = trim((string) $request->input('terminal_id', ''));
        $sinceRevision = trim((string) $request->input('revision', ''));
        $this->monitor->touchWatcher($userId, $terminalId !== '' ? $terminalId : null);

        return response()->json([
            'success' => true,
            'data' => $this->monitor->livePayload(
                $userId,
                $terminalId !== '' ? $terminalId : null,
                $sinceRevision !== '' ? $sinceRevision : null,
            ),
        ]);
    }

    public function unsubscribe(Request $request): JsonResponse
    {
        $userId = (int) $request->user()?->id;
        if ($userId > 0) {
            $this->monitor->removeWatcher($userId);
        }

        return response()->json(['success' => true]);
    }

    public function live(Request $request): JsonResponse
    {
        $userId = (int) $request->user()?->id;
        $terminalId = trim((string) $request->query('terminal_id', ''));
        $sinceRevision = trim((string) $request->query('revision', ''));

        return response()->json([
            'success' => true,
            'data' => $this->monitor->livePayload(
                $userId > 0 ? $userId : null,
                $terminalId !== '' ? $terminalId : null,
                $sinceRevision !== '' ? $sinceRevision : null,
            ),
        ]);
    }

    public function watch(Request $request): JsonResponse
    {
        $userId = (int) $request->user()?->id;
        if ($userId > 0) {
            $terminalId = trim((string) $request->query('terminal_id', ''));
            $this->monitor->touchWatcher(
                $userId,
                $terminalId !== '' ? $terminalId : null,
            );
        }

        $sinceRevision = trim((string) $request->query('revision', ''));

        return response()->json([
            'success' => true,
            'data' => $this->monitor->watch(
                $sinceRevision !== '' ? $sinceRevision : null,
            ),
        ]);
    }

    public function sales(Request $request): JsonResponse
    {
        [$start, $end] = $this->reports->resolveRange($request);

        return response()->json([
            'success' => true,
            'data' => $this->reports->liveWallSales($start, $end),
        ]);
    }
}
