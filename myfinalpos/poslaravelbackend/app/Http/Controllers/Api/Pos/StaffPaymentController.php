<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class StaffPaymentController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        try {
            if ($request->isMethod('options')) {
                return $this->posSuccess();
            }

            if ($request->isMethod('get')) {
                $actorUserId = PosHelpers::optionalInt($request->query('actor_user_id'));
                PosHelpers::requireAdminActor($actorUserId);

                $userId = PosHelpers::optionalInt($request->query('user_id'));
                $branchId = PosHelpers::optionalInt($request->query('branch_id'));
                $limit = max(1, min(500, (int) ($request->query('limit') ?? 100)));

                $sql = 'SELECT sp.*, u.full_name AS staff_name, b.name AS branch_name,
                               payer.full_name AS paid_by_name
                        FROM staff_payments sp
                        INNER JOIN users u ON u.id = sp.user_id
                        LEFT JOIN branches b ON b.id = sp.branch_id
                        LEFT JOIN users payer ON payer.id = sp.paid_by_user_id
                        WHERE 1=1';
                $params = [];

                if ($userId !== null && $userId > 0) {
                    $sql .= ' AND sp.user_id = ?';
                    $params[] = $userId;
                }
                if ($branchId !== null && $branchId > 0) {
                    $sql .= ' AND sp.branch_id = ?';
                    $params[] = $branchId;
                }

                $sql .= ' ORDER BY sp.created_at DESC, sp.id DESC LIMIT '.$limit;

                $rows = DB::select($sql, $params);

                return $this->posSuccess([
                    'data' => array_map(
                        fn ($row) => PosHelpers::staffPaymentRowToArray((array) $row),
                        $rows,
                    ),
                ]);
            }

            if (! $request->isMethod('post')) {
                return $this->posError('Method not allowed', 405);
            }

            $body = $request->all();
            $actorUserId = PosHelpers::currentActorId($request, $body);
            $actor = PosHelpers::requireAdminActor($actorUserId);

            $userId = (int) ($body['user_id'] ?? 0);
            $amount = round((float) ($body['amount'] ?? 0), 2);
            $paymentType = strtolower(trim((string) ($body['payment_type'] ?? 'salary')));
            $branchId = PosHelpers::optionalInt($body['branch_id'] ?? null);
            $periodStart = trim((string) ($body['period_start'] ?? ''));
            $periodEnd = trim((string) ($body['period_end'] ?? ''));
            $notes = trim((string) ($body['notes'] ?? ''));

            if ($userId <= 0 || $amount <= 0) {
                return $this->posError('Staff user and amount are required', 400);
            }

            if (! in_array($paymentType, ['salary', 'commission', 'bonus', 'allowance'], true)) {
                return $this->posError('Invalid payment type', 400);
            }

            $staff = DB::selectOne('SELECT id, full_name FROM users WHERE id = ? LIMIT 1', [$userId]);
            if (! $staff) {
                return $this->posError('Staff member not found', 404);
            }

            DB::insert(
                'INSERT INTO staff_payments
                    (user_id, branch_id, amount, payment_type, period_start, period_end, notes, paid_by_user_id, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())',
                [
                    $userId,
                    $branchId,
                    $amount,
                    $paymentType,
                    $periodStart !== '' ? $periodStart : null,
                    $periodEnd !== '' ? $periodEnd : null,
                    $notes !== '' ? $notes : null,
                    (int) $actor['id'],
                ],
            );

            $paymentId = (int) DB::getPdo()->lastInsertId();

            PosHelpers::insertAuditLog(
                (int) $actor['id'],
                'create',
                'staff_payments',
                'staff_payment',
                $paymentId,
                'Staff payment recorded',
                ['user_id' => $userId, 'amount' => $amount, 'payment_type' => $paymentType],
            );

            $row = DB::selectOne(
                'SELECT sp.*, u.full_name AS staff_name, b.name AS branch_name,
                        payer.full_name AS paid_by_name
                 FROM staff_payments sp
                 INNER JOIN users u ON u.id = sp.user_id
                 LEFT JOIN branches b ON b.id = sp.branch_id
                 LEFT JOIN users payer ON payer.id = sp.paid_by_user_id
                 WHERE sp.id = ? LIMIT 1',
                [$paymentId],
            );

            return $this->posSuccess([
                'message' => 'Staff payment recorded',
                'data' => PosHelpers::staffPaymentRowToArray((array) $row),
            ], 201);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
