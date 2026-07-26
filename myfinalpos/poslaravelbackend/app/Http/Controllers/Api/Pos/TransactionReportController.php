<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\TransactionReportService;
use App\Support\PosApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TransactionReportController extends Controller
{
    use PosApiResponse;

    public function __construct(private readonly TransactionReportService $reports) {}

    public function handle(Request $request): JsonResponse
    {
        if ($request->isMethod('OPTIONS')) {
            return $this->posSuccess();
        }

        if (! $request->isMethod('GET')) {
            return $this->posError('Method not allowed', 405);
        }

        try {
            return $this->posSuccess(['data' => $this->reports->fetch($request)]);
        } catch (\InvalidArgumentException $e) {
            return $this->posError($e->getMessage(), 400);
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
