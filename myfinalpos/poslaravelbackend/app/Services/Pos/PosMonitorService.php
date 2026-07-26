<?php

namespace App\Services\Pos;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\App;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class PosMonitorService
{
    private const WATCHER_TTL_SECONDS = 90;

    private const STATE_TTL_SECONDS = 180;

    private const REGISTRY_TTL_SECONDS = 300;

    private const ONLINE_SECONDS = 75;

    private const WATCHERS_UNTIL_KEY = 'pos_monitor:watchers_until';

    private const REGISTRY_KEY = 'pos_monitor:registry';

    private const REVISION_KEY = 'pos_monitor:revision';

    public function touchWatcher(int $userId, ?string $terminalId = null): void
    {
        $until = now()->addSeconds(self::WATCHER_TTL_SECONDS)->timestamp;
        $current = (int) Cache::get(self::WATCHERS_UNTIL_KEY, 0);
        Cache::put(self::WATCHERS_UNTIL_KEY, max($current, $until), self::WATCHER_TTL_SECONDS + 10);

        Cache::put($this->watcherKey($userId), true, self::WATCHER_TTL_SECONDS);

        if ($terminalId !== null && trim($terminalId) !== '') {
            Cache::put(
                $this->watcherTerminalKey($userId),
                trim($terminalId),
                self::WATCHER_TTL_SECONDS + 60,
            );
        }
    }

    public function removeWatcher(int $userId): void
    {
        Cache::forget($this->watcherKey($userId));
        Cache::forget($this->watcherTerminalKey($userId));

        if (! $this->hasActiveWatchers()) {
            Cache::forget(self::WATCHERS_UNTIL_KEY);
        }
    }

    public function revision(): string
    {
        return (string) Cache::get(self::REVISION_KEY, '0');
    }

    public function selectedTerminalForUser(int $userId): ?string
    {
        $value = Cache::get($this->watcherTerminalKey($userId));

        return is_string($value) && $value !== '' ? $value : null;
    }

    public function hasActiveWatchers(): bool
    {
        return (int) Cache::get(self::WATCHERS_UNTIL_KEY, 0) > now()->timestamp;
    }

    /**
     * One live monitor card per logged-in cashier. Older session IDs for the
     * same cashier (e.g. after hot restart) are retired on the next heartbeat.
     *
     * @param  array<string, mixed>  $payload
     */
    public function resolveRegisterId(array $payload): string
    {
        $cashierId = (int) ($payload['cashier_id'] ?? 0);
        $base = trim((string) ($payload['register_code'] ?? ''));

        if ($base === '' || str_contains($base, ' · ')) {
            $base = trim((string) ($payload['terminal_label'] ?? ''));
        }

        if ($base === '' || str_contains($base, ' · ')) {
            $terminalId = trim((string) ($payload['terminal_id'] ?? 'POS-01'));
            if (preg_match('/^(.+)-u\d+(?:-.+)?$/', $terminalId, $matches) === 1) {
                $base = (string) $matches[1];
            } else {
                $base = $terminalId !== '' ? $terminalId : 'POS-01';
            }
        }

        if ($base === '') {
            $base = 'POS-01';
        }

        if ($cashierId > 0) {
            return $base.'-u'.$cashierId;
        }

        return $base;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    public function resolveRegisterLabel(array $payload, string $registerId): string
    {
        $cashierName = trim((string) ($payload['cashier_name'] ?? ''));
        if ($cashierName !== '') {
            return $cashierName;
        }

        $base = trim((string) ($payload['terminal_label'] ?? $payload['register_code'] ?? 'Register'));
        if ($base === '') {
            return $registerId;
        }

        return $base;
    }

    /**
     * Lightweight heartbeat so open POS tablets appear on the monitor wall
     * even before a sale starts. Does not require an active watcher.
     *
     * @param  array<string, mixed>  $payload
     */
    public function touchPresence(string $terminalId, array $payload): void
    {
        $terminalId = trim($terminalId);
        if ($terminalId === '') {
            return;
        }

        $now = now()->toIso8601String();
        $registerLabel = $this->resolveRegisterLabel($payload, $terminalId);
        $registerCode = trim((string) ($payload['register_code'] ?? $payload['terminal_label'] ?? 'POS-01'));
        if ($registerCode === '' || str_contains($registerCode, ' · ')) {
            $registerCode = 'POS-01';
        }
        $cashierUsername = $this->resolveCashierUsername($payload);
        $incomingStatus = (string) ($payload['status'] ?? 'idle');
        $registryPayload = [
            'terminal_id' => $terminalId,
            'terminal_label' => $registerLabel,
            'register_code' => $registerCode,
            'cashier_name' => (string) ($payload['cashier_name'] ?? 'Cashier'),
            'cashier_username' => $cashierUsername,
            'branch_name' => (string) ($payload['branch_name'] ?? 'Main Branch'),
            'customer_name' => (string) ($payload['customer_name'] ?? ''),
            'status' => $incomingStatus,
            'total' => round((float) ($payload['total'] ?? 0), 2),
            'updated_at' => $now,
        ];

        $this->upsertRegistry($terminalId, $registryPayload);
        $this->retireOtherCashierTerminals((int) ($payload['cashier_id'] ?? 0), $terminalId);
        $this->pruneStaleTerminals();

        /** @var array<string, mixed>|null $existing */
        $existing = Cache::get($this->terminalStateKey($terminalId));
        if (is_array($existing) && $this->isRecent($existing)) {
            $this->patchPresenceState($terminalId, $existing, $payload, $registerLabel, $registerCode, $now);

            return;
        }

        Cache::put($this->terminalStateKey($terminalId), [
            'terminal_id' => $terminalId,
            'terminal_label' => $registerLabel,
            'register_code' => $registerCode,
            'branch_id' => (int) ($payload['branch_id'] ?? 1),
            'branch_name' => $registryPayload['branch_name'],
            'cashier_id' => (int) ($payload['cashier_id'] ?? 0),
            'cashier_name' => $registryPayload['cashier_name'],
            'cashier_username' => $cashierUsername,
            'customer_name' => (string) ($payload['customer_name'] ?? 'Walk-in'),
            'order_type' => (string) ($payload['order_type'] ?? 'Retail'),
            'status' => in_array($incomingStatus, ['idle', 'cart', 'payment', 'success'], true)
                ? $incomingStatus
                : 'idle',
            'is_payment_mode' => $incomingStatus === 'payment',
            'items' => [],
            'item_count' => 0,
            'subtotal' => round((float) ($payload['total'] ?? 0), 2),
            'discount' => 0,
            'vat' => 0,
            'total' => round((float) ($payload['total'] ?? 0), 2),
            'success' => null,
            'updated_at' => $now,
        ], self::STATE_TTL_SECONDS);
    }

    /**
     * @param  array<string, mixed>  $existing
     * @param  array<string, mixed>  $payload
     */
    private function patchPresenceState(
        string $terminalId,
        array $existing,
        array $payload,
        string $registerLabel,
        string $registerCode,
        string $now,
    ): void {
        $incomingStatus = (string) ($payload['status'] ?? 'idle');
        $existingStatus = (string) ($existing['status'] ?? 'idle');
        $statusChanged = false;

        if ($incomingStatus === 'idle') {
            $existing['status'] = 'idle';
            $existing['is_payment_mode'] = false;
            $existing['items'] = [];
            $existing['item_count'] = 0;
            $existing['subtotal'] = round((float) ($payload['total'] ?? 0), 2);
            $existing['discount'] = 0;
            $existing['vat'] = 0;
            $existing['total'] = $existing['subtotal'];
            $existing['success'] = null;
        } elseif (in_array($incomingStatus, ['cart', 'payment', 'success'], true)) {
            $statusChanged = $existingStatus !== $incomingStatus;
            $existing['status'] = $incomingStatus;
            $existing['is_payment_mode'] = $incomingStatus === 'payment';
        } elseif (! in_array($existingStatus, ['cart', 'payment', 'success'], true)) {
            $existing['status'] = 'idle';
            $existing['is_payment_mode'] = false;
        }

        $existing['terminal_label'] = $registerLabel;
        $existing['register_code'] = $registerCode;
        $existing['cashier_name'] = (string) ($payload['cashier_name'] ?? $existing['cashier_name'] ?? 'Cashier');
        $existing['cashier_username'] = $this->resolveCashierUsername($payload, $existing);
        $existing['branch_name'] = (string) ($payload['branch_name'] ?? $existing['branch_name'] ?? 'Main Branch');
        $existing['customer_name'] = (string) ($payload['customer_name'] ?? $existing['customer_name'] ?? 'Walk-in');
        $existing['updated_at'] = $now;

        $existing = $this->normalizeMonitorState($existing);

        Cache::put($this->terminalStateKey($terminalId), $existing, self::STATE_TTL_SECONDS);

        if ($statusChanged || $incomingStatus === 'success') {
            $this->bumpRevision();
        }
    }

    public function disconnectTerminal(string $terminalId, int $cashierId = 0): void
    {
        $terminalId = trim($terminalId);
        if ($terminalId === '' && $cashierId <= 0) {
            return;
        }

        /** @var array<string, array<string, mixed>> $registry */
        $registry = Cache::get(self::REGISTRY_KEY, []);
        $toRemove = [];

        if ($terminalId !== '') {
            $toRemove[] = $terminalId;
        }

        foreach (array_keys($registry) as $registeredId) {
            if ($cashierId > 0 && $this->cashierIdFromTerminalId($registeredId) === $cashierId) {
                $toRemove[] = $registeredId;
            }
        }

        $toRemove = array_values(array_unique($toRemove));
        if ($toRemove === []) {
            return;
        }

        $changed = false;
        foreach ($toRemove as $removeId) {
            if (! array_key_exists($removeId, $registry)) {
                Cache::forget($this->terminalStateKey($removeId));
                Cache::forget($this->terminalSuccessKey($removeId));
                $changed = true;

                continue;
            }

            unset($registry[$removeId]);
            Cache::forget($this->terminalStateKey($removeId));
            Cache::forget($this->terminalSuccessKey($removeId));
            $changed = true;
        }

        if (! $changed) {
            return;
        }

        Cache::put(self::REGISTRY_KEY, $registry, self::REGISTRY_TTL_SECONDS);
        $this->bumpRevision();
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    public function publish(string $terminalId, array $payload): void
    {
        $terminalId = trim($terminalId);
        if ($terminalId === '') {
            return;
        }

        $status = (string) ($payload['status'] ?? 'idle');
        $isCritical = in_array($status, ['payment', 'success'], true);

        if (! $isCritical && ! $this->hasActiveWatchers()) {
            return;
        }

        $payload['terminal_id'] = $terminalId;
        $payload['updated_at'] = now()->toIso8601String();

        /** @var array<string, mixed>|null $existing */
        $existing = Cache::get($this->terminalStateKey($terminalId));
        $clientSeq = (int) ($payload['publish_seq'] ?? 0);
        if ($clientSeq > 0 && is_array($existing)) {
            $existingSeq = (int) ($existing['publish_seq'] ?? 0);
            if ($clientSeq <= $existingSeq) {
                return;
            }
        }

        $monitorReset = (bool) ($payload['monitor_reset'] ?? false);
        $items = is_array($payload['items'] ?? null) ? $payload['items'] : [];
        $hasCartActivity = in_array($status, ['cart', 'payment'], true)
            && (count($items) > 0 || (int) ($payload['item_count'] ?? 0) > 0);

        // Only block stray empty-idle snapshots right after checkout.
        // A new deal (cart/payment with items) must replace success immediately.
        if (
            ! $monitorReset
            && ! $hasCartActivity
            && $status === 'idle'
            && is_array($existing)
            && (string) ($existing['status'] ?? '') === 'success'
            && $this->isRecent($existing)
        ) {
            return;
        }

        if ($hasCartActivity || ($monitorReset && $status === 'idle')) {
            Cache::forget($this->terminalSuccessKey($terminalId));
        }

        if ($status === 'success' && ! is_array($payload['success'] ?? null)) {
            /** @var array<string, mixed>|null $cachedSuccess */
            $cachedSuccess = Cache::get($this->terminalSuccessKey($terminalId));
            if (is_array($cachedSuccess) && $cachedSuccess !== []) {
                $payload['success'] = $cachedSuccess;
            }
        }

        $payload['cashier_username'] = $this->resolveCashierUsername($payload);

        $this->retireOtherCashierTerminals((int) ($payload['cashier_id'] ?? 0), $terminalId);
        $this->upsertRegistry($terminalId, $payload);
        $payload = $this->normalizeMonitorState($payload);

        /** @var array<string, mixed>|null $existing */
        $existing = Cache::get($this->terminalStateKey($terminalId));
        $stateChanged = ! $this->monitorStateEquals($existing, $payload);
        Cache::put($this->terminalStateKey($terminalId), $payload, self::STATE_TTL_SECONDS);
        if ($stateChanged || in_array($status, ['payment', 'success'], true)) {
            $this->bumpRevision();
        }

        if ($status === 'success' && is_array($payload['success'] ?? null)) {
            Cache::put(
                $this->terminalSuccessKey($terminalId),
                $payload['success'],
                90,
            );
        }
    }

    /**
     * @return array<string, mixed>
     */
    public function livePayload(
        ?int $userId = null,
        ?string $terminalId = null,
        ?string $sinceRevision = null,
    ): array {
        $this->pruneStaleTerminals();

        if ($userId !== null && ($terminalId === null || $terminalId === '')) {
            $terminalId = $this->selectedTerminalForUser($userId);
        }

        $revision = $this->revision();
        $watching = $this->hasActiveWatchers();

        if (
            $sinceRevision !== null
            && $sinceRevision !== ''
            && hash_equals($revision, $sinceRevision)
        ) {
            $terminals = $this->listTerminals();
            $onlineCount = 0;
            $activeCount = 0;

            foreach ($terminals as $terminal) {
                if ($terminal['online']) {
                    $onlineCount++;
                }
                if (in_array($terminal['status'], ['cart', 'payment', 'success'], true)) {
                    $activeCount++;
                }
            }

            return [
                'unchanged' => true,
                'revision' => $revision,
                'watching' => $watching,
                'online_count' => $onlineCount,
                'active_count' => $activeCount,
                'terminals' => $terminals,
                'terminal_states' => $this->collectTerminalStates($terminals),
            ];
        }

        $terminals = $this->listTerminals();
        $terminalStates = $this->collectTerminalStates($terminals);
        $state = null;
        $registerOnline = false;
        $onlineCount = 0;
        $activeCount = 0;

        foreach ($terminals as $terminal) {
            if ($terminal['online']) {
                $onlineCount++;
            }
            if (in_array($terminal['status'], ['cart', 'payment', 'success'], true)) {
                $activeCount++;
            }
        }

        if ($terminalId !== null && $terminalId !== '') {
            $state = $terminalStates[$terminalId] ?? null;
            $registerOnline = $this->isOnline($state);

            if ($state === null) {
                foreach ($terminals as $terminal) {
                    if ($terminal['terminal_id'] === $terminalId) {
                        $registerOnline = $terminal['online'];
                        break;
                    }
                }
            }
        }

        return [
            'unchanged' => false,
            'revision' => $revision,
            'watching' => $watching,
            'selected_terminal_id' => $terminalId,
            'terminals' => $terminals,
            'terminal_states' => $terminalStates,
            'online_count' => $onlineCount,
            'active_count' => $activeCount,
            'register_online' => $registerOnline,
            'state' => $state,
        ];
    }

    /**
     * Long-poll until a register snapshot changes (cart, payment, sale, etc.).
     *
     * @return array{changed: bool, revision: string}
     */
    public function watch(?string $sinceRevision = null): array
    {
        // Stay under PHP / proxy limits on shared hosting.
        @set_time_limit(0);

        // Keep Hostinger-friendly holds short; refresh watcher TTL while waiting.
        $holdSeconds = App::environment('local') ? 6.0 : 12.0;
        $deadline = microtime(true) + $holdSeconds;

        if ($sinceRevision === null || $sinceRevision === '') {
            return [
                'changed' => true,
                'revision' => $this->revision(),
            ];
        }

        $ticks = 0;

        do {
            if ($ticks % 8 === 0) {
                $this->pruneStaleTerminals();
            }
            // Keep "watching" alive for the whole long-poll window.
            if ($ticks % 12 === 0) {
                $this->extendActiveWatchersWindow();
            }
            $ticks++;

            $revision = $this->revision();
            if (! hash_equals($revision, $sinceRevision)) {
                return [
                    'changed' => true,
                    'revision' => $revision,
                ];
            }

            usleep(75000);
        } while (microtime(true) < $deadline);

        return [
            'changed' => false,
            'revision' => $this->revision() ?: $sinceRevision,
        ];
    }

    private function extendActiveWatchersWindow(): void
    {
        if (! $this->hasActiveWatchers()) {
            return;
        }

        $until = now()->addSeconds(self::WATCHER_TTL_SECONDS)->timestamp;
        Cache::put(self::WATCHERS_UNTIL_KEY, $until, self::WATCHER_TTL_SECONDS + 10);
    }

    /**
     * @param  array<int, array<string, mixed>>  $terminals
     * @return array<string, array<string, mixed>>
     */
    private function collectTerminalStates(array $terminals): array
    {
        $states = [];

        foreach ($terminals as $terminal) {
            $terminalId = (string) ($terminal['terminal_id'] ?? '');
            if ($terminalId === '') {
                continue;
            }

            /** @var array<string, mixed>|null $state */
            $state = Cache::get($this->terminalStateKey($terminalId));
            $state = $this->hydrateSuccessState($terminalId, $state);

            if ($state !== null) {
                if (trim((string) ($state['cashier_username'] ?? '')) === '') {
                    $state['cashier_username'] = $this->resolveCashierUsername($state);
                }

                $states[$terminalId] = $this->normalizeMonitorState($state);

                continue;
            }

            if (! $terminal['online']) {
                continue;
            }

            $states[$terminalId] = [
                'terminal_id' => $terminalId,
                'terminal_label' => (string) ($terminal['terminal_label'] ?? $terminalId),
                'register_code' => (string) ($terminal['register_code'] ?? $terminal['terminal_label'] ?? $terminalId),
                'branch_id' => 0,
                'branch_name' => (string) ($terminal['branch_name'] ?? 'Main Branch'),
                'cashier_id' => 0,
                'cashier_name' => (string) ($terminal['cashier_name'] ?? 'Cashier'),
                'cashier_username' => (string) ($terminal['cashier_username'] ?? ''),
                'customer_name' => (string) ($terminal['customer_name'] ?? 'Walk-in'),
                'order_type' => 'Retail',
                'status' => (string) ($terminal['status'] ?? 'idle'),
                'is_payment_mode' => ($terminal['status'] ?? '') === 'payment',
                'items' => [],
                'item_count' => 0,
                'subtotal' => round((float) ($terminal['total'] ?? 0), 2),
                'discount' => 0,
                'vat' => 0,
                'total' => round((float) ($terminal['total'] ?? 0), 2),
                'success' => null,
                'updated_at' => (string) ($terminal['updated_at'] ?? ''),
            ];
        }

        return $states;
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function listTerminals(): array
    {
        /** @var array<string, array<string, mixed>> $registry */
        $registry = Cache::get(self::REGISTRY_KEY, []);
        $rows = [];

        foreach ($registry as $terminalId => $meta) {
            /** @var array<string, mixed>|null $state */
            $state = Cache::get($this->terminalStateKey($terminalId));
            $online = $this->isOnline($state ?? $meta);

            if (! $online) {
                continue;
            }

            $cashierUsername = (string) ($meta['cashier_username'] ?? '');
            if ($cashierUsername === '') {
                $cashierUsername = $this->resolveCashierUsername([
                    'cashier_id' => (int) ($state['cashier_id'] ?? 0),
                ]);
            }

            $status = (string) ($state['status'] ?? $meta['status'] ?? 'idle');
            $total = round((float) ($state['total'] ?? $meta['total'] ?? 0), 2);
            $normalized = $this->normalizeMonitorState([
                'status' => $status,
                'items' => is_array($state['items'] ?? null) ? $state['items'] : [],
                'item_count' => (int) ($state['item_count'] ?? 0),
                'total' => $total,
                'subtotal' => round((float) ($state['subtotal'] ?? $total), 2),
            ]);
            $status = (string) ($normalized['status'] ?? $status);
            $total = round((float) ($normalized['total'] ?? $total), 2);

            $rows[] = [
                'terminal_id' => $terminalId,
                'terminal_label' => (string) ($meta['terminal_label'] ?? $terminalId),
                'register_code' => (string) ($meta['register_code'] ?? $meta['terminal_label'] ?? $terminalId),
                'cashier_name' => (string) ($meta['cashier_name'] ?? 'Cashier'),
                'cashier_username' => $cashierUsername,
                'branch_name' => (string) ($meta['branch_name'] ?? 'Main Branch'),
                'status' => $status,
                'customer_name' => (string) ($state['customer_name'] ?? $meta['customer_name'] ?? ''),
                'total' => $total,
                'online' => true,
                'updated_at' => (string) ($state['updated_at'] ?? $meta['updated_at'] ?? ''),
            ];
        }

        $rows = $this->dedupeTerminalsByCashier($rows);

        usort($rows, static function (array $a, array $b) {
            $onlineCmp = ($b['online'] <=> $a['online']);
            if ($onlineCmp !== 0) {
                return $onlineCmp;
            }

            $nameCmp = strcasecmp((string) $a['cashier_name'], (string) $b['cashier_name']);
            if ($nameCmp !== 0) {
                return $nameCmp;
            }

            return strcmp((string) $b['updated_at'], (string) $a['updated_at']);
        });

        return $rows;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function upsertRegistry(string $terminalId, array $payload): void
    {
        /** @var array<string, array<string, mixed>> $registry */
        $registry = Cache::get(self::REGISTRY_KEY, []);

        $next = [
            'terminal_id' => $terminalId,
            'terminal_label' => (string) ($payload['terminal_label'] ?? $terminalId),
            'register_code' => (string) ($payload['register_code'] ?? $payload['terminal_label'] ?? $terminalId),
            'cashier_name' => (string) ($payload['cashier_name'] ?? 'Cashier'),
            'cashier_username' => $this->resolveCashierUsername($payload),
            'branch_name' => (string) ($payload['branch_name'] ?? 'Main Branch'),
            'customer_name' => (string) ($payload['customer_name'] ?? ''),
            'status' => (string) ($payload['status'] ?? 'idle'),
            'total' => round((float) ($payload['total'] ?? 0), 2),
            'updated_at' => (string) ($payload['updated_at'] ?? now()->toIso8601String()),
        ];

        $previous = $registry[$terminalId] ?? null;
        if (is_array($previous) && $this->registryEntryEquals($previous, $next)) {
            $registry[$terminalId] = $next;
            Cache::put(self::REGISTRY_KEY, $registry, self::REGISTRY_TTL_SECONDS);

            return;
        }

        $registry[$terminalId] = $next;
        Cache::put(self::REGISTRY_KEY, $registry, self::REGISTRY_TTL_SECONDS);
        $this->bumpRevision();
    }

    /**
     * @param  array<string, mixed>  $previous
     * @param  array<string, mixed>  $next
     */
    private function registryEntryEquals(array $previous, array $next): bool
    {
        foreach ([
            'terminal_label',
            'register_code',
            'cashier_name',
            'cashier_username',
            'branch_name',
            'customer_name',
            'status',
            'total',
        ] as $key) {
            if (($previous[$key] ?? null) != ($next[$key] ?? null)) {
                return false;
            }
        }

        return true;
    }

    private function bumpRevision(): void
    {
        Cache::put(
            self::REVISION_KEY,
            substr(md5((string) microtime(true).random_int(0, PHP_INT_MAX)), 0, 16),
            self::REGISTRY_TTL_SECONDS,
        );
    }

    /**
     * @param  array<string, mixed>|null  $existing
     * @param  array<string, mixed>  $next
     */
    private function monitorStateEquals(?array $existing, array $next): bool
    {
        if ($existing === null) {
            return false;
        }

        return $this->monitorStateSignature($existing)
            === $this->monitorStateSignature($next);
    }

    /**
     * @param  array<string, mixed>  $state
     */
    private function monitorStateSignature(array $state): string
    {
        return hash('sha256', json_encode([
            'status' => $state['status'] ?? 'idle',
            'customer_name' => $state['customer_name'] ?? '',
            'item_count' => (int) ($state['item_count'] ?? 0),
            'subtotal' => round((float) ($state['subtotal'] ?? 0), 2),
            'discount' => round((float) ($state['discount'] ?? 0), 2),
            'vat' => round((float) ($state['vat'] ?? 0), 2),
            'total' => round((float) ($state['total'] ?? 0), 2),
            'items' => $state['items'] ?? [],
            'success' => $state['success'] ?? null,
            'is_payment_mode' => (bool) ($state['is_payment_mode'] ?? false),
        ], JSON_THROW_ON_ERROR));
    }

    private function pruneStaleTerminals(): void
    {
        /** @var array<string, array<string, mixed>> $registry */
        $registry = Cache::get(self::REGISTRY_KEY, []);
        if ($registry === []) {
            return;
        }

        $changed = false;

        foreach (array_keys($registry) as $terminalId) {
            /** @var array<string, mixed>|null $state */
            $state = Cache::get($this->terminalStateKey($terminalId));
            $row = is_array($state) ? $state : $registry[$terminalId];

            if ($this->isRecent($row)) {
                continue;
            }

            unset($registry[$terminalId]);
            Cache::forget($this->terminalStateKey($terminalId));
            Cache::forget($this->terminalSuccessKey($terminalId));
            $changed = true;
        }

        if (! $changed) {
            return;
        }

        Cache::put(self::REGISTRY_KEY, $registry, self::REGISTRY_TTL_SECONDS);
        $this->bumpRevision();
    }

    /**
     * @param  array<string, mixed>|null  $row
     */
    private function isOnline(?array $row): bool
    {
        if ($row === null) {
            return false;
        }

        return $this->isRecent($row);
    }

    /**
     * @param  array<string, mixed>  $row
     */
    private function isRecent(array $row): bool
    {
        $updatedAt = (string) ($row['updated_at'] ?? '');
        if ($updatedAt === '') {
            return false;
        }

        try {
            $timestamp = Carbon::parse($updatedAt)->utc()->getTimestamp();

            return abs(now()->utc()->getTimestamp() - $timestamp) <= self::ONLINE_SECONDS;
        } catch (\Throwable) {
            return false;
        }
    }

    /**
     * @param  array<string, mixed>  $state
     * @return array<string, mixed>
     */
    private function normalizeMonitorState(array $state): array
    {
        $status = (string) ($state['status'] ?? 'idle');
        $items = is_array($state['items'] ?? null) ? $state['items'] : [];
        $itemCount = (int) ($state['item_count'] ?? count($items));
        $total = round((float) ($state['total'] ?? 0), 2);

        if (
            in_array($status, ['cart', 'payment'], true)
            && $itemCount <= 0
            && count($items) === 0
        ) {
            $state['status'] = 'idle';
            $state['is_payment_mode'] = false;
            $state['items'] = [];
            $state['item_count'] = 0;
            $state['subtotal'] = 0;
            $state['discount'] = 0;
            $state['vat'] = 0;
            $state['total'] = 0;
        }

        return $state;
    }

    /**
     * @param  array<string, mixed>|null  $state
     * @return array<string, mixed>|null
     */
    private function hydrateSuccessState(string $terminalId, ?array $state): ?array
    {
        if ($state === null) {
            return null;
        }

        if ((string) ($state['status'] ?? '') !== 'success') {
            return $state;
        }

        if (is_array($state['success'] ?? null) && $state['success'] !== []) {
            return $state;
        }

        /** @var array<string, mixed>|null $cachedSuccess */
        $cachedSuccess = Cache::get($this->terminalSuccessKey($terminalId));
        if (! is_array($cachedSuccess) || $cachedSuccess === []) {
            return $state;
        }

        $state['success'] = $cachedSuccess;

        return $state;
    }

    private function terminalStateKey(string $terminalId): string
    {
        return 'pos_monitor:terminal:'.$terminalId;
    }

    private function terminalSuccessKey(string $terminalId): string
    {
        return 'pos_monitor:success:'.$terminalId;
    }

    private function watcherKey(int $userId): string
    {
        return 'pos_monitor:watcher:'.$userId;
    }

    private function watcherTerminalKey(int $userId): string
    {
        return 'pos_monitor:watcher_terminal:'.$userId;
    }

    private function cashierIdFromTerminalId(string $terminalId): int
    {
        if (preg_match('/-u(\d+)(?:-|$)/', $terminalId, $matches) === 1) {
            return (int) $matches[1];
        }

        return 0;
    }

    private function retireOtherCashierTerminals(int $cashierId, string $activeTerminalId): void
    {
        if ($cashierId <= 0) {
            return;
        }

        /** @var array<string, array<string, mixed>> $registry */
        $registry = Cache::get(self::REGISTRY_KEY, []);
        $changed = false;

        foreach (array_keys($registry) as $terminalId) {
            if ($terminalId === $activeTerminalId) {
                continue;
            }

            if ($this->cashierIdFromTerminalId($terminalId) !== $cashierId) {
                continue;
            }

            unset($registry[$terminalId]);
            Cache::forget($this->terminalStateKey($terminalId));
            Cache::forget($this->terminalSuccessKey($terminalId));
            $changed = true;
        }

        if (! $changed) {
            return;
        }

        Cache::put(self::REGISTRY_KEY, $registry, self::REGISTRY_TTL_SECONDS);
        $this->bumpRevision();
    }

    /**
     * @param  array<int, array<string, mixed>>  $rows
     * @return array<int, array<string, mixed>>
     */
    private function dedupeTerminalsByCashier(array $rows): array
    {
        $bestByCashier = [];
        $withoutCashier = [];

        foreach ($rows as $row) {
            $cashierId = $this->cashierIdFromTerminalId((string) ($row['terminal_id'] ?? ''));
            if ($cashierId <= 0) {
                $withoutCashier[] = $row;

                continue;
            }

            $existing = $bestByCashier[$cashierId] ?? null;
            if ($existing === null || $this->terminalRowRank($row) > $this->terminalRowRank($existing)) {
                $bestByCashier[$cashierId] = $row;
            }
        }

        return array_merge($withoutCashier, array_values($bestByCashier));
    }

    /**
     * @param  array<string, mixed>  $row
     */
    private function terminalRowRank(array $row): int
    {
        $rank = (bool) ($row['online'] ?? false) ? 1_000_000_000 : 0;
        $updatedAt = (string) ($row['updated_at'] ?? '');

        try {
            $rank += Carbon::parse($updatedAt)->timestamp;
        } catch (\Throwable) {
        }

        return $rank;
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  array<string, mixed>  $existing
     */
    private function resolveCashierUsername(array $payload, array $existing = []): string
    {
        $username = trim((string) ($payload['cashier_username'] ?? $existing['cashier_username'] ?? ''));
        if ($username !== '') {
            return $username;
        }

        $cashierId = (int) ($payload['cashier_id'] ?? $existing['cashier_id'] ?? 0);

        return $this->usernameForUser($cashierId);
    }

    private function usernameForUser(int $userId): string
    {
        if ($userId <= 0) {
            return '';
        }

        static $cache = [];

        if (array_key_exists($userId, $cache)) {
            return $cache[$userId];
        }

        try {
            if (! Schema::hasTable('users')) {
                return $cache[$userId] = '';
            }

            $row = DB::selectOne(
                'SELECT username, email FROM users WHERE id = ? LIMIT 1',
                [$userId],
            );

            if ($row === null) {
                return $cache[$userId] = '';
            }

            $username = trim((string) ($row->username ?? ''));
            if ($username !== '') {
                return $cache[$userId] = $username;
            }

            $email = trim((string) ($row->email ?? ''));
            if ($email !== '' && str_contains($email, '@')) {
                return $cache[$userId] = explode('@', $email, 2)[0];
            }
        } catch (\Throwable) {
            return $cache[$userId] = '';
        }

        return $cache[$userId] = '';
    }
}
