<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\AttendanceService;
use App\Support\AttendancePhotoStorage;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class AttendanceController extends Controller
{
    use PosApiResponse;

    public function __construct(
        private readonly AttendanceService $attendance,
    ) {}

    public function handle(Request $request): JsonResponse
    {
        try {
            if ($request->isMethod('options')) {
                return $this->posSuccess();
            }

            if ($request->isMethod('get')) {
                return $this->getBoard($request);
            }

            if ($request->isMethod('post')) {
                return $this->clock($request);
            }

            return $this->posError('Method not allowed', 405);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\RuntimeException $e) {
            return $this->posError($e->getMessage(), 422);
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }

    private function getBoard(Request $request): JsonResponse
    {
        $date = trim((string) ($request->query('date') ?? Carbon::today()->format('Y-m-d')));
        $branchId = PosHelpers::optionalInt($request->query('branch_id'));
        $userId = PosHelpers::optionalInt($request->query('user_id'));
        $actorUserId = PosHelpers::optionalInt($request->query('actor_user_id'));

        if ($userId !== null && $userId > 0) {
            if ($actorUserId !== null && $actorUserId > 0 && $actorUserId !== $userId) {
                $actor = PosHelpers::fetchActorUser($actorUserId);
                if (! $actor || ! PosHelpers::isAdminRole((string) ($actor['role'] ?? ''))) {
                    return $this->posError('You can only view your own attendance', 403);
                }
            }

            return $this->posSuccess([
                'date' => $date,
                'schedule' => $this->attendance->schedule(),
                'status' => $this->attendance->userStatus($userId, $date),
            ]);
        }

        if ($request->query('report') === 'punctuality') {
            PosHelpers::requireAdminActor($actorUserId);
            $start = trim((string) ($request->query('start') ?? $date));
            $end = trim((string) ($request->query('end') ?? $date));

            return $this->posSuccess([
                'range' => ['start' => $start, 'end' => $end],
                'schedule' => $this->attendance->schedule(),
                'rows' => $this->attendance->punctualityReport($start, $end, $branchId),
            ]);
        }

        if ($request->query('report') === 'events') {
            PosHelpers::requireAdminActor($actorUserId);
            $start = trim((string) ($request->query('start') ?? $date));
            $end = trim((string) ($request->query('end') ?? $date));

            return $this->posSuccess([
                'range' => ['start' => $start, 'end' => $end],
                'rows' => $this->attendance->eventLog($start, $end, $branchId),
            ]);
        }

        PosHelpers::requireAuthenticatedActor($actorUserId);

        return $this->posSuccess([
            'date' => $date,
            'schedule' => $this->attendance->schedule(),
            'rows' => $this->attendance->dailyBoard($date, $branchId),
        ]);
    }

    private function clock(Request $request): JsonResponse
    {
        $body = $request->all();
        $action = strtolower(trim((string) ($body['action'] ?? '')));
        $userId = (int) ($body['user_id'] ?? 0);
        $branchId = (int) ($body['branch_id'] ?? 1);
        $latitude = (float) ($body['latitude'] ?? 0);
        $longitude = (float) ($body['longitude'] ?? 0);
        $accuracy = isset($body['accuracy_meters']) ? (float) $body['accuracy_meters'] : null;
        $deviceInfo = trim((string) ($body['device_info'] ?? ''));
        $actorUserId = PosHelpers::currentActorId($request, $body);

        if (! in_array($action, ['clock_in', 'clock_out', 'break_in', 'break_out'], true)) {
            return $this->posError('action must be clock_in, clock_out, break_in, or break_out', 400);
        }

        if ($userId <= 0) {
            return $this->posError('user_id is required', 400);
        }

        $adminManual = ! empty($body['admin_manual']);
        $faceVerified = ! empty($body['face_verified']);
        $photoBase64 = trim((string) ($body['photo_base64'] ?? ''));
        $tabletManual = ! empty($body['tablet_manual']) || $photoBase64 !== '';

        if ($adminManual) {
            PosHelpers::requireManagementActor($actorUserId);
        } elseif ($tabletManual) {
            PosHelpers::requireAuthenticatedActor($actorUserId);
        } elseif (AttendanceService::requiresGps() && $latitude === 0.0 && $longitude === 0.0) {
            return $this->posError('GPS location is required for attendance', 400);
        }

        if ($actorUserId !== null && $actorUserId > 0 && $actorUserId !== $userId) {
            if (! $faceVerified && ! $adminManual && ! $tabletManual) {
                $actor = PosHelpers::fetchActorUser($actorUserId);
                if (! $actor || ! PosHelpers::isManagementRole((string) ($actor['role'] ?? ''))) {
                    return $this->posError('You can only clock in/out for your own account', 403);
                }
            }
        }

        $photoUrl = null;
        if ($photoBase64 !== '') {
            try {
                $saved = AttendancePhotoStorage::saveBase64(
                    $photoBase64,
                    (string) ($body['photo_mime'] ?? 'image/jpeg'),
                );
                $photoUrl = $saved['image_url'];
            } catch (\InvalidArgumentException $e) {
                return $this->posError($e->getMessage(), 422);
            }
        }

        $result = $this->attendance->clock(
            $action,
            $userId,
            $branchId,
            $latitude,
            $longitude,
            $accuracy,
            $deviceInfo !== '' ? $deviceInfo : null,
            isset($body['face_verified']) ? (bool) $body['face_verified'] : null,
            $adminManual || $tabletManual,
            $photoUrl,
        );

        $message = match ($action) {
            'clock_in' => 'Clocked in successfully',
            'clock_out' => 'Clocked out successfully',
            'break_in' => 'Break started',
            'break_out' => 'Break ended',
            default => 'Recorded',
        };

        return $this->posSuccess([
            'message' => $message,
            'data' => $result,
        ]);
    }
}
