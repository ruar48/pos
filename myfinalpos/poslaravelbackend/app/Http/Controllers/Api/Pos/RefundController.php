<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\CashDrawerService;
use App\Support\BusinessDay;
use App\Support\CatalogStockRevision;
use App\Support\CashDrawerRevision;
use App\Support\PosApiLogger;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class RefundController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        if ($request->isMethod('OPTIONS')) {
            return $this->posSuccess();
        }

        if (! $request->isMethod('post')) {
            return $this->posError('Method not allowed', 405);
        }

        if (! Schema::hasTable('refunds') || ! Schema::hasTable('refund_items')) {
            return $this->posError(
                'Refund tables are missing. Run php artisan migrate in poslaravelbackend.',
                503,
            );
        }

        $body = $request->all();
        $orderId = (int) ($body['order_id'] ?? 0);
        $reason = trim((string) ($body['reason'] ?? ''));
        $refundType = strtolower(trim((string) ($body['refund_type'] ?? 'items')));
        $action = strtolower(trim((string) ($body['action'] ?? 'refund')));
        $itemsInput = $body['items'] ?? [];
        $actorUserId = PosHelpers::currentActorId($request, $body);

        if ($orderId <= 0) {
            return $this->posError('order_id is required', 400);
        }

        if ($reason === '') {
            return $this->posError('reason is required', 400);
        }

        if (! in_array($refundType, ['all', 'items'], true)) {
            return $this->posError('refund_type must be all or items', 400);
        }

        if (! in_array($action, ['refund', 'return'], true)) {
            return $this->posError('action must be refund or return', 400);
        }

        if (PosHelpers::isRefundPinRequired()) {
            $refundPin = trim((string) ($body['refund_pin'] ?? ''));
            if (! PosHelpers::verifyRefundPin($refundPin)) {
                return $this->posError('Invalid or missing refund PIN', 403);
            }
        }

        PosApiLogger::info('refunds.create.start', [
            'order_id' => $orderId,
            'refund_type' => $refundType,
        ]);

        try {
            $result = DB::transaction(function () use (
                $orderId,
                $reason,
                $refundType,
                $action,
                $itemsInput,
                $actorUserId,
            ) {
                $order = DB::selectOne(
                    'SELECT * FROM orders WHERE id = ? LIMIT 1 FOR UPDATE',
                    [$orderId],
                );

                if (! $order) {
                    throw new \RuntimeException('Order not found');
                }

                if (strtolower((string) $order->status) === 'refunded') {
                    throw new \RuntimeException('Order is already fully refunded');
                }

                $hasVarietyCol = PosHelpers::columnExists('order_items', 'variety_id');
                $hasVarietyNameCol = PosHelpers::columnExists('order_items', 'variety_name');
                $varietyCol = $hasVarietyCol ? 'variety_id,' : '';
                $varietyNameCol = $hasVarietyNameCol ? 'variety_name,' : '';

                $orderItems = DB::select(
                    "SELECT id, order_id, product_id, {$varietyCol}{$varietyNameCol} product_name, quantity, price, total, refunded_quantity
                     FROM order_items
                     WHERE order_id = ?
                     FOR UPDATE",
                    [$orderId],
                );

                if (count($orderItems) === 0) {
                    throw new \RuntimeException('No order items found');
                }

                $itemsById = [];
                foreach ($orderItems as $row) {
                    $itemsById[(int) $row->id] = $row;
                }

                $refundLines = [];

                if ($refundType === 'all') {
                    foreach ($orderItems as $row) {
                        $remaining = (float) $row->quantity - (float) $row->refunded_quantity;
                        if ($remaining > 0) {
                            $refundLines[] = [
                                'order_item_id' => (int) $row->id,
                                'quantity' => $remaining,
                            ];
                        }
                    }
                } else {
                    if (! is_array($itemsInput) || count($itemsInput) === 0) {
                        throw new \RuntimeException('items array is required for refund by items');
                    }

                    foreach ($itemsInput as $line) {
                        $orderItemId = (int) ($line['order_item_id'] ?? 0);
                        $qty = (float) ($line['quantity'] ?? 0);

                        if ($orderItemId <= 0 || $qty <= 0) {
                            continue;
                        }

                        if (! isset($itemsById[$orderItemId])) {
                            throw new \RuntimeException("Invalid order_item_id: $orderItemId");
                        }

                        $refundLines[] = [
                            'order_item_id' => $orderItemId,
                            'quantity' => $qty,
                        ];
                    }
                }

                $priorRefunded = round((float) ($order->refunded_amount ?? 0), 2);
                $orderTotal = round((float) $order->total_amount, 2);
                $totalRefundAmount = 0.0;
                $processedLines = [];

                // order_items.total is the pre-discount line amount (price x qty) -
                // any manual/coupon/loyalty discount is only ever stored at the
                // order level. Without prorating it back into each line, refunding
                // items from a discounted order would refund the pre-discount
                // amount, overpaying the customer by the discount and leaving the
                // cash drawer short by exactly that much.
                $orderSubtotal = round((float) ($order->subtotal ?? 0), 2);
                $totalOrderDiscount = round(
                    (float) ($order->discount_amount ?? 0)
                    + (float) ($order->coupon_discount ?? 0)
                    + (float) ($order->loyalty_discount ?? 0),
                    2,
                );
                $discountRatio = $orderSubtotal > 0
                    ? max(0.0, min(1.0, ($orderSubtotal - $totalOrderDiscount) / $orderSubtotal))
                    : 1.0;

                if (count($refundLines) === 0) {
                    $balance = round($orderTotal - $priorRefunded, 2);
                    if (! $this->allItemsFullyRefunded($orderItems) || $balance <= 0) {
                        throw new \RuntimeException('Nothing to refund');
                    }
                    $totalRefundAmount = $balance;
                } else {
                    foreach ($refundLines as $line) {
                        $orderItemId = $line['order_item_id'];
                        $qtyToRefund = $line['quantity'];
                        $row = $itemsById[$orderItemId];

                        $orderedQty = (float) $row->quantity;
                        $alreadyRefunded = (float) $row->refunded_quantity;
                        $remaining = $orderedQty - $alreadyRefunded;

                        if ($qtyToRefund > $remaining) {
                            throw new \RuntimeException(
                                "Refund quantity exceeds remaining for item #$orderItemId",
                            );
                        }

                        $lineTotal = (float) $row->total;
                        $unitMerchandise = $orderedQty > 0
                            ? ($lineTotal / $orderedQty)
                            : (float) $row->price;
                        $merchandiseAmount = round($unitMerchandise * $qtyToRefund * $discountRatio, 2);
                        $amount = PosHelpers::refundAmountIncludingVat($order, $merchandiseAmount);

                        $totalRefundAmount += $amount;

                        $processedLines[] = [
                            'order_item_id' => $orderItemId,
                            'quantity' => $qtyToRefund,
                            'amount' => $amount,
                        ];
                    }

                    $totalRefundAmount = round($totalRefundAmount, 2);

                    if ($this->allItemsFullyRefundedAfter($orderItems, $refundLines)) {
                        // Once every item is refunded, the order balance owed is
                        // known exactly - clamp to it either direction to absorb
                        // rounding drift, instead of only ever correcting upward
                        // (which silently let over-refunds slip through).
                        $fullRefund = round($orderTotal - $priorRefunded, 2);
                        $remainder = round($fullRefund - $totalRefundAmount, 2);
                        if ($remainder !== 0.0 && count($processedLines) > 0) {
                            $totalRefundAmount = $fullRefund;
                            $last = count($processedLines) - 1;
                            $processedLines[$last]['amount'] = round(
                                $processedLines[$last]['amount'] + $remainder,
                                2,
                            );
                        } else {
                            $totalRefundAmount = $fullRefund;
                        }
                    }
                }

                if ($totalRefundAmount <= 0) {
                    throw new \RuntimeException('Refund amount must be greater than zero');
                }

                DB::insert(
                    'INSERT INTO refunds (order_id, refund_type, amount, reason)
                     VALUES (?, ?, ?, ?)',
                    [$orderId, $refundType, $totalRefundAmount, $reason],
                );

                $refundId = (int) DB::getPdo()->lastInsertId();
                $stockRestored = [];

                foreach ($processedLines as $line) {
                    DB::insert(
                        'INSERT INTO refund_items (refund_id, order_item_id, quantity, amount)
                         VALUES (?, ?, ?, ?)',
                        [
                            $refundId,
                            $line['order_item_id'],
                            $line['quantity'],
                            $line['amount'],
                        ],
                    );

                    DB::update(
                        'UPDATE order_items
                         SET refunded_quantity = refunded_quantity + ?
                         WHERE id = ?',
                        [$line['quantity'], $line['order_item_id']],
                    );

                    $refundRow = $itemsById[$line['order_item_id']];
                    $stockRestored[] = PosHelpers::restoreRefundedStock(
                        $refundRow,
                        (float) $line['quantity'],
                        $refundId,
                        $actorUserId,
                        ucfirst($action),
                    );
                }

                $remainingRow = DB::selectOne(
                    'SELECT SUM(quantity - refunded_quantity) AS remaining_qty
                     FROM order_items
                     WHERE order_id = ?',
                    [$orderId],
                );
                $remainingQty = (float) ($remainingRow->remaining_qty ?? 0);

                $newRefundedAmount = round($priorRefunded + $totalRefundAmount, 2);
                $newStatus = $newRefundedAmount >= $orderTotal - 0.01 || $remainingQty <= 0
                    ? 'refunded'
                    : 'partial_refund';

                DB::update(
                    'UPDATE orders
                     SET status = ?, refunded_amount = ?
                     WHERE id = ?',
                    [$newStatus, $newRefundedAmount, $orderId],
                );

                $actionLabel = $action === 'return' ? 'Return' : 'Refund';

                PosHelpers::insertAuditLog(
                    $actorUserId,
                    $action,
                    'sales',
                    $action,
                    $refundId,
                    "$actionLabel processed successfully",
                    [
                        'order_id' => $orderId,
                        'refund_type' => $refundType,
                        'refund_amount' => $totalRefundAmount,
                        'reason' => $reason,
                        'order_status' => $newStatus,
                        'action' => $action,
                    ],
                );

                PosHelpers::insertUserTransaction(
                    $actorUserId,
                    "{$action}_save",
                    $action === 'return' ? 'returns' : 'refunds',
                    $refundId,
                    $totalRefundAmount,
                    "$actionLabel saved",
                    [
                        'order_id' => $orderId,
                        'refund_type' => $refundType,
                        'action' => $action,
                    ],
                );

                $unitsRestored = array_sum(array_map(
                    static fn (array $row) => (float) ($row['quantity'] ?? 0),
                    $stockRestored,
                ));

                return [
                    'refund_id' => $refundId,
                    'refund_amount' => $totalRefundAmount,
                    'order_status' => $newStatus,
                    'refunded_amount' => $newRefundedAmount,
                    'items' => $processedLines,
                    'stock_restored' => $stockRestored,
                    'units_restored' => $unitsRestored,
                    'action' => $action,
                    'message' => $unitsRestored > 0
                        ? "$actionLabel processed successfully. {$unitsRestored} unit(s) returned to inventory."
                        : "$actionLabel processed successfully",
                ];
            });

            PosApiLogger::info('refunds.create.success', [
                'order_id' => $orderId,
                'refund_id' => $result['refund_id'],
            ]);

            if (($result['units_restored'] ?? 0) > 0) {
                CatalogStockRevision::bump();
            }

            $orderRow = DB::table('orders')->where('id', $orderId)->first();
            if ($orderRow !== null) {
                $orderAt = Carbon::parse((string) $orderRow->created_at);
                $businessDate = BusinessDay::dateForMoment($orderAt);
                CashDrawerRevision::bump($businessDate);
                [$startDt, $endDt] = BusinessDay::rangeFor($businessDate);
                app(CashDrawerService::class)->forgetSalesCacheForRange($startDt, $endDt);
            }

            return $this->posSuccess($result);
        } catch (\RuntimeException $e) {
            PosApiLogger::warning('refunds.create.validation', ['message' => $e->getMessage()]);

            $status = str_contains($e->getMessage(), 'not found') ? 404 : 400;

            return $this->posError($e->getMessage(), $status);
        } catch (\Throwable $e) {
            PosApiLogger::error('refunds.create.failed', ['message' => $e->getMessage()]);

            return $this->posServerError($e);
        }
    }

    /**
     * @param  array<int, object>  $orderItems
     */
    private function allItemsFullyRefunded(array $orderItems): bool
    {
        foreach ($orderItems as $row) {
            if ((float) $row->quantity - (float) $row->refunded_quantity > 0) {
                return false;
            }
        }

        return count($orderItems) > 0;
    }

    /**
     * @param  array<int, object>  $orderItems
     * @param  array<int, array{order_item_id: int, quantity: float}>  $refundLines
     */
    private function allItemsFullyRefundedAfter(array $orderItems, array $refundLines): bool
    {
        $refundQtyByItem = [];
        foreach ($refundLines as $line) {
            $id = (int) $line['order_item_id'];
            $refundQtyByItem[$id] = ($refundQtyByItem[$id] ?? 0) + (float) $line['quantity'];
        }

        foreach ($orderItems as $row) {
            $id = (int) $row->id;
            $remainingAfter = (float) $row->quantity
                - (float) $row->refunded_quantity
                - ($refundQtyByItem[$id] ?? 0);
            if ($remainingAfter > 0) {
                return false;
            }
        }

        return true;
    }
}
