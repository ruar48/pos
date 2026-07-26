<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CouponController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        try {
            if (! PosHelpers::tableExists('coupons')) {
                if ($request->isMethod('get')) {
                    return $this->posSuccess([
                        'data' => [],
                        'message' => 'Coupons table not found. Run backend/sql/coupons.sql',
                    ]);
                }

                return $this->posError('Coupons table not found. Run backend/sql/coupons.sql', 503);
            }

            if ($request->isMethod('get')) {
                $includeInactive = ! empty($request->query('include_inactive'));
                $sql = 'SELECT * FROM coupons';
                if (! $includeInactive) {
                    $sql .= ' WHERE status = 1 AND start_date <= CURDATE() AND end_date >= CURDATE()';
                }
                $sql .= ' ORDER BY status DESC, end_date DESC, code ASC';

                $rows = DB::select($sql);

                return $this->posSuccess([
                    'data' => array_map(
                        fn ($row) => PosHelpers::couponRowToArray((array) $row),
                        $rows,
                    ),
                ]);
            }

            if (! $request->isMethod('post')) {
                return $this->posError('Method not allowed', 405);
            }

            $body = $request->all();
            $action = strtolower(trim((string) ($body['action'] ?? 'create')));
            $actorUserId = PosHelpers::currentActorId($request, $body);

            if ($action === 'validate') {
                $code = PosHelpers::normalizeCouponCode((string) ($body['code'] ?? ''));
                $subtotal = round((float) ($body['subtotal'] ?? 0), 2);
                if ($code === '') {
                    return $this->posError('Coupon code is required', 400);
                }

                $coupon = PosHelpers::findCouponByCode($code);
                if (! $coupon) {
                    return $this->posError('Invalid coupon code', 404);
                }

                $validationError = PosHelpers::isCouponCurrentlyValid($coupon, $subtotal);
                if ($validationError !== null) {
                    return $this->posError($validationError, 400);
                }

                return $this->posSuccess([
                    'message' => 'Coupon is valid',
                    'data' => PosHelpers::couponRowToArray($coupon),
                    'discount_amount' => PosHelpers::calculateCouponDiscount($coupon, $subtotal),
                ]);
            }

            if ($action === 'toggle') {
                $couponId = (int) ($body['id'] ?? 0);
                if ($couponId <= 0) {
                    return $this->posError('Coupon id is required', 400);
                }

                $existing = DB::selectOne('SELECT * FROM coupons WHERE id = ? LIMIT 1', [$couponId]);
                if (! $existing) {
                    return $this->posError('Coupon not found', 404);
                }

                $existingArr = (array) $existing;
                $newStatus = ((int) $existingArr['status'] === 1) ? 0 : 1;
                DB::update('UPDATE coupons SET status = ? WHERE id = ?', [$newStatus, $couponId]);

                PosHelpers::insertAuditLog(
                    $actorUserId,
                    $newStatus === 1 ? 'activate' : 'deactivate',
                    'promotions',
                    'coupon',
                    $couponId,
                    'Coupon status updated',
                    ['code' => $existingArr['code'], 'status' => $newStatus],
                );

                $updated = DB::selectOne('SELECT * FROM coupons WHERE id = ? LIMIT 1', [$couponId]);

                return $this->posSuccess([
                    'message' => $newStatus === 1 ? 'Coupon activated' : 'Coupon deactivated',
                    'data' => PosHelpers::couponRowToArray((array) $updated),
                ]);
            }

            if ($action === 'update') {
                $couponId = (int) ($body['id'] ?? 0);
                if ($couponId <= 0) {
                    return $this->posError('Coupon id is required', 400);
                }

                $existing = DB::selectOne('SELECT * FROM coupons WHERE id = ? LIMIT 1', [$couponId]);
                if (! $existing) {
                    return $this->posError('Coupon not found', 404);
                }
                $existing = (array) $existing;

                $code = PosHelpers::normalizeCouponCode((string) ($body['code'] ?? $existing['code']));
                $description = trim((string) ($body['description'] ?? ($existing['description'] ?? '')));
                $discountType = strtolower(trim((string) ($body['discount_type'] ?? $existing['discount_type'])));
                $discountValue = round((float) ($body['discount_value'] ?? $existing['discount_value']), 2);
                $minOrderAmount = round((float) ($body['min_order_amount'] ?? $existing['min_order_amount']), 2);
                $startDate = trim((string) ($body['start_date'] ?? $existing['start_date']));
                $endDate = trim((string) ($body['end_date'] ?? $existing['end_date']));
                $maxUses = array_key_exists('max_uses', $body)
                    ? PosHelpers::optionalInt($body['max_uses'])
                    : ($existing['max_uses'] !== null ? (int) $existing['max_uses'] : null);

                if ($code === '') {
                    return $this->posError('Coupon code is required', 400);
                }
                if (! in_array($discountType, ['percentage', 'fixed'], true)) {
                    return $this->posError('discount_type must be percentage or fixed', 400);
                }
                if ($discountValue <= 0) {
                    return $this->posError('discount_value must be greater than zero', 400);
                }
                if ($discountType === 'percentage' && $discountValue > 100) {
                    return $this->posError('Percentage discount cannot exceed 100', 400);
                }

                $dateError = PosHelpers::validateCouponDates($startDate, $endDate);
                if ($dateError !== null) {
                    return $this->posError($dateError, 400);
                }

                $duplicate = DB::selectOne(
                    'SELECT id FROM coupons WHERE UPPER(code) = UPPER(?) AND id <> ? LIMIT 1',
                    [$code, $couponId],
                );
                if ($duplicate) {
                    return $this->posError('Coupon code already exists', 409);
                }

                DB::update(
                    'UPDATE coupons
                     SET code = ?, description = ?, discount_type = ?, discount_value = ?,
                         min_order_amount = ?, start_date = ?, end_date = ?, max_uses = ?
                     WHERE id = ?',
                    [
                        $code,
                        $description === '' ? null : $description,
                        $discountType,
                        $discountValue,
                        max(0, $minOrderAmount),
                        $startDate,
                        $endDate,
                        $maxUses,
                        $couponId,
                    ],
                );

                PosHelpers::insertAuditLog(
                    $actorUserId,
                    'update',
                    'promotions',
                    'coupon',
                    $couponId,
                    'Coupon updated',
                    ['code' => $code],
                );

                $updated = DB::selectOne('SELECT * FROM coupons WHERE id = ? LIMIT 1', [$couponId]);

                return $this->posSuccess([
                    'message' => 'Coupon updated successfully',
                    'data' => PosHelpers::couponRowToArray((array) $updated),
                ]);
            }

            $code = PosHelpers::normalizeCouponCode((string) ($body['code'] ?? ''));
            $description = trim((string) ($body['description'] ?? ''));
            $discountType = strtolower(trim((string) ($body['discount_type'] ?? 'fixed')));
            $discountValue = round((float) ($body['discount_value'] ?? 0), 2);
            $minOrderAmount = round((float) ($body['min_order_amount'] ?? 0), 2);
            $startDate = trim((string) ($body['start_date'] ?? now()->format('Y-m-d')));
            $endDate = trim((string) ($body['end_date'] ?? now()->addYear()->format('Y-m-d')));
            $maxUses = PosHelpers::optionalInt($body['max_uses'] ?? null);

            if ($code === '') {
                return $this->posError('Coupon code is required', 400);
            }
            if (! in_array($discountType, ['percentage', 'fixed'], true)) {
                return $this->posError('discount_type must be percentage or fixed', 400);
            }
            if ($discountValue <= 0) {
                return $this->posError('discount_value must be greater than zero', 400);
            }
            if ($discountType === 'percentage' && $discountValue > 100) {
                return $this->posError('Percentage discount cannot exceed 100', 400);
            }

            $dateError = PosHelpers::validateCouponDates($startDate, $endDate);
            if ($dateError !== null) {
                return $this->posError($dateError, 400);
            }

            $duplicate = DB::selectOne(
                'SELECT id FROM coupons WHERE UPPER(code) = UPPER(?) LIMIT 1',
                [$code],
            );
            if ($duplicate) {
                return $this->posError('Coupon code already exists', 409);
            }

            DB::insert(
                'INSERT INTO coupons
                    (code, description, discount_type, discount_value, min_order_amount, start_date, end_date, max_uses, status)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)',
                [
                    $code,
                    $description === '' ? null : $description,
                    $discountType,
                    $discountValue,
                    max(0, $minOrderAmount),
                    $startDate,
                    $endDate,
                    $maxUses,
                ],
            );

            $couponId = (int) DB::getPdo()->lastInsertId();

            PosHelpers::insertAuditLog(
                $actorUserId,
                'create',
                'promotions',
                'coupon',
                $couponId,
                'Coupon created',
                ['code' => $code],
            );

            $created = DB::selectOne('SELECT * FROM coupons WHERE id = ? LIMIT 1', [$couponId]);

            return $this->posSuccess([
                'message' => 'Coupon created successfully',
                'data' => PosHelpers::couponRowToArray((array) $created),
            ], 201);
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
