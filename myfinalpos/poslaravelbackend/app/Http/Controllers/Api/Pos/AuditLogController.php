<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class AuditLogController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        try {
            if ($request->isMethod('options')) {
                return $this->posSuccess();
            }

            if (! $request->isMethod('get')) {
                return $this->posError('Method not allowed', 405);
            }

            $actorUserId = PosHelpers::optionalInt($request->query('actor_user_id'));
            PosHelpers::requireAdminActor($actorUserId);

            $limit = max(1, min(500, (int) ($request->query('limit') ?? 100)));
            $module = trim((string) ($request->query('module') ?? ''));

            $sql = 'SELECT a.*, u.full_name AS user_name, u.email AS user_email
                    FROM audit_logs a
                    LEFT JOIN users u ON u.id = a.user_id
                    WHERE 1=1';
            $params = [];

            if ($module !== '') {
                $sql .= ' AND a.module = ?';
                $params[] = $module;
            }

            $sql .= ' ORDER BY a.created_at DESC, a.id DESC LIMIT '.$limit;

            $rows = DB::select($sql, $params);

            return $this->posSuccess([
                'data' => array_map(
                    fn ($row) => PosHelpers::auditLogRowToArray((array) $row),
                    $rows,
                ),
            ]);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
