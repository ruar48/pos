<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Services\Pos\CashDrawerService;
use App\Services\Pos\LowStockNotificationService;
use App\Support\BusinessDay;
use App\Support\CatalogStockRevision;
use App\Support\CashDrawerRevision;
use App\Support\PosApiLogger;
use App\Support\PosApiResponse;
use App\Support\PosDateTime;
use App\Support\PosHelpers;
use App\Support\StockLedger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class OrderController extends Controller
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

        if (! Schema::hasTable('orders') || ! Schema::hasTable('order_items')) {
            return $this->posError(
                'Order tables are missing. Run php artisan migrate in poslaravelbackend.',
                503,
            );
        }

        PosApiLogger::info('orders.create.start', PosApiLogger::requestContext($request));

        $body = $request->all();
        $customerId = (int) ($body['customer_id'] ?? 0);
        $isWalkIn = ! empty($body['is_walk_in']) || $customerId <= 0;
        $items = $body['items'] ?? [];
        $subtotal = round((float) ($body['subtotal'] ?? 0), 2);
        $vat = round((float) ($body['vat'] ?? 0), 2);
        $totalAmount = round((float) ($body['total_amount'] ?? 0), 2);
        $clientChange = round((float) ($body['client_change'] ?? 0), 2);
        $paymentMethod = trim((string) ($body['payment_method'] ?? 'Cash'));
        $reference = trim((string) ($body['reference'] ?? ''));
        $receiptNoteRaw = trim((string) ($body['receipt_note'] ?? ''));
        $receiptNote = $receiptNoteRaw !== '' ? mb_substr($receiptNoteRaw, 0, 240) : null;
        $payments = $body['payments'] ?? null;
        $splitPayments = [];
        $actorUserId = PosHelpers::currentActorId($request, $body);
        $discountAmount = round((float) ($body['discount_amount'] ?? 0), 2);
        $couponDiscount = round((float) ($body['coupon_discount'] ?? 0), 2);
        $couponCode = PosHelpers::normalizeCouponCode((string) ($body['coupon_code'] ?? ''));
        $loyaltyDiscount = round((float) ($body['loyalty_discount'] ?? 0), 2);
        $loyaltyPointsRedeemed = (int) ($body['loyalty_points_redeemed'] ?? 0);
        $branchId = max(1, (int) ($body['branch_id'] ?? 1));
        $createdAt = $this->resolveOrderCreatedAt($body);

        if (! is_array($items) || count($items) === 0) {
            return $this->posError('At least one item is required', 400);
        }

        if (is_array($payments) && count($payments) >= 2) {
            $paymentTotal = 0.0;
            $methods = [];

            foreach ($payments as $payment) {
                if (! is_array($payment)) {
                    return $this->posError('Invalid split payment payload', 400);
                }

                $method = trim((string) ($payment['payment_method'] ?? ''));
                $amount = round((float) ($payment['amount'] ?? 0), 2);
                $paymentReference = trim((string) ($payment['reference'] ?? ''));

                if ($method === '' || $amount <= 0) {
                    return $this->posError('Each split payment needs a method and amount', 400);
                }

                if (strcasecmp($method, 'Cash') !== 0 && $paymentReference === '') {
                    return $this->posError("Reference is required for {$method} payments", 400);
                }

                $paymentTotal += $amount;
                $methods[] = $method;
                $splitPayments[] = [
                    'payment_method' => $method,
                    'amount' => $amount,
                    'reference' => $paymentReference !== '' ? $paymentReference : null,
                ];
            }

            if (abs($paymentTotal - $totalAmount) > 0.01) {
                return $this->posError('Split payment amounts must equal the order total', 400);
            }

            $uniqueMethods = array_values(array_unique($methods));
            $paymentMethod = count($uniqueMethods) === 1
                ? (string) $uniqueMethods[0]
                : 'Split ('.implode(' + ', $uniqueMethods).')';
            $reference = '';
            $clientChange = 0.0;
        } elseif (is_array($payments) && count($payments) > 0) {
            return $this->posError('Split payment requires at least two payments', 400);
        }

        try {
            $checkout = DB::transaction(function () use (
                $customerId,
                $isWalkIn,
                $items,
                $subtotal,
                $vat,
                $totalAmount,
                $clientChange,
                $paymentMethod,
                $reference,
                $receiptNote,
                $actorUserId,
                $discountAmount,
                $couponDiscount,
                $couponCode,
                $loyaltyDiscount,
                $loyaltyPointsRedeemed,
                $branchId,
                $splitPayments,
                $createdAt,
            ) {
                if ($isWalkIn) {
                    if ($loyaltyPointsRedeemed > 0 || $loyaltyDiscount > 0) {
                        throw new \RuntimeException('Walk-in customers cannot use loyalty points');
                    }
                } else {
                    $customerRow = DB::selectOne(
                        'SELECT id, customer_name FROM customers WHERE id = ? LIMIT 1',
                        [$customerId],
                    );

                    if (! $customerRow) {
                        throw new \RuntimeException('Customer not found');
                    }

                    if (PosHelpers::isWalkInCustomerName((string) ($customerRow->customer_name ?? ''))) {
                        throw new \RuntimeException(
                            'Walk-in customers are not stored. Complete checkout without a customer.',
                        );
                    }
                }

                $validatedItems = [];
                $calculatedSubtotal = 0.0;
                $stockChanges = [];

                $hasVarietyTable = Schema::hasTable('product_varieties');
                $allowNegativeStock = $this->allowNegativeStock();

                foreach ($items as $item) {
                    $productId = (int) ($item['product_id'] ?? 0);
                    $varietyId = (int) ($item['variety_id'] ?? 0);
                    $quantity = (int) ($item['quantity'] ?? 0);

                    if ($productId <= 0 || $quantity <= 0) {
                        throw new \RuntimeException('Invalid order item payload');
                    }

                    $product = DB::selectOne(
                        'SELECT id, name, price, stock, cost_price, option
                         FROM products
                         WHERE id = ?
                         LIMIT 1
                         FOR UPDATE',
                        [$productId],
                    );

                    if (! $product) {
                        throw new \RuntimeException("Product #{$productId} not found");
                    }

                    if ($varietyId > 0 && $hasVarietyTable) {
                        $variety = DB::selectOne(
                            'SELECT id, product_id, name, price, stock, cost_price
                             FROM product_varieties
                             WHERE id = ? AND product_id = ?
                             LIMIT 1
                             FOR UPDATE',
                            [$varietyId, $productId],
                        );

                        if (! $variety) {
                            throw new \RuntimeException("Variety #{$varietyId} not found");
                        }

                        $stock = (int) ($variety->stock ?? 0);
                        if (! $allowNegativeStock && $stock < $quantity) {
                            throw new \RuntimeException(
                                'Insufficient stock for '.$product->name.' - '.$variety->name,
                            );
                        }

                        $price = round((float) $variety->price, 2);
                        $unitCost = round(
                            (float) ($variety->cost_price ?? $product->cost_price ?? 0),
                            2,
                        );
                        $lineTotal = round($price * $quantity, 2);
                        $calculatedSubtotal += $lineTotal;

                        $validatedItems[] = [
                            'product_id' => (int) $product->id,
                            'product_name' => (string) $product->name,
                            'variety_id' => (int) $variety->id,
                            'variety_name' => (string) $variety->name,
                            'quantity' => $quantity,
                            'price' => $price,
                            'unit_cost' => $unitCost,
                            'total' => $lineTotal,
                        ];

                        $productIdKey = (int) $product->id;
                        if (! isset($stockChanges[$productIdKey])) {
                            $stockChanges[$productIdKey] = [
                                'previous' => (int) ($product->stock ?? 0),
                                'sold' => 0,
                            ];
                        }
                        $stockChanges[$productIdKey]['sold'] += $quantity;

                        continue;
                    }

                    $stock = (int) ($product->stock ?? 0);
                    if (! $allowNegativeStock && $stock < $quantity) {
                        throw new \RuntimeException('Insufficient stock for '.$product->name);
                    }

                    $price = round((float) $product->price, 2);
                    $unitCost = round((float) ($product->cost_price ?? 0), 2);
                    $lineTotal = round($price * $quantity, 2);
                    $calculatedSubtotal += $lineTotal;

                    $flatOption = trim((string) ($product->option ?? ''));

                    $validatedItems[] = [
                        'product_id' => (int) $product->id,
                        'product_name' => (string) $product->name,
                        'variety_id' => null,
                        // Products without a separate variety row can still
                        // carry a flat "option" (e.g. "1000 ML", "50 KILO") -
                        // store it in variety_name so receipts/reports show
                        // it exactly like a real variety.
                        'variety_name' => $flatOption === '' ? null : $flatOption,
                        'quantity' => $quantity,
                        'price' => $price,
                        'unit_cost' => $unitCost,
                        'total' => $lineTotal,
                    ];

                    $productIdKey = (int) $product->id;
                    if (! isset($stockChanges[$productIdKey])) {
                        $stockChanges[$productIdKey] = [
                            'previous' => (int) ($product->stock ?? 0),
                            'sold' => 0,
                        ];
                    }
                    $stockChanges[$productIdKey]['sold'] += $quantity;
                }

                $calculatedSubtotal = round($calculatedSubtotal, 2);
                $totalDiscounts = round($discountAmount + $couponDiscount + $loyaltyDiscount, 2);
                $netMerchandise = max(0, round($calculatedSubtotal - $totalDiscounts, 2));
                [$vat, $totalAmount] = PosHelpers::saleVatAndTotal($netMerchandise);
                $subtotal = $netMerchandise;

                if ($couponCode !== '' && $couponDiscount > 0) {
                    if (! PosHelpers::tableExists('coupons')) {
                        throw new \RuntimeException('Coupons are not configured');
                    }

                    $coupon = PosHelpers::findCouponByCode($couponCode);
                    if (! $coupon) {
                        throw new \RuntimeException('Invalid coupon code');
                    }

                    $validationError = PosHelpers::isCouponCurrentlyValid(
                        $coupon,
                        $calculatedSubtotal,
                    );
                    if ($validationError !== null) {
                        throw new \RuntimeException($validationError);
                    }

                    PosHelpers::incrementCouponUsage($couponCode);
                }

                $hasBranchId = PosHelpers::columnExists('orders', 'branch_id');
                $hasCashierUserId = PosHelpers::columnExists('orders', 'cashier_user_id');
                $hasReceiptNote = PosHelpers::columnExists('orders', 'receipt_note');
                $cashierUserId = $actorUserId !== null && $actorUserId > 0 ? $actorUserId : null;

                $orderRow = [
                    'customer_id' => $isWalkIn ? null : $customerId,
                    'subtotal' => $subtotal,
                    'vat' => $vat,
                    'total_amount' => $totalAmount,
                    'client_change' => $clientChange,
                    'payment_method' => $paymentMethod,
                    'reference' => $reference !== '' ? $reference : null,
                    'status' => 'completed',
                    'refunded_amount' => 0,
                    'discount_amount' => $discountAmount,
                    'coupon_discount' => $couponDiscount,
                    'loyalty_discount' => $loyaltyDiscount,
                    'loyalty_points_redeemed' => $loyaltyPointsRedeemed,
                    'created_at' => $createdAt,
                ];

                if ($hasBranchId) {
                    $orderRow['branch_id'] = $branchId;
                }
                if ($hasCashierUserId) {
                    $orderRow['cashier_user_id'] = $cashierUserId;
                }
                if ($hasReceiptNote) {
                    $orderRow['receipt_note'] = $receiptNote;
                }

                $orderId = PosHelpers::insertRow('orders', $orderRow);

                $hasVarietyColumns = PosHelpers::columnExists('order_items', 'variety_id');
                $hasUnitCost = PosHelpers::columnExists('order_items', 'unit_cost');

                foreach ($validatedItems as $item) {
                    $itemRow = [
                        'order_id' => $orderId,
                        'product_id' => $item['product_id'],
                        'product_name' => $item['product_name'],
                        'quantity' => $item['quantity'],
                        'price' => $item['price'],
                        'total' => $item['total'],
                        'refunded_quantity' => 0,
                        'created_at' => $createdAt,
                    ];

                    if ($hasVarietyColumns) {
                        $itemRow['variety_id'] = $item['variety_id'];
                        $itemRow['variety_name'] = $item['variety_name'];
                    }
                    if ($hasUnitCost) {
                        $itemRow['unit_cost'] = $item['unit_cost'];
                    }

                    PosHelpers::insertRow('order_items', $itemRow);

                    if (! empty($item['variety_id'])) {
                        DB::update(
                            'UPDATE product_varieties SET stock = stock - ? WHERE id = ?',
                            [$item['quantity'], $item['variety_id']],
                        );
                    }

                    DB::update(
                        'UPDATE products SET stock = stock - ? WHERE id = ?',
                        [$item['quantity'], $item['product_id']],
                    );

                    // One ledger row per line (counted once at product level).
                    StockLedger::record(
                        productId: (int) $item['product_id'],
                        varietyId: $item['variety_id'] !== null ? (int) $item['variety_id'] : null,
                        type: 'sale',
                        quantityDelta: -1 * (int) $item['quantity'],
                        referenceType: 'order',
                        referenceId: $orderId,
                        note: 'Sale',
                        userId: $actorUserId,
                    );
                }

                if (! $isWalkIn && $customerId > 0 && PosHelpers::isLoyaltyProgramEnabled()) {
                    if ($loyaltyPointsRedeemed > 0) {
                        PosHelpers::deductRedeemedLoyaltyPoints(
                            $customerId,
                            $loyaltyPointsRedeemed,
                            $orderId,
                            $actorUserId,
                        );
                    }

                    PosHelpers::awardLoyaltyPoints(
                        $customerId,
                        $totalAmount,
                        $orderId,
                        $actorUserId,
                    );
                }

                if (count($splitPayments) >= 2 && Schema::hasTable('order_payments')) {
                    foreach ($splitPayments as $payment) {
                        DB::insert(
                            'INSERT INTO order_payments
                                (order_id, payment_method, amount, reference)
                             VALUES (?, ?, ?, ?)',
                            [
                                $orderId,
                                $payment['payment_method'],
                                $payment['amount'],
                                $payment['reference'],
                            ],
                        );
                    }
                }

                PosHelpers::insertAuditLog(
                    $actorUserId,
                    'create',
                    'sales',
                    'order',
                    $orderId,
                    'Order saved successfully',
                    [
                        'customer_id' => $isWalkIn ? null : $customerId,
                        'is_walk_in' => $isWalkIn,
                        'payment_method' => $paymentMethod,
                        'subtotal' => $subtotal,
                        'vat' => $vat,
                        'total_amount' => $totalAmount,
                        'discount_amount' => $discountAmount,
                        'coupon_discount' => $couponDiscount,
                        'loyalty_discount' => $loyaltyDiscount,
                        'loyalty_points_redeemed' => $loyaltyPointsRedeemed,
                    ],
                );

                PosHelpers::insertUserTransaction(
                    $actorUserId,
                    'order_save',
                    'orders',
                    $orderId,
                    $totalAmount,
                    'POS order saved',
                    [
                        'customer_id' => $isWalkIn ? null : $customerId,
                        'is_walk_in' => $isWalkIn,
                        'item_count' => count($validatedItems),
                        'payment_method' => $paymentMethod,
                    ],
                );

                return [
                    'order_id' => $orderId,
                    'stock_changes' => $stockChanges,
                ];
            });

            $orderId = (int) ($checkout['order_id'] ?? 0);
            $notifier = app(LowStockNotificationService::class);
            foreach (($checkout['stock_changes'] ?? []) as $productId => $change) {
                $previousStock = (int) ($change['previous'] ?? 0);
                $sold = (int) ($change['sold'] ?? 0);
                $notifier->afterStockChange((int) $productId, $previousStock, $previousStock - $sold);
            }

            PosApiLogger::info('orders.create.success', ['order_id' => $orderId]);

            CatalogStockRevision::bump();
            CashDrawerRevision::bump();
            app(CashDrawerService::class)->forgetSalesCacheForToday();

            return $this->posSuccess([
                'message' => 'Order saved successfully',
                'order_id' => $orderId,
            ], 201);
        } catch (\RuntimeException $e) {
            PosApiLogger::warning('orders.create.validation', ['message' => $e->getMessage()]);

            $status = str_contains($e->getMessage(), 'not found') ? 404 : 400;

            return $this->posError($e->getMessage(), $status);
        } catch (\Throwable $e) {
            PosApiLogger::error('orders.create.failed', ['message' => $e->getMessage()]);

            return $this->posServerError($e);
        }
    }

    /**
     * Checkout time stored as Philippines local wall clock for MySQL (+08:00 session).
     * Prefer sold_at_ms from the tablet when available.
     */
    private function resolveOrderCreatedAt(array $body): string
    {
        $tz = BusinessDay::timezone();
        $now = BusinessDay::now();

        $ms = $body['sold_at_ms'] ?? null;
        if (is_numeric($ms) && (float) $ms > 0) {
            $client = Carbon::createFromTimestampMs((int) round((float) $ms), 'UTC')
                ->timezone($tz);

            // Tablet builds may send a bad epoch (often +8h). Trust only if near server time.
            if ($client->diffInSeconds($now, true) <= 180) {
                return $client->format('Y-m-d H:i:s');
            }
        }

        return $now->format('Y-m-d H:i:s');
    }

    private function allowNegativeStock(): bool
    {
        if (! PosHelpers::tableExists('app_settings')) {
            return false;
        }

        $settings = DB::selectOne(
            'SELECT allow_negative_stock
             FROM app_settings
             ORDER BY id ASC
             LIMIT 1',
        );

        return $settings && (int) ($settings->allow_negative_stock ?? 0) === 1;
    }
}
