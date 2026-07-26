<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PosStubController extends Controller
{
    use PosApiResponse;

    public function notMigrated(Request $request, string $endpoint): JsonResponse
    {
        return $this->posError(
            "{$endpoint} is not available on this API yet.",
            501,
        );
    }
}
