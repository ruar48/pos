<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CustomerController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        try {
            if ($request->isMethod('get')) {
                $rows = DB::select(
                    'SELECT id, customer_name, table_name, order_type, created_at
                     FROM customers
                     WHERE '.PosHelpers::walkInCustomerSqlExclusion('customer_name').'
                     ORDER BY id DESC',
                );

                return $this->posSuccess([
                    'data' => array_map(fn ($row) => (array) $row, $rows),
                ]);
            }

            if (! $request->isMethod('post')) {
                return $this->posError('Method not allowed', 405);
            }

            $body = $request->all();
            $customerName = trim((string) ($body['customer_name'] ?? ''));
            $tableName = trim((string) ($body['table_name'] ?? ''));
            $orderType = trim((string) ($body['order_type'] ?? 'Retail'));
            $actorUserId = PosHelpers::currentActorId($request, $body);

            if (PosHelpers::isWalkInCustomerName($customerName)) {
                return $this->posError(
                    'Walk-in customers are not saved. Leave customer blank at checkout.',
                    400,
                );
            }

            DB::insert(
                'INSERT INTO customers (customer_name, table_name, order_type) VALUES (?, ?, ?)',
                [$customerName, $tableName, $orderType],
            );

            $customerId = (int) DB::getPdo()->lastInsertId();
            $createLoyaltyCard = ! empty($body['create_loyalty_card']);

            if ($createLoyaltyCard && ! PosHelpers::isWalkInCustomerName($customerName)) {
                PosHelpers::ensureLoyaltyCard($customerId, $actorUserId);
            }

            PosHelpers::insertAuditLog(
                $actorUserId,
                'create',
                'customers',
                'customer',
                $customerId,
                'Customer saved successfully',
                [
                    'customer_name' => $customerName,
                    'table_name' => $tableName,
                    'order_type' => $orderType,
                ],
            );

            PosHelpers::insertUserTransaction(
                $actorUserId,
                'customer_save',
                'customers',
                $customerId,
                0.0,
                'Customer record saved',
                ['customer_name' => $customerName],
            );

            return $this->posSuccess([
                'id' => $customerId,
                'message' => 'Customer saved successfully',
                'data' => [
                    'id' => $customerId,
                    'customer_name' => $customerName,
                    'table_name' => $tableName,
                    'order_type' => $orderType,
                ],
            ], 201);
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
