<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\FaceProfileService;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FaceProfileController extends Controller
{
    use PosApiResponse;

    public function __construct(
        private readonly FaceProfileService $faces,
    ) {}

    public function handle(Request $request): JsonResponse
    {
        try {
            if ($request->isMethod('options')) {
                return $this->posSuccess();
            }

            if ($request->isMethod('get')) {
                $userId = PosHelpers::optionalInt($request->query('user_id'));
                if ($userId !== null && $userId > 0) {
                    return $this->posSuccess([
                        'data' => $this->faces->statusForUser($userId),
                    ]);
                }

                $actorUserId = PosHelpers::optionalInt($request->query('actor_user_id'));

                if ($request->query('staff') === '1') {
                    PosHelpers::requireManagementActor($actorUserId);

                    return $this->posSuccess(['data' => $this->faces->staffDirectory()]);
                }

                PosHelpers::requireManagementActor($actorUserId);

                return $this->posSuccess(['data' => $this->faces->list()]);
            }

            if (! $request->isMethod('post')) {
                return $this->posError('Method not allowed', 405);
            }

            $body = $request->all();
            $action = strtolower(trim((string) ($body['action'] ?? '')));
            $actorUserId = PosHelpers::currentActorId($request, $body) ?? 0;

            return match ($action) {
                'enroll' => $this->enroll($body, $actorUserId),
                'verify' => $this->verify($body),
                'delete' => $this->delete($body, $actorUserId),
                default => $this->posError('Unknown action', 422),
            };
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\RuntimeException $e) {
            return $this->posError($e->getMessage(), 422);
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }

    public function listForWeb(int $actorUserId): JsonResponse
    {
        try {
            PosHelpers::requireManagementActor($actorUserId);

            return response()->json([
                'success' => true,
                'data' => $this->faces->list(),
            ]);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    public function enrollForWeb(Request $request, int $actorUserId): JsonResponse
    {
        try {
            PosHelpers::requireManagementActor($actorUserId);
            $saved = $this->faces->enroll(
                (int) $request->input('user_id', 0),
                $this->enrollmentPayload($request->all()),
                $actorUserId,
                PosHelpers::optionalInt($request->input('confidence')),
            );

            return response()->json([
                'success' => true,
                'message' => 'Face enrolled successfully',
                'data' => $saved,
            ]);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        } catch (\Throwable $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 500);
        }
    }

    public function verifyForWeb(Request $request): JsonResponse
    {
        try {
            $result = $this->faces->verify((array) $request->input('descriptor', []));

            return response()->json([
                'success' => true,
                'data' => $result,
            ]);
        } catch (\RuntimeException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        } catch (\Throwable $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 500);
        }
    }

    public function deleteForWeb(int $userId, int $actorUserId): JsonResponse
    {
        try {
            PosHelpers::requireManagementActor($actorUserId);
            $this->faces->remove($userId, $actorUserId);

            return response()->json([
                'success' => true,
                'message' => 'Face profile removed',
            ]);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 500);
        }
    }

    /**
     * @param  array<string, mixed>  $body
     */
    private function enroll(array $body, int $actorUserId): JsonResponse
    {
        PosHelpers::requireManagementActor($actorUserId);

        $saved = $this->faces->enroll(
            (int) ($body['user_id'] ?? 0),
            $this->enrollmentPayload($body),
            $actorUserId,
            PosHelpers::optionalInt($body['confidence'] ?? null),
        );

        return $this->posSuccess([
            'message' => 'Face enrolled successfully',
            'data' => $saved,
        ]);
    }

    /**
     * @param  array<string, mixed>  $body
     * @return list<float|int>|list<list<float|int>>
     */
    private function enrollmentPayload(array $body): array
    {
        $descriptors = $body['descriptors'] ?? null;
        if (is_array($descriptors) && $descriptors !== []) {
            return $descriptors;
        }

        return (array) ($body['descriptor'] ?? []);
    }

    /**
     * @param  array<string, mixed>  $body
     */
    private function verify(array $body): JsonResponse
    {
        $result = $this->faces->verify((array) ($body['descriptor'] ?? []));

        return $this->posSuccess(['data' => $result]);
    }

    /**
     * @param  array<string, mixed>  $body
     */
    private function delete(array $body, int $actorUserId): JsonResponse
    {
        PosHelpers::requireManagementActor($actorUserId);
        $userId = (int) ($body['user_id'] ?? 0);
        if ($userId <= 0) {
            return $this->posError('user_id is required', 422);
        }

        $this->faces->remove($userId, $actorUserId);

        return $this->posSuccess(['message' => 'Face profile removed']);
    }
}
