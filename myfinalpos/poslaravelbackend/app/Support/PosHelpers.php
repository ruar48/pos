<?php

namespace App\Support;

use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

class PosHelpers
{
    public static function optionalInt(mixed $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }

        if (! is_numeric($value)) {
            return null;
        }

        return (int) $value;
    }

    public static function boolToInt(bool $value): int
    {
        return $value ? 1 : 0;
    }

    public static function currentActorId(Request $request, ?array $body = null): ?int
    {
        $payload = $body ?? $request->all();

        $candidate = $payload['actor_user_id']
            ?? $request->header('X-User-Id')
            ?? $request->query('actor_user_id');

        return self::optionalInt($candidate);
    }

    public static function tableExists(string $table): bool
    {
        return Schema::hasTable($table);
    }

    public static function columnExists(string $table, string $column): bool
    {
        return Schema::hasColumn($table, $column);
    }

    public static function isWalkInCustomerName(string $customerName): bool
    {
        $normalized = strtolower(trim($customerName));

        return $normalized === ''
            || $normalized === 'walk in farmer'
            || $normalized === 'walk in'
            || $normalized === 'walk-in farmer';
    }

    public static function walkInCustomerSqlExclusion(string $column = 'customer_name'): string
    {
        return "LOWER(TRIM({$column})) NOT IN ('walk in farmer', 'walk in', 'walk-in farmer') AND TRIM({$column}) <> ''";
    }

    public static function ensureLoyaltyCard(int $customerId, ?int $actorUserId = null): void
    {
        if (! self::tableExists('loyalty_cards')) {
            return;
        }

        $existing = DB::selectOne(
            'SELECT id FROM loyalty_cards WHERE customer_id = ? LIMIT 1',
            [$customerId],
        );

        if ($existing) {
            return;
        }

        $cardNumber = sprintf('LC-%05d', $customerId);
        DB::insert(
            'INSERT INTO loyalty_cards (customer_id, card_number, points, tier, status)
             VALUES (?, ?, 0, "Bronze", "Active")',
            [$customerId, $cardNumber],
        );

        $cardId = (int) DB::getPdo()->lastInsertId();
        self::insertLoyaltyPointLog(
            customerId: $customerId,
            loyaltyCardId: $cardId,
            action: 'open_card',
            pointsChange: 0,
            pointsBalanceAfter: 0,
            description: 'Loyalty card opened',
            actorUserId: $actorUserId,
        );
    }

    public static function normalizeNfcUid(string $value): string
    {
        $normalized = strtoupper(preg_replace('/[^0-9A-F]/', '', trim($value)) ?? '');

        return $normalized;
    }

    /**
     * @return array<string, mixed>|null
     */
    public static function findCustomerByNfcUid(string $nfcUid): ?array
    {
        if (! self::tableExists('loyalty_cards') || ! self::columnExists('loyalty_cards', 'nfc_uid')) {
            return null;
        }

        $nfcUid = self::normalizeNfcUid($nfcUid);
        if ($nfcUid === '' || strlen($nfcUid) < 4) {
            return null;
        }

        $row = DB::selectOne(
            'SELECT
                c.id AS customer_id,
                c.customer_name,
                c.table_name,
                c.order_type,
                c.created_at AS customer_created_at,
                lc.card_number,
                lc.nfc_uid,
                lc.points,
                lc.tier,
                lc.status AS card_status,
                lc.created_at AS card_created_at
             FROM loyalty_cards lc
             INNER JOIN customers c ON c.id = lc.customer_id
             WHERE lc.nfc_uid = ?
             LIMIT 1',
            [$nfcUid],
        );

        if (! $row) {
            return null;
        }

        if (self::isWalkInCustomerName((string) $row->customer_name)) {
            return null;
        }

        return [
            'customer' => [
                'id' => (int) $row->customer_id,
                'customer_name' => (string) $row->customer_name,
                'table_name' => (string) ($row->table_name ?? ''),
                'order_type' => (string) ($row->order_type ?? 'Retail'),
                'created_at' => $row->customer_created_at,
            ],
            'loyalty_card' => [
                'customer_id' => (int) $row->customer_id,
                'customer_name' => (string) $row->customer_name,
                'card_number' => (string) $row->card_number,
                'nfc_uid' => (string) $row->nfc_uid,
                'points' => (int) $row->points,
                'tier' => (string) $row->tier,
                'status' => (string) $row->card_status,
                'created_at' => $row->card_created_at,
            ],
        ];
    }

    public static function linkLoyaltyCardNfc(
        int $customerId,
        string $nfcUid,
        ?int $actorUserId = null,
    ): array {
        if (! self::tableExists('loyalty_cards')) {
            throw new \RuntimeException('Loyalty cards are not available on this server');
        }

        if (! self::columnExists('loyalty_cards', 'nfc_uid')) {
            throw new \RuntimeException('NFC linking is not enabled. Run database migrations.');
        }

        $nfcUid = self::normalizeNfcUid($nfcUid);
        if ($nfcUid === '' || strlen($nfcUid) < 4) {
            throw new \InvalidArgumentException('Invalid NFC card UID');
        }

        $customer = DB::selectOne(
            'SELECT id, customer_name FROM customers WHERE id = ? LIMIT 1',
            [$customerId],
        );

        if (! $customer) {
            throw new \InvalidArgumentException('Customer not found');
        }

        if (self::isWalkInCustomerName((string) $customer->customer_name)) {
            throw new \InvalidArgumentException('Walk-in customers cannot enroll in the loyalty program');
        }

        $duplicate = DB::selectOne(
            'SELECT customer_id FROM loyalty_cards WHERE nfc_uid = ? AND customer_id <> ? LIMIT 1',
            [$nfcUid, $customerId],
        );

        if ($duplicate) {
            throw new \InvalidArgumentException('This NFC card is already linked to another customer');
        }

        $alreadyLinked = DB::selectOne(
            'SELECT customer_id FROM loyalty_cards WHERE customer_id = ? AND nfc_uid = ? LIMIT 1',
            [$customerId, $nfcUid],
        );

        if ($alreadyLinked) {
            $card = DB::selectOne(
                'SELECT
                    lc.customer_id,
                    c.customer_name,
                    lc.card_number,
                    lc.nfc_uid,
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

            return (array) $card;
        }

        self::ensureLoyaltyCard($customerId, $actorUserId);

        DB::update(
            'UPDATE loyalty_cards SET nfc_uid = ? WHERE customer_id = ?',
            [$nfcUid, $customerId],
        );

        $card = DB::selectOne(
            'SELECT
                lc.customer_id,
                c.customer_name,
                lc.card_number,
                lc.nfc_uid,
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

        self::insertAuditLog(
            $actorUserId,
            'link_nfc',
            'loyalty',
            'loyalty_card',
            $customerId,
            'NFC card linked to loyalty profile',
            ['customer_id' => $customerId, 'nfc_uid' => $nfcUid],
        );

        return (array) $card;
    }

    /**
     * Put refunded units back on the shelf — mirrors sale stock deduction
     * (product stock always; variety stock when the line has a variety).
     *
     * @return array<string, mixed>
     */
    public static function restoreRefundedStock(
        object $orderItem,
        float $quantity,
        int $refundId,
        ?int $actorUserId = null,
        string $note = 'Refund',
    ): array {
        if ($quantity <= 0) {
            throw new \InvalidArgumentException('Refund quantity must be greater than zero');
        }

        $productId = (int) ($orderItem->product_id ?? 0);
        if ($productId <= 0) {
            throw new \InvalidArgumentException('Invalid product on refunded line');
        }

        $varietyId = null;
        if (self::columnExists('order_items', 'variety_id')
            && isset($orderItem->variety_id)
            && $orderItem->variety_id !== null
            && (int) $orderItem->variety_id > 0) {
            $varietyId = (int) $orderItem->variety_id;
        }

        if ($varietyId === null
            && self::tableExists('product_varieties')
            && self::columnExists('order_items', 'variety_name')) {
            $varietyName = trim((string) ($orderItem->variety_name ?? ''));
            if ($varietyName !== '') {
                $match = DB::selectOne(
                    'SELECT id FROM product_varieties WHERE product_id = ? AND name = ? LIMIT 1',
                    [$productId, $varietyName],
                );
                if ($match) {
                    $varietyId = (int) $match->id;
                }
            }
        }

        $varietyStockAfter = null;

        if ($varietyId !== null && self::tableExists('product_varieties')) {
            $updated = DB::update(
                'UPDATE product_varieties SET stock = stock + ? WHERE id = ?',
                [$quantity, $varietyId],
            );

            if ($updated === 0) {
                throw new \RuntimeException("Could not restore variety stock for variety #{$varietyId}");
            }

            $varietyRow = DB::selectOne(
                'SELECT stock FROM product_varieties WHERE id = ? LIMIT 1',
                [$varietyId],
            );
            $varietyStockAfter = $varietyRow ? (float) $varietyRow->stock : null;
        }

        $productUpdated = DB::update(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [$quantity, $productId],
        );

        if ($productUpdated === 0) {
            throw new \RuntimeException("Could not restore product stock for product #{$productId}");
        }

        $productRow = DB::selectOne(
            'SELECT stock FROM products WHERE id = ? LIMIT 1',
            [$productId],
        );
        $productStockAfter = $productRow ? (float) $productRow->stock : null;

        StockLedger::record(
            productId: $productId,
            varietyId: $varietyId,
            type: 'refund',
            quantityDelta: $quantity,
            balanceAfter: $varietyId !== null ? $varietyStockAfter : $productStockAfter,
            referenceType: 'refund',
            referenceId: $refundId,
            note: $note,
            userId: $actorUserId,
        );

        return [
            'order_item_id' => (int) ($orderItem->id ?? 0),
            'product_id' => $productId,
            'variety_id' => $varietyId,
            'quantity' => $quantity,
            'product_stock_after' => $productStockAfter,
            'variety_stock_after' => $varietyStockAfter,
        ];
    }

    public static function taxRate(): float
    {
        if (! self::tableExists('app_settings')) {
            return 0.12;
        }

        $row = DB::selectOne(
            'SELECT tax_rate FROM app_settings ORDER BY id ASC LIMIT 1',
        );

        if (! $row) {
            return 0.12;
        }

        return max(0.0, min(1.0, round((float) ($row->tax_rate ?? 0.12), 4)));
    }

    /**
     * VAT rate applied on the original order (0 when the sale had no VAT).
     */
    public static function orderVatRate(object $order): float
    {
        $vat = round((float) ($order->vat ?? 0), 4);
        if ($vat <= 0) {
            return 0.0;
        }

        $taxableBase = round((float) ($order->subtotal ?? 0), 2);
        if ($taxableBase <= 0) {
            return 0.0;
        }

        return $vat / $taxableBase;
    }

    /**
     * Refund cash amount for a merchandise portion, including proportional VAT.
     */
    public static function refundAmountIncludingVat(object $order, float $merchandiseAmount): float
    {
        $merchandiseAmount = round(max(0, $merchandiseAmount), 2);
        if ($merchandiseAmount <= 0) {
            return 0.0;
        }

        $vatPortion = round($merchandiseAmount * self::orderVatRate($order), 2);

        return round($merchandiseAmount + $vatPortion, 2);
    }

    /**
     * Compute VAT and total from net merchandise using the store tax setting.
     *
     * @return array{0: float, 1: float} [vat, total]
     */
    public static function saleVatAndTotal(float $netMerchandise): array
    {
        $netMerchandise = round(max(0, $netMerchandise), 2);
        $vat = round($netMerchandise * self::taxRate(), 2);

        return [$vat, round($netMerchandise + $vat, 2)];
    }

    public static function loyaltySettings(): array
    {
        $defaults = [
            'loyalty_enabled' => true,
            'loyalty_points_per_unit' => 50,
            'loyalty_spend_unit' => 1000.0,
            'loyalty_redeem_points_per_peso' => 10,
        ];

        if (! self::tableExists('app_settings')) {
            return $defaults;
        }

        $select = ['loyalty_enabled'];
        if (self::columnExists('app_settings', 'loyalty_points_per_unit')) {
            $select[] = 'loyalty_points_per_unit';
        }
        if (self::columnExists('app_settings', 'loyalty_spend_unit')) {
            $select[] = 'loyalty_spend_unit';
        }
        if (self::columnExists('app_settings', 'loyalty_redeem_points_per_peso')) {
            $select[] = 'loyalty_redeem_points_per_peso';
        }

        $row = DB::selectOne(
            'SELECT '.implode(', ', $select).' FROM app_settings ORDER BY id ASC LIMIT 1',
        );

        if (! $row) {
            return $defaults;
        }

        $data = (array) $row;

        return [
            'loyalty_enabled' => ((int) ($data['loyalty_enabled'] ?? 1)) === 1,
            'loyalty_points_per_unit' => max(0, (int) ($data['loyalty_points_per_unit'] ?? 50)),
            'loyalty_spend_unit' => max(0.01, (float) ($data['loyalty_spend_unit'] ?? 1000)),
            'loyalty_redeem_points_per_peso' => max(1, (int) ($data['loyalty_redeem_points_per_peso'] ?? 10)),
        ];
    }

    public static function isLoyaltyProgramEnabled(): bool
    {
        return self::loyaltySettings()['loyalty_enabled'] === true;
    }

    public static function calculateLoyaltyPointsEarned(float $totalPaid): int
    {
        if ($totalPaid <= 0 || ! self::isLoyaltyProgramEnabled()) {
            return 0;
        }

        $settings = self::loyaltySettings();
        $pointsPerUnit = (int) $settings['loyalty_points_per_unit'];
        $spendUnit = (float) $settings['loyalty_spend_unit'];

        if ($pointsPerUnit <= 0 || $spendUnit <= 0) {
            return 0;
        }

        return (int) floor(($totalPaid / $spendUnit) * $pointsPerUnit);
    }

    public static function awardLoyaltyPoints(
        int $customerId,
        float $totalPaid,
        ?int $orderId = null,
        ?int $actorUserId = null,
    ): void {
        if (! self::tableExists('loyalty_cards') || ! self::isLoyaltyProgramEnabled()) {
            return;
        }

        self::ensureLoyaltyCard($customerId, $actorUserId);

        $pointsToAdd = self::calculateLoyaltyPointsEarned($totalPaid);
        if ($pointsToAdd <= 0) {
            return;
        }

        $card = DB::selectOne(
            'SELECT id, points FROM loyalty_cards WHERE customer_id = ? LIMIT 1 FOR UPDATE',
            [$customerId],
        );

        if (! $card) {
            return;
        }

        $newPoints = (int) $card->points + $pointsToAdd;
        DB::update(
            'UPDATE loyalty_cards SET points = ?, tier = ?, status = "Active" WHERE id = ?',
            [$newPoints, self::loyaltyTierForPoints($newPoints), (int) $card->id],
        );

        $orderLabel = $orderId !== null && $orderId > 0
            ? 'order #'.$orderId
            : 'checkout';
        $amountLabel = $totalPaid > 0
            ? ' (₱'.number_format($totalPaid, 2).')'
            : '';

        self::insertLoyaltyPointLog(
            customerId: $customerId,
            loyaltyCardId: (int) $card->id,
            action: 'earn',
            pointsChange: $pointsToAdd,
            pointsBalanceAfter: $newPoints,
            description: 'Earned '.$pointsToAdd.' points from '.$orderLabel.$amountLabel,
            orderId: $orderId,
            orderAmount: $totalPaid,
            actorUserId: $actorUserId,
        );
    }

    public static function deductRedeemedLoyaltyPoints(
        int $customerId,
        int $points,
        ?int $orderId = null,
        ?int $actorUserId = null,
    ): void {
        if ($points <= 0 || ! self::tableExists('loyalty_cards')) {
            return;
        }

        $card = DB::selectOne(
            'SELECT id, points FROM loyalty_cards WHERE customer_id = ? LIMIT 1 FOR UPDATE',
            [$customerId],
        );

        if (! $card) {
            return;
        }

        $newPoints = max(0, (int) $card->points - $points);
        DB::update(
            'UPDATE loyalty_cards SET points = ?, tier = ? WHERE id = ?',
            [$newPoints, self::loyaltyTierForPoints($newPoints), (int) $card->id],
        );

        $orderLabel = $orderId !== null && $orderId > 0
            ? 'order #'.$orderId
            : 'checkout';

        self::insertLoyaltyPointLog(
            customerId: $customerId,
            loyaltyCardId: (int) $card->id,
            action: 'redeem',
            pointsChange: -$points,
            pointsBalanceAfter: $newPoints,
            description: 'Redeemed '.$points.' points on '.$orderLabel,
            orderId: $orderId,
            actorUserId: $actorUserId,
        );
    }

    public static function loyaltyTierForPoints(int $points): string
    {
        if ($points >= 1000) {
            return 'Platinum';
        }

        if ($points >= 500) {
            return 'Gold';
        }

        if ($points >= 200) {
            return 'Silver';
        }

        return 'Bronze';
    }

    public static function insertLoyaltyPointLog(
        int $customerId,
        string $action,
        int $pointsChange,
        int $pointsBalanceAfter,
        string $description,
        ?int $loyaltyCardId = null,
        ?int $orderId = null,
        ?float $orderAmount = null,
        ?int $actorUserId = null,
    ): void {
        if (! self::tableExists('loyalty_point_logs')) {
            return;
        }

        DB::insert(
            'INSERT INTO loyalty_point_logs
                (customer_id, loyalty_card_id, order_id, action, points_change, points_balance_after, order_amount, description, actor_user_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $customerId,
                $loyaltyCardId,
                $orderId,
                $action,
                $pointsChange,
                $pointsBalanceAfter,
                $orderAmount,
                $description,
                $actorUserId,
            ],
        );
    }

    public static function loyaltyPointLogRowToArray(array $row): array
    {
        return [
            'id' => (int) ($row['id'] ?? 0),
            'customer_id' => (int) ($row['customer_id'] ?? 0),
            'loyalty_card_id' => isset($row['loyalty_card_id']) ? (int) $row['loyalty_card_id'] : null,
            'order_id' => isset($row['order_id']) ? (int) $row['order_id'] : null,
            'action' => (string) ($row['action'] ?? ''),
            'points_change' => (int) ($row['points_change'] ?? 0),
            'points_balance_after' => (int) ($row['points_balance_after'] ?? 0),
            'order_amount' => isset($row['order_amount']) ? (float) $row['order_amount'] : null,
            'description' => (string) ($row['description'] ?? ''),
            'actor_user_id' => isset($row['actor_user_id']) ? (int) $row['actor_user_id'] : null,
            'actor_name' => $row['actor_name'] ?? null,
            'created_at' => (string) ($row['created_at'] ?? ''),
        ];
    }

    public static function insertAuditLog(
        ?int $userId,
        string $action,
        string $module,
        string $entityType,
        ?int $entityId,
        string $description,
        array $payload = [],
    ): void {
        if (! self::tableExists('audit_logs')) {
            return;
        }

        $row = [
            'user_id' => $userId,
            'action' => $action,
            'module' => $module,
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'description' => $description,
            'payload_json' => empty($payload) ? null : json_encode($payload),
            'created_at' => now(),
        ];

        self::insertWithAutoIdFallback('audit_logs', $row, [
            'action' => $action,
            'module' => $module,
            'entity_type' => $entityType,
            'entity_id' => $entityId,
        ]);
    }

    public static function insertUserTransaction(
        ?int $userId,
        string $transactionType,
        string $referenceTable,
        ?int $referenceId,
        float $amount = 0.0,
        string $notes = '',
        array $payload = [],
    ): void {
        if (! self::tableExists('user_transactions')) {
            return;
        }

        $row = [
            'user_id' => $userId,
            'transaction_type' => $transactionType,
            'reference_table' => $referenceTable,
            'reference_id' => $referenceId,
            'amount' => round($amount, 2),
            'notes' => $notes,
            'payload_json' => empty($payload) ? null : json_encode($payload),
            'created_at' => now(),
        ];

        self::insertWithAutoIdFallback('user_transactions', $row, [
            'transaction_type' => $transactionType,
            'reference_table' => $referenceTable,
            'reference_id' => $referenceId,
        ]);
    }

    /**
     * Insert a row and return the new id. Retries with MAX(id)+1 when AUTO_INCREMENT is missing.
     *
     * @param  array<string, mixed>  $row
     * @param  array<string, mixed>  $logContext
     */
    public static function insertRow(
        string $table,
        array $row,
        array $logContext = [],
    ): int {
        try {
            DB::table($table)->insert($row);
            $id = (int) DB::getPdo()->lastInsertId();
            if ($id > 0) {
                return $id;
            }
        } catch (\Throwable $exception) {
            if (! self::isMissingAutoIncrementId($exception)) {
                Log::warning("{$table} insert failed: ".$exception->getMessage(), $logContext);

                throw $exception;
            }
        }

        try {
            $nextId = ((int) DB::table($table)->max('id')) + 1;
            DB::table($table)->insert(['id' => $nextId] + $row);

            return $nextId;
        } catch (\Throwable $fallback) {
            Log::warning("{$table} insert failed: ".$fallback->getMessage(), $logContext);

            throw $fallback;
        }
    }

    /**
     * @param  array<string, mixed>  $row
     * @param  array<string, mixed>  $logContext
     */
    private static function insertWithAutoIdFallback(
        string $table,
        array $row,
        array $logContext = [],
    ): void {
        try {
            self::insertRow($table, $row, $logContext);
        } catch (\Throwable) {
            // Audit / transaction logs must not break the main POS action.
        }
    }

    private static function isMissingAutoIncrementId(\Throwable $exception): bool
    {
        $message = $exception->getMessage();

        return str_contains($message, "Field 'id' doesn't have a default value")
            || str_contains($message, '1364');
    }

    public static function normalizeRoleKey(string $role): string
    {
        return strtolower(trim(str_replace(' ', '_', $role)));
    }

    /**
     * @return list<string>
     */
    public static function allowedRoles(): array
    {
        return ['admin', 'cashier', 'labor'];
    }

    public static function normalizeStoredRole(string $role): string
    {
        $normalized = self::normalizeRoleKey($role);

        if (
            str_contains($normalized, 'super')
            || str_contains($normalized, 'admin')
            || str_contains($normalized, 'manager')
        ) {
            return 'admin';
        }

        if (str_contains($normalized, 'labor') || str_contains($normalized, 'worker')) {
            return 'labor';
        }

        if (str_contains($normalized, 'cashier')) {
            return 'cashier';
        }

        return 'cashier';
    }

    public static function isAllowedRole(string $role): bool
    {
        return in_array(self::normalizeStoredRole($role), self::allowedRoles(), true);
    }

    public static function isAdminRole(string $role): bool
    {
        return self::normalizeStoredRole($role) === 'admin';
    }

    public static function isCashierRole(string $role): bool
    {
        return self::normalizeStoredRole($role) === 'cashier';
    }

    public static function isLaborRole(string $role): bool
    {
        return self::normalizeStoredRole($role) === 'labor';
    }

    public static function canLogin(string $role): bool
    {
        $normalized = self::normalizeStoredRole($role);

        return $normalized === 'admin' || $normalized === 'cashier';
    }

    public static function isManagementRole(string $role): bool
    {
        return self::isAdminRole($role);
    }

    public static function fetchActorUser(?int $actorUserId): ?array
    {
        if ($actorUserId === null || $actorUserId <= 0) {
            return null;
        }

        $columns = self::columnExists('users', 'status')
            ? 'id, full_name, username, email, role, status'
            : 'id, full_name, username, email, role';

        $row = DB::selectOne("SELECT {$columns} FROM users WHERE id = ? LIMIT 1", [$actorUserId]);

        return $row ? (array) $row : null;
    }

    public static function requireAdminActor(?int $actorUserId): array
    {
        $actor = self::fetchActorUser($actorUserId);
        if (! $actor) {
            throw new HttpResponseException(
                response()->json(['success' => false, 'message' => 'Admin authentication required'], 401),
            );
        }

        if (self::columnExists('users', 'status') && (int) ($actor['status'] ?? 1) !== 1) {
            throw new HttpResponseException(
                response()->json(['success' => false, 'message' => 'Your account is inactive'], 403),
            );
        }

        if (! self::isAdminRole((string) ($actor['role'] ?? ''))) {
            throw new HttpResponseException(
                response()->json(['success' => false, 'message' => 'Admin privileges required'], 403),
            );
        }

        return $actor;
    }

    public static function verifyCashDrawerPin(string $pin): bool
    {
        if (! self::tableExists('app_settings') || ! self::columnExists('app_settings', 'cash_drawer_pin_hash')) {
            return false;
        }

        $row = DB::selectOne('SELECT cash_drawer_pin_hash FROM app_settings WHERE id = 1 LIMIT 1');
        $hash = trim((string) ($row->cash_drawer_pin_hash ?? ''));

        if ($hash === '' || $pin === '') {
            return false;
        }

        return password_verify($pin, $hash);
    }

    public static function isRefundPinRequired(): bool
    {
        if (! self::tableExists('app_settings') || ! self::columnExists('app_settings', 'refund_pin_hash')) {
            return false;
        }

        $row = DB::selectOne('SELECT refund_pin_hash FROM app_settings WHERE id = 1 LIMIT 1');

        return trim((string) ($row->refund_pin_hash ?? '')) !== '';
    }

    public static function verifyRefundPin(string $pin): bool
    {
        if (! self::tableExists('app_settings') || ! self::columnExists('app_settings', 'refund_pin_hash')) {
            return false;
        }

        $row = DB::selectOne('SELECT refund_pin_hash FROM app_settings WHERE id = 1 LIMIT 1');
        $hash = trim((string) ($row->refund_pin_hash ?? ''));

        if ($hash === '' || $pin === '') {
            return false;
        }

        return password_verify($pin, $hash);
    }

    public static function requireAuthenticatedActor(?int $actorUserId): array
    {
        $actor = self::fetchActorUser($actorUserId);
        if (! $actor) {
            throw new HttpResponseException(
                response()->json(['success' => false, 'message' => 'Authentication required'], 401),
            );
        }

        if (self::columnExists('users', 'status') && (int) ($actor['status'] ?? 1) !== 1) {
            throw new HttpResponseException(
                response()->json(['success' => false, 'message' => 'Your account is inactive'], 403),
            );
        }

        return $actor;
    }

    public static function requireManagementActor(?int $actorUserId): array
    {
        $actor = self::fetchActorUser($actorUserId);
        if (! $actor) {
            throw new HttpResponseException(
                response()->json(['success' => false, 'message' => 'Authentication required'], 401),
            );
        }

        if (self::columnExists('users', 'status') && (int) ($actor['status'] ?? 1) !== 1) {
            throw new HttpResponseException(
                response()->json(['success' => false, 'message' => 'Your account is inactive'], 403),
            );
        }

        if (! self::isManagementRole((string) ($actor['role'] ?? ''))) {
            throw new HttpResponseException(
                response()->json(['success' => false, 'message' => 'Admin privileges required'], 403),
            );
        }

        return $actor;
    }

    public static function userRowToArray(array|object $row): array
    {
        $data = self::row($row);

        return [
            'id' => (int) $data['id'],
            'full_name' => $data['full_name'],
            'username' => $data['username'],
            'email' => $data['email'],
            'role' => $data['role'],
            'status' => isset($data['status']) ? (int) $data['status'] : 1,
            'branch_id' => isset($data['branch_id']) && $data['branch_id'] !== null ? (int) $data['branch_id'] : null,
            'branch_name' => $data['branch_name'] ?? null,
            'created_at' => $data['created_at'] ?? null,
        ];
    }

    public static function branchRowToArray(array|object $row): array
    {
        $data = self::row($row);

        return [
            'id' => (int) $data['id'],
            'name' => $data['name'],
            'code' => $data['code'] ?? null,
            'location' => $data['location'] ?? null,
            'latitude' => isset($data['latitude']) && $data['latitude'] !== null
                ? (float) $data['latitude']
                : null,
            'longitude' => isset($data['longitude']) && $data['longitude'] !== null
                ? (float) $data['longitude']
                : null,
            'geofence_radius_km' => isset($data['geofence_radius_km'])
                ? (float) $data['geofence_radius_km']
                : 2.0,
            'is_active' => isset($data['is_active']) ? (int) $data['is_active'] : 1,
            'created_at' => $data['created_at'] ?? null,
        ];
    }

    public static function staffPaymentRowToArray(array|object $row): array
    {
        $data = self::row($row);

        return [
            'id' => (int) $data['id'],
            'user_id' => (int) $data['user_id'],
            'staff_name' => (string) ($data['staff_name'] ?? ''),
            'branch_id' => isset($data['branch_id']) && $data['branch_id'] !== null
                ? (int) $data['branch_id']
                : null,
            'branch_name' => $data['branch_name'] ?? null,
            'amount' => round((float) ($data['amount'] ?? 0), 2),
            'payment_type' => (string) ($data['payment_type'] ?? 'salary'),
            'period_start' => $data['period_start'] ?? null,
            'period_end' => $data['period_end'] ?? null,
            'notes' => $data['notes'] ?? null,
            'paid_by_user_id' => isset($data['paid_by_user_id']) && $data['paid_by_user_id'] !== null
                ? (int) $data['paid_by_user_id']
                : null,
            'paid_by_name' => $data['paid_by_name'] ?? null,
            'created_at' => $data['created_at'] ?? null,
        ];
    }

    public static function auditLogRowToArray(array|object $row): array
    {
        $data = self::row($row);

        return [
            'id' => (int) $data['id'],
            'user_id' => isset($data['user_id']) && $data['user_id'] !== null
                ? (int) $data['user_id']
                : null,
            'user_name' => $data['user_name'] ?? null,
            'user_email' => $data['user_email'] ?? null,
            'action' => (string) ($data['action'] ?? ''),
            'module' => (string) ($data['module'] ?? ''),
            'entity_type' => (string) ($data['entity_type'] ?? ''),
            'entity_id' => isset($data['entity_id']) && $data['entity_id'] !== null
                ? (int) $data['entity_id']
                : null,
            'description' => (string) ($data['description'] ?? ''),
            'payload_json' => $data['payload_json'] ?? null,
            'created_at' => $data['created_at'] ?? null,
        ];
    }

    public static function couponRowToArray(array|object $row): array
    {
        $data = self::row($row);

        return [
            'id' => (int) $data['id'],
            'code' => $data['code'],
            'description' => $data['description'],
            'discount_type' => $data['discount_type'],
            'discount_value' => (float) $data['discount_value'],
            'min_order_amount' => (float) $data['min_order_amount'],
            'start_date' => $data['start_date'],
            'end_date' => $data['end_date'],
            'max_uses' => $data['max_uses'] !== null ? (int) $data['max_uses'] : null,
            'usage_count' => (int) $data['usage_count'],
            'status' => (int) $data['status'],
            'created_at' => $data['created_at'] ?? null,
        ];
    }

    public static function normalizeCouponCode(string $code): string
    {
        return strtoupper(trim($code));
    }

    public static function validateCouponDates(string $startDate, string $endDate): ?string
    {
        if ($startDate === '' || $endDate === '') {
            return 'Start and end dates are required';
        }

        $start = \DateTime::createFromFormat('Y-m-d', $startDate);
        $end = \DateTime::createFromFormat('Y-m-d', $endDate);

        if (! $start || ! $end) {
            return 'Invalid date format. Use YYYY-MM-DD';
        }

        if ($end < $start) {
            return 'End date must be on or after start date';
        }

        return null;
    }

    public static function findCouponByCode(string $code): ?array
    {
        $row = DB::selectOne(
            'SELECT * FROM coupons WHERE UPPER(code) = UPPER(?) LIMIT 1',
            [self::normalizeCouponCode($code)],
        );

        return $row ? (array) $row : null;
    }

    public static function isCouponCurrentlyValid(array $coupon, float $subtotal = 0.0): ?string
    {
        if ((int) $coupon['status'] !== 1) {
            return 'Coupon is inactive';
        }

        $today = now()->format('Y-m-d');
        if ($today < $coupon['start_date']) {
            return 'Coupon is not active yet';
        }
        if ($today > $coupon['end_date']) {
            return 'Coupon has expired';
        }

        $minOrder = (float) $coupon['min_order_amount'];
        if ($subtotal > 0 && $subtotal < $minOrder) {
            return 'Order does not meet the minimum amount for this coupon';
        }

        $maxUses = $coupon['max_uses'];
        if ($maxUses !== null && (int) $coupon['usage_count'] >= (int) $maxUses) {
            return 'Coupon usage limit reached';
        }

        return null;
    }

    public static function calculateCouponDiscount(array $coupon, float $subtotal): float
    {
        $type = $coupon['discount_type'];
        $value = (float) $coupon['discount_value'];

        if ($subtotal <= 0) {
            return 0.0;
        }

        if ($type === 'percentage') {
            return round(min($subtotal, $subtotal * ($value / 100)), 2);
        }

        return round(min($subtotal, $value), 2);
    }

    public static function incrementCouponUsage(string $code): void
    {
        $normalized = self::normalizeCouponCode($code);
        if ($normalized === '') {
            return;
        }

        DB::update(
            'UPDATE coupons SET usage_count = usage_count + 1 WHERE UPPER(code) = UPPER(?)',
            [$normalized],
        );
    }

    /**
     * @return list<array{payment_method: string, amount: float, reference: ?string}>
     */
    public static function loadOrderPayments(int $orderId): array
    {
        if (! self::tableExists('order_payments')) {
            return [];
        }

        $rows = DB::select(
            'SELECT payment_method, amount, reference
             FROM order_payments
             WHERE order_id = ?
             ORDER BY id ASC',
            [$orderId],
        );

        return array_map(
            static fn ($row) => [
                'payment_method' => (string) ($row->payment_method ?? 'Cash'),
                'amount' => round((float) ($row->amount ?? 0), 2),
                'reference' => ! empty($row->reference) ? (string) $row->reference : null,
            ],
            $rows,
        );
    }

    private static function row(array|object $row): array
    {
        return is_array($row) ? $row : (array) $row;
    }
}
