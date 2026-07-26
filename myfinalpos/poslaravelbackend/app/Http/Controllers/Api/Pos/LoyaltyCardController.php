<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class LoyaltyCardController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        try {
            if (! PosHelpers::tableExists('loyalty_cards')) {
                return $this->posSuccess(['data' => []]);
            }

            if ($request->isMethod('get')) {
                $lookupUid = trim((string) $request->query('nfc_uid', ''));
                if ($lookupUid !== '') {
                    if (! PosHelpers::columnExists('loyalty_cards', 'nfc_uid')) {
                        return $this->posError('NFC lookup is not enabled. Run database migrations.', 503);
                    }

                    $match = PosHelpers::findCustomerByNfcUid($lookupUid);
                    if ($match === null) {
                        return $this->posError('No customer is linked to this RFID card', 404);
                    }

                    return $this->posSuccess(['data' => $match]);
                }

                $nfcColumn = PosHelpers::columnExists('loyalty_cards', 'nfc_uid')
                    ? 'lc.nfc_uid,'
                    : 'NULL AS nfc_uid,';

                $rows = DB::select(
                    'SELECT
                        lc.customer_id,
                        c.customer_name,
                        lc.card_number,
                        '.$nfcColumn.'
                        lc.points,
                        lc.tier,
                        lc.status,
                        lc.created_at,
                        lc.updated_at
                     FROM loyalty_cards lc
                     INNER JOIN customers c ON c.id = lc.customer_id
                     WHERE '.PosHelpers::walkInCustomerSqlExclusion('c.customer_name').'
                     ORDER BY lc.updated_at DESC, lc.id DESC',
                );

                return $this->posSuccess([
                    'data' => array_map(fn ($row) => (array) $row, $rows),
                ]);
            }

            if (! $request->isMethod('post')) {
                return $this->posError('Method not allowed', 405);
            }

            $body = $request->all();
            $actionRaw = isset($body['action']) ? (string) $body['action'] : 'issue';
            $action = strtolower(trim($actionRaw));
            $customerId = (int) ($body['customer_id'] ?? 0);
            $actorUserId = PosHelpers::currentActorId($request, $body);

            if ($action === 'link_nfc') {
                if ($customerId <= 0) {
                    return $this->posError('customer_id is required', 400);
                }

                try {
                    $card = PosHelpers::linkLoyaltyCardNfc(
                        $customerId,
                        (string) ($body['nfc_uid'] ?? ''),
                        $actorUserId,
                    );
                } catch (\InvalidArgumentException $e) {
                    return $this->posError($e->getMessage(), 400);
                } catch (\RuntimeException $e) {
                    return $this->posError($e->getMessage(), 503);
                }

                return $this->posSuccess([
                    'message' => 'RFID card linked successfully',
                    'data' => $card,
                ]);
            }

            if ($customerId <= 0) {
                return $this->posError('customer_id is required', 400);
            }

            $customer = DB::selectOne(
                'SELECT id, customer_name FROM customers WHERE id = ? LIMIT 1',
                [$customerId],
            );

            if (! $customer) {
                return $this->posError('Customer not found', 404);
            }

            $customerName = (string) $customer->customer_name;
            if (PosHelpers::isWalkInCustomerName($customerName)) {
                return $this->posError('Walk-in customers cannot enroll in the loyalty program', 400);
            }

            PosHelpers::ensureLoyaltyCard($customerId, $actorUserId);

            $card = DB::selectOne(
                'SELECT
                    lc.customer_id,
                    c.customer_name,
                    lc.card_number,
                    lc.points,
                    lc.tier,
                    lc.status,
                    lc.created_at,
                    lc.updated_at
                 FROM loyalty_cards lc
                 INNER JOIN customers c ON c.id = lc.customer_id
                 WHERE lc.customer_id = ?
                 LIMIT 1',
                [$customerId],
            );

            PosHelpers::insertAuditLog(
                $actorUserId,
                'create',
                'loyalty',
                'loyalty_card',
                $customerId,
                'Loyalty card opened for customer',
                ['customer_id' => $customerId, 'customer_name' => $customerName],
            );

            return $this->posSuccess([
                'message' => 'Loyalty card opened successfully',
                'data' => (array) $card,
            ], 201);
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
