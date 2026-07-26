<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\AppSettingsService;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SettingsController extends Controller
{
    use PosApiResponse;

    public function __construct(
        private readonly AppSettingsService $settings,
    ) {}

    public function handle(Request $request): JsonResponse
    {
        try {
            if ($request->isMethod('get')) {
                $revision = $request->query('revision');
                if ($revision !== null) {
                    return $this->posSuccess([
                        'data' => $this->settings->sync((string) $revision),
                    ]);
                }

                return $this->posSuccess([
                    'data' => $this->settings->read(),
                ]);
            }

            if (! $request->isMethod('post')) {
                return $this->posError('Method not allowed', 405);
            }

            if (! PosHelpers::tableExists('app_settings')) {
                return $this->posError('POS settings are not ready.', 503);
            }

            $body = $request->all();
            $actorUserId = PosHelpers::currentActorId($request, $body);
            $saved = $this->settings->save($body, $actorUserId);

            return $this->posSuccess([
                'message' => 'Settings saved successfully',
                'data' => $saved,
            ]);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
