<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\RegisterReadingService;
use App\Services\Pos\RegisterSessionService;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use InvalidArgumentException;
use RuntimeException;
use Throwable;

/**
 * X reading / Z reading endpoints for the tablet register.
 *
 * Actions (via ?action= or the `action` field):
 *   status  GET   - open shift and counters for a terminal
 *   open    POST  - start a shift
 *   x       POST  - interim reading, changes nothing
 *   z       POST  - closing reading, PIN-gated and irreversible
 *   history GET   - past readings for a terminal
 */
class RegisterReadingController extends Controller
{
    use PosApiResponse;

    public function __construct(
        private readonly RegisterReadingService $readings,
        private readonly RegisterSessionService $sessions,
    ) {}

    public function handle(Request $request): JsonResponse
    {
        if (! PosHelpers::tableExists('pos_register_sessions')) {
            return $this->posError(
                'Register readings are not set up yet. Run php artisan migrate.',
                503,
            );
        }

        $action = strtolower(trim((string) (
            $request->input('action') ?? $request->query('action', 'status')
        )));

        $terminalId = trim((string) (
            $request->input('terminal_id') ?? $request->query('terminal_id', '')
        ));
        if ($terminalId === '') {
            return $this->posError('terminal_id is required', 422);
        }

        try {
            return match ($action) {
                'status' => $this->status($terminalId),
                'open' => $this->open($request, $terminalId),
                'x' => $this->xReading($request, $terminalId),
                'z' => $this->zReading($request, $terminalId),
                'history' => $this->history($request, $terminalId),
                default => $this->posError('Unknown action: ' . $action, 400),
            };
        } catch (InvalidArgumentException $e) {
            return $this->posError($e->getMessage(), 403);
        } catch (RuntimeException $e) {
            return $this->posError($e->getMessage(), 409);
        } catch (Throwable $e) {
            report($e);

            return $this->posError('Could not complete the register reading.', 500);
        }
    }

    private function status(string $terminalId): JsonResponse
    {
        $session = $this->sessions->openSessionFor($terminalId);
        $counters = $this->sessions->countersFor($terminalId);

        return $this->posSuccess([
            'data' => [
                'terminal_id' => $terminalId,
                'session' => $session === null ? null : (array) $session,
                'counters' => (array) $counters,
                'uncaptured_bir_fields' => RegisterReadingService::uncapturedBirFields(),
                'machine_identity' => $this->readings->machineIdentity(),
                'missing_identity_fields' => $this->readings->missingIdentityFields(),
            ],
        ]);
    }

    private function open(Request $request, string $terminalId): JsonResponse
    {
        $session = $this->sessions->open(
            terminalId: $terminalId,
            cashierUserId: $this->intOrNull($request->input('cashier_user_id')),
            openingCash: (float) $request->input('opening_cash', 0),
            branchId: $this->intOrNull($request->input('branch_id')),
        );

        return $this->posSuccess(['data' => (array) $session]);
    }

    private function xReading(Request $request, string $terminalId): JsonResponse
    {
        $reading = $this->readings->xReading(
            $terminalId,
            $this->intOrNull($request->input('taken_by_user_id')),
        );

        return $this->posSuccess(['data' => $reading]);
    }

    /**
     * Z closes the shift and increments a counter that can never be wound
     * back, so it is gated on the cash drawer PIN.
     */
    private function zReading(Request $request, string $terminalId): JsonResponse
    {
        $pin = trim((string) ($request->input('cash_drawer_pin') ?? ''));
        if (! PosHelpers::verifyCashDrawerPin($pin)) {
            throw new InvalidArgumentException(
                'Invalid or missing cash drawer PIN',
            );
        }

        $reading = $this->readings->zReading(
            $terminalId,
            $this->intOrNull($request->input('taken_by_user_id')),
        );

        return $this->posSuccess(['data' => $reading]);
    }

    private function history(Request $request, string $terminalId): JsonResponse
    {
        return $this->posSuccess([
            'data' => $this->readings->history(
                $terminalId,
                (int) $request->query('limit', 50),
            ),
        ]);
    }

    private function intOrNull(mixed $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }

        return (int) $value;
    }
}
