<?php

namespace App\Http\Controllers\Settings;

use App\Http\Controllers\Controller;
use App\Services\Pos\AppSettingsService;
use App\Support\PosHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Inertia\Inertia;
use Inertia\Response;

class StoreSettingsController extends Controller
{
    public function __construct(
        private readonly AppSettingsService $settings,
    ) {}

    public function edit(): Response
    {
        $user = Auth::user();

        return Inertia::render('settings/store', [
            'settings' => $this->settings->read(),
            'branches' => $this->branches(),
            'account' => $user ? [
                'name' => (string) ($user->name ?? ''),
                'email' => (string) ($user->email ?? ''),
                'role' => (string) ($user->role ?? 'user'),
            ] : null,
        ]);
    }

    /**
     * @return list<array{id: int, name: string, location: string|null, code: string|null}>
     */
    private function branches(): array
    {
        if (! PosHelpers::tableExists('branches')) {
            return [
                ['id' => 1, 'name' => 'Main Branch', 'location' => null, 'code' => 'MAIN'],
            ];
        }

        $rows = DB::table('branches')
            ->where('is_active', 1)
            ->orderBy('name')
            ->get(['id', 'name', 'location', 'code']);

        if ($rows->isEmpty()) {
            return [
                ['id' => 1, 'name' => 'Main Branch', 'location' => null, 'code' => 'MAIN'],
            ];
        }

        return $rows->map(static fn ($row) => [
            'id' => (int) $row->id,
            'name' => (string) $row->name,
            'location' => $row->location !== null ? (string) $row->location : null,
            'code' => $row->code !== null ? (string) $row->code : null,
        ])->all();
    }

    public function update(Request $request): JsonResponse
    {
        $userId = (int) Auth::id();
        if ($userId <= 0) {
            return response()->json(['success' => false, 'message' => 'Unauthorized'], 401);
        }

        try {
            $saved = $this->settings->save($request->all(), $userId);

            return response()->json([
                'success' => true,
                'message' => 'Store settings saved',
                'settings' => $saved,
            ]);
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 500);
        }
    }
}
