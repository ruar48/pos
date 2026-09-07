<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\AppSettingsService;
use App\Services\Pos\RegisterReadingService;
use App\Services\Pos\RegisterSessionService;
use App\Support\PosHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use RuntimeException;
use Inertia\Inertia;
use Inertia\Response;
use Throwable;

/**
 * Admin-side X reading / Z reading.
 *
 * Same service layer as the tablet endpoint, so a reading taken here and one
 * taken at the register produce identical figures and share the same Z
 * counter — the counters live on the terminal, not on the client.
 */
class RegisterReadingPageController extends Controller
{
    public function __construct(
        private readonly RegisterReadingService $readings,
        private readonly RegisterSessionService $sessions,
        private readonly AppSettingsService $settings,
    ) {}

    public function index(): Response
    {
        return Inertia::render('pos/readings', [
            'terminals' => $this->knownTerminals(),
            'machineIdentity' => $this->readings->machineIdentity(),
            'missingIdentityFields' => $this->readings->missingIdentityFields(),
            'uncapturedBirFields' => RegisterReadingService::uncapturedBirFields(),
            'hasCashDrawerPin' => (bool) (
                $this->settings->read()['has_cash_drawer_pin'] ?? false
            ),
        ]);
    }

    public function status(Request $request): JsonResponse
    {
        return $this->json(function () use ($request) {
            $terminalId = $this->terminalId($request);

            return [
                'terminal_id' => $terminalId,
                'session' => $this->sessions->openSessionFor($terminalId),
                'counters' => $this->sessions->countersFor($terminalId),
                'history' => $this->readings->history($terminalId, 20),
            ];
        });
    }

    public function xReading(Request $request): JsonResponse
    {
        return $this->json(fn () => [
            'reading' => $this->readings->xReading(
                $this->terminalId($request),
                $request->user()?->id,
            ),
        ]);
    }

    public function zReading(Request $request): JsonResponse
    {
        return $this->json(function () use ($request) {
            $pin = trim((string) $request->input('cash_drawer_pin', ''));
            if (! PosHelpers::verifyCashDrawerPin($pin)) {
                throw new InvalidArgumentException(
                    'Invalid or missing cash drawer PIN',
                );
            }

            return [
                'reading' => $this->readings->zReading(
                    $this->terminalId($request),
                    $request->user()?->id,
                ),
            ];
        });
    }

    public function openSession(Request $request): JsonResponse
    {
        return $this->json(fn () => [
            'session' => $this->sessions->open(
                terminalId: $this->terminalId($request),
                cashierUserId: $request->user()?->id,
                openingCash: (float) $request->input('opening_cash', 0),
            ),
        ]);
    }

    private function terminalId(Request $request): string
    {
        $terminalId = trim((string) $request->input(
            'terminal_id',
            $request->query('terminal_id', ''),
        ));

        if ($terminalId === '') {
            throw new InvalidArgumentException('Select a terminal first.');
        }

        return $terminalId;
    }

    /**
     * Terminals that have traded or been opened before, plus the configured
     * default, so the page has something to select on a fresh install.
     *
     * @return list<string>
     */
    private function knownTerminals(): array
    {
        $terminals = [];

        if (PosHelpers::tableExists('pos_terminal_counters')) {
            $terminals = DB::table('pos_terminal_counters')
                ->orderBy('terminal_id')
                ->pluck('terminal_id')
                ->all();
        }

        if (PosHelpers::columnExists('orders', 'terminal_id')) {
            $fromOrders = DB::table('orders')
                ->whereNotNull('terminal_id')
                ->where('terminal_id', '!=', '')
                ->distinct()
                ->pluck('terminal_id')
                ->all();
            $terminals = array_merge($terminals, $fromOrders);
        }

        $configured = trim((string) (
            $this->settings->read()['receipt_store']['pos_terminal_id'] ?? ''
        ));
        if ($configured !== '') {
            $terminals[] = $configured;
        }

        $terminals = array_values(array_unique(array_filter(
            array_map('strval', $terminals),
            static fn ($id) => trim($id) !== '',
        )));
        sort($terminals);

        return $terminals;
    }

    private function json(callable $handler): JsonResponse
    {
        try {
            return response()->json(['success' => true] + $handler());
        } catch (InvalidArgumentException $e) {
            return response()->json(
                ['success' => false, 'message' => $e->getMessage()],
                403,
            );
        } catch (RuntimeException $e) {
            return response()->json(
                ['success' => false, 'message' => $e->getMessage()],
                409,
            );
        } catch (Throwable $e) {
            report($e);

            return response()->json(
                ['success' => false, 'message' => 'Could not complete the reading.'],
                500,
            );
        }
    }
}
