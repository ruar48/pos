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

                    // Merge repeated order_item_ids first - each line used to be
                    // checked against the same starting refunded_quantity, so
                    // sending one item twice refunded (and restocked) more than
                    // was ever sold.
                    $requested = [];
                    foreach ($itemsInput as $line) {
                        $orderItemId = (int) ($line['order_item_id'] ?? 0);
                        $qty = (float) ($line['quantity'] ?? 0);

                        if ($orderItemId <= 0 || $qty <= 0) {
                            continue;
                        }

                        if (! isset($itemsById[$orderItemId])) {
                            throw new \RuntimeException("Invalid order_item_id: $orderItemId");
                        }

                        $requested[$orderItemId] = round(($requested[$orderItemId] ?? 0) + $qty, 3);
                    }

                    foreach ($requested as $orderItemId => $qty) {
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

                // order_items.total is net of the line's own item discount, but
                // manual/coupon/loyalty discounts are only stored at the order
                // level. Without prorating them back into each line, refunding
                // items from a discounted order would overpay the customer by
                // the discount and leave the cash drawer short by that much.
                $lineTotalsSum = 0.0;
                foreach ($orderItems as $row) {
                    $lineTotalsSum += (float) $row->total;
                }
                $discountRatio = PosHelpers::refundMerchandiseRatio($order, $lineTotalsSum);

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

                // Never pay back more than is still owed on the order, however
                // the lines add up - scale the lines down to the balance.
                $balanceOwed = max(0.0, round($orderTotal - $priorRefunded, 2));
                if ($totalRefundAmount > $balanceOwed && count($processedLines) > 0) {
                    $scale = $totalRefundAmount > 0 ? $balanceOwed / $totalRefundAmount : 0.0;
                    $allocated = 0.0;
                    foreach ($processedLines as $i => $line) {
                        $processedLines[$i]['amount'] = round($line['amount'] * $scale, 2);
                        $allocated += $processedLines[$i]['amount'];
                    }
                    $last = count($processedLines) - 1;
                    $processedLines[$last]['amount'] = round(
                        $processedLines[$last]['amount'] + ($balanceOwed - $allocated),
                        2,
                    );
                    $totalRefundAmount = $balanceOwed;
                }

                // A line discounted to 0 still has to go back into stock -
                // returning it refunds nothing, which is not an error.
                $returnsGoods = count($processedLines) > 0;
                if ($totalRefundAmount < 0 || ($totalRefundAmount == 0 && ! $returnsGoods)) {
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
                // "Refunded" only once every unit is back - going by money
                // alone locked orders whose remaining lines were free (or whose
                // total was 0), so those goods could never be returned.
                $newStatus = $remainingQty <= 0.0001 ? 'refunded' : 'partial_refund';

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

                // Take back points earned on the refunded share of the sale
                // and give back points redeemed on it.
                $loyalty = PosHelpers::reverseLoyaltyForRefund($orderId, $actorUserId);

                return [
                    'refund_id' => $refundId,
                    'refund_amount' => $totalRefundAmount,
                    'order_status' => $newStatus,
                    'refunded_amount' => $newRefundedAmount,
                    'items' => $processedLines,
                    'stock_restored' => $stockRestored,
                    'units_restored' => $unitsRestored,
                    'loyalty' => $loyalty,
                    'action' => $action,
                    // The amount differs from the line price shown on the
                    // tablet (order discounts are prorated, VAT added), so
                    // say it outright - every app version shows this message.
                    'message' => "$actionLabel processed. Give back ₱".number_format($totalRefundAmount, 2)
                        .' to the customer.'
                        .($unitsRestored > 0 ? " {$unitsRestored} unit(s) returned to inventory." : ''),
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
