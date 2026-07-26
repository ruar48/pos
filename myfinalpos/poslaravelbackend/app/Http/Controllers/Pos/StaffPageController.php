<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Api\Pos\AttendanceController;
use App\Http\Controllers\Api\Pos\FaceProfileController;
use App\Http\Controllers\Api\Pos\UserController;
use App\Http\Controllers\Controller;
use App\Services\Pos\AttendanceExportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;

class StaffPageController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('pos/staff');
    }

    public function users(Request $request): JsonResponse
    {
        $request->query->set('actor_user_id', (string) Auth::id());

        return app(UserController::class)->handle($request);
    }

    public function storeUser(Request $request): JsonResponse
    {
        $request->merge(['actor_user_id' => Auth::id()]);

        return app(UserController::class)->handle($request);
    }

    public function attendance(Request $request): JsonResponse
    {
        $request->query->set('actor_user_id', (string) Auth::id());

        return app(AttendanceController::class)->handle($request);
    }

    public function exportAttendance(Request $request)
    {
        $start = trim((string) $request->query('start', ''));
        $end = trim((string) $request->query('end', ''));

        if ($start === '' || $end === '') {
            return response()->json([
                'success' => false,
                'message' => 'Start and end dates are required',
            ], 400);
        }

        $branchId = (int) $request->query('branch_id', 0);

        return app(AttendanceExportService::class)->downloadResponse(
            $start,
            $end,
            $branchId > 0 ? $branchId : null,
        );
    }

    public function clockAttendance(Request $request): JsonResponse
    {
        $faceVerified = ! empty($request->input('face_verified'));
        $deviceInfo = trim((string) $request->input('device_info', ''));

        $request->merge([
            'admin_manual' => true,
            'actor_user_id' => Auth::id(),
            'face_verified' => $faceVerified,
            'device_info' => $deviceInfo !== ''
                ? $deviceInfo
                : (! empty($request->input('photo_base64'))
                    ? 'Web Manual Photo'
                    : ($faceVerified ? 'Web Face Terminal' : 'Web Admin Manual')),
        ]);

        return app(AttendanceController::class)->handle($request);
    }

    public function faceProfiles(): JsonResponse
    {
        return app(FaceProfileController::class)->listForWeb((int) Auth::id());
    }

    public function enrollFace(Request $request): JsonResponse
    {
        return app(FaceProfileController::class)->enrollForWeb($request, (int) Auth::id());
    }

    public function verifyFace(Request $request): JsonResponse
    {
        return app(FaceProfileController::class)->verifyForWeb($request);
    }

    public function deleteFace(int $userId): JsonResponse
    {
        return app(FaceProfileController::class)->deleteForWeb($userId, (int) Auth::id());
    }
}
