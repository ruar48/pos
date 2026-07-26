<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\PosMonitorService;
use App\Services\Pos\ReportService;
use App\Support\PosApiResponse;
use Illuminate\Support\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PosMonitorController extends Controller
{
    use PosApiResponse;

    public function __construct(
        private readonly PosMonitorService $monitor,
        private readonly ReportService $reports,
    ) {}

    public function handle(Request $request): JsonResponse
    {
        if ($request->isMethod('options')) {
            return response()->json([], 204);
        }

        $action = strtolower(trim((string) $request->query('action', $request->input('action', ''))));

        if ($request->isMethod('get') && ($action === '' || $action === 'active')) {
            return $this->posSuccess([
                'data' => [
                    'active' => $this->monitor->hasActiveWatchers(),
                ],
            ]);
        }

        if ($request->isMethod('get') && $action === 'live') {
            $sinceRevision = trim((string) $request->query('revision', ''));

            return $this->posSuccess([
                'data' => $this->monitor->livePayload(
                    null,
                    null,
                    $sinceRevision !== '' ? $sinceRevision : null,
                ),
            ]);
        }

        if ($request->isMethod('get') && $action === 'watch') {
            $userId = (int) ($request->query('actor_user_id') ?? 0);
            if ($userId > 0) {
                $this->monitor->touchWatcher($userId, null);
            }

            $sinceRevision = trim((string) $request->query('revision', ''));

            return $this->posSuccess([
                'data' => $this->monitor->watch(
                    $sinceRevision !== '' ? $sinceRevision : null,
                ),
            ]);
        }

        if ($request->isMethod('get') && $action === 'sales') {
            [$start, $end] = $this->resolveSalesRange($request);

            return $this->posSuccess([
                'data' => $this->reports->liveWallSales($start, $end),
            ]);
        }

        if ($request->isMethod('post') && $action === 'subscribe') {
            $userId = (int) ($request->input('actor_user_id') ?? 0);
            if ($userId <= 0) {
                return $this->posError('actor_user_id is required', 422);
            }

            $sinceRevision = trim((string) $request->input('revision', ''));
            $this->monitor->touchWatcher($userId, null);

            return $this->posSuccess([
                'data' => $this->monitor->livePayload(
                    $userId,
                    null,
                    $sinceRevision !== '' ? $sinceRevision : null,
                ),
            ]);
        }

        if ($request->isMethod('post') && $action === 'unsubscribe') {
            $userId = (int) ($request->input('actor_user_id') ?? 0);
            if ($userId > 0) {
                $this->monitor->removeWatcher($userId);
            }

            return $this->posSuccess(['data' => ['unsubscribed' => true]]);
        }

        if ($request->isMethod('post') && $action === 'presence') {
            $body = $request->all();
            unset($body['action']);

            $terminalId = $this->monitor->resolveRegisterId($body);
            $this->monitor->touchPresence($terminalId, $body);

            return $this->posSuccess(['data' => ['present' => true]]);
        }

        if ($request->isMethod('post') && $action === 'disconnect') {
            $body = $request->all();
            unset($body['action']);

            $terminalId = $this->monitor->resolveRegisterId($body);
            $this->monitor->disconnectTerminal(
                $terminalId,
                (int) ($body['cashier_id'] ?? 0),
            );

            return $this->posSuccess(['data' => ['disconnected' => true]]);
        }

        if ($request->isMethod('post') && $action === 'publish') {
            $body = $request->all();
            unset($body['action']);

            $status = strtolower(trim((string) ($body['status'] ?? 'idle')));
            if (! in_array($status, ['idle', 'cart', 'payment', 'success'], true)) {
                $status = 'idle';
            }

            $isCritical = in_array($status, ['payment', 'success'], true);
            if (! $isCritical && ! $this->monitor->hasActiveWatchers()) {
                return $this->posSuccess([
                    'data' => ['skipped' => true],
                ]);
            }

            $terminalId = $this->monitor->resolveRegisterId($body);

            $success = null;
            if ($status === 'success' && is_array($body['success'] ?? null)) {
                $success = [
                    'invoice_number' => (string) ($body['success']['invoice_number'] ?? ''),
                    'payment_method' => (string) ($body['success']['payment_method'] ?? 'Cash'),
                    'total' => round((float) ($body['success']['total'] ?? 0), 2),
                    'customer_name' => (string) ($body['success']['customer_name'] ?? 'Walk-in'),
                    'items' => is_array($body['success']['items'] ?? null) ? $body['success']['items'] : [],
                    'completed_at' => (string) ($body['success']['completed_at'] ?? now()->toIso8601String()),
                ];
            }

            $this->monitor->publish($terminalId, [
                'terminal_label' => $this->monitor->resolveRegisterLabel($body, $terminalId),
                'register_code' => trim((string) ($body['register_code'] ?? $body['terminal_label'] ?? 'POS-01')),
                'branch_id' => (int) ($body['branch_id'] ?? 1),
                'branch_name' => (string) ($body['branch_name'] ?? 'Main Branch'),
                'cashier_id' => (int) ($body['cashier_id'] ?? 0),
                'cashier_name' => (string) ($body['cashier_name'] ?? 'Cashier'),
                'cashier_username' => trim((string) ($body['cashier_username'] ?? '')),
                'customer_name' => (string) ($body['customer_name'] ?? 'Walk-in'),
                'order_type' => (string) ($body['order_type'] ?? 'Retail'),
                'is_payment_mode' => $status === 'payment',
                'status' => $status,
                'items' => is_array($body['items'] ?? null) ? $body['items'] : [],
                'item_count' => (int) ($body['item_count'] ?? 0),
                'subtotal' => round((float) ($body['subtotal'] ?? 0), 2),
                'discount' => round((float) ($body['discount'] ?? 0), 2),
                'vat' => round((float) ($body['vat'] ?? 0), 2),
                'total' => round((float) ($body['total'] ?? 0), 2),
                'success' => $success,
                'monitor_reset' => (bool) ($body['monitor_reset'] ?? false),
            ]);

            return $this->posSuccess(['data' => ['published' => true]]);
        }

        return $this->posError('Unsupported monitor action', 405);
    }

    /**
     * @return array{0: string, 1: string}
     */
    private function resolveSalesRange(Request $request): array
    {
        $today = Carbon::today();
        $start = trim((string) $request->query('start', ''));
        $end = trim((string) $request->query('end', ''));

        if ($start === '' || $end === '') {
            $iso = $today->format('Y-m-d');

            return ["{$iso} 00:00:00", "{$iso} 23:59:59"];
        }

        return ["{$start} 00:00:00", "{$end} 23:59:59"];
    }
}
