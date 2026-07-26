<?php

namespace App\Support;

use Illuminate\Http\JsonResponse;
use Throwable;

trait PosApiResponse
{
    protected function posSuccess(
        array $payload = [],
        int $status = 200,
    ): JsonResponse {
        return response()->json([
            'success' => true,
            ...$payload,
        ], $status);
    }

    protected function posError(
        string $message,
        int $status = 400,
        array $extra = [],
    ): JsonResponse {
        $clientMessage = PosApiExceptionMessage::sanitizeMessage(
            $message,
            $status >= 500,
        );

        return response()->json([
            'success' => false,
            'message' => $clientMessage,
            ...$extra,
        ], $status);
    }

    protected function posServerError(
        Throwable $throwable,
        int $status = 500,
        array $extra = [],
    ): JsonResponse {
        PosApiLogger::error('pos_api.server_error', [], $throwable);

        return $this->posError(
            PosApiExceptionMessage::forClient($throwable),
            $status,
            $extra,
        );
    }
}
