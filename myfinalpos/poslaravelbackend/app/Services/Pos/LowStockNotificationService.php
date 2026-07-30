<?php

namespace App\Services\Pos;

use App\Mail\LowStockAlertMail;
use App\Support\PosApiLogger;
use App\Support\PosHelpers;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Schema;

class LowStockNotificationService
{
    public function afterStockChange(int $productId, int $previousStock, int $newStock): void
    {
        if ($productId <= 0 || $previousStock === $newStock) {
            return;
        }

        try {
            $this->evaluate($productId, $previousStock, $newStock);
        } catch (\Throwable $e) {
            PosApiLogger::warning('low_stock.notify.failed', [
                'product_id' => $productId,
                'previous_stock' => $previousStock,
                'new_stock' => $newStock,
                'message' => $e->getMessage(),
            ]);
        }
    }

    private function evaluate(int $productId, int $previousStock, int $newStock): void
    {
        if (! Schema::hasTable('products')) {
            return;
        }

        $columns = ['id', 'name', 'stock', 'reorder_level'];
        if (Schema::hasColumn('products', 'low_stock_notified_at')) {
            $columns[] = 'low_stock_notified_at';
        }

        $product = DB::table('products')
            ->where('id', $productId)
            ->first($columns);

        if (! $product) {
            return;
        }

        $reorderLevel = $this->effectiveReorderLevel((int) ($product->reorder_level ?? 0));
        $currentStock = (int) ($product->stock ?? $newStock);

        if ($currentStock > $reorderLevel) {
            if (Schema::hasColumn('products', 'low_stock_notified_at') && $product->low_stock_notified_at !== null) {
                DB::table('products')
                    ->where('id', $productId)
                    ->update(['low_stock_notified_at' => null]);
            }

            return;
        }

        if (
            Schema::hasColumn('products', 'low_stock_notified_at')
            && $product->low_stock_notified_at !== null
        ) {
            return;
        }

        if (! $this->isEnabled()) {
            return;
        }

        $recipients = $this->resolveRecipients();
        if ($recipients === []) {
            PosApiLogger::warning('low_stock.notify.no_recipients', [
                'product_id' => $productId,
            ]);

            return;
        }

        $storeName = $this->storeName();
        $payload = [
            'product_id' => $productId,
            'name' => (string) ($product->name ?? 'Product'),
            'stock' => $currentStock,
            'reorder_level' => $reorderLevel,
            'store_name' => $storeName,
        ];

        Mail::to($recipients)->send(new LowStockAlertMail($payload));

        if (Schema::hasColumn('products', 'low_stock_notified_at')) {
            DB::table('products')
                ->where('id', $productId)
                ->update(['low_stock_notified_at' => now()]);
        }

        PosApiLogger::info('low_stock.notify.sent', [
            'product_id' => $productId,
            'stock' => $currentStock,
            'reorder_level' => $reorderLevel,
            'recipient_count' => count($recipients),
        ]);
    }

    public function effectiveReorderLevel(int $reorderLevel): int
    {
        return $reorderLevel > 0 ? $reorderLevel : 5;
    }

    private function isEnabled(): bool
    {
        if (! PosHelpers::tableExists('app_settings')) {
            return true;
        }

        if (! PosHelpers::columnExists('app_settings', 'low_stock_email_enabled')) {
            return true;
        }

        $row = DB::selectOne(
            'SELECT low_stock_email_enabled FROM app_settings ORDER BY id ASC LIMIT 1',
        );

        return $row === null || (int) ($row->low_stock_email_enabled ?? 1) === 1;
    }

    /**
     * @return list<string>
     */
    private function resolveRecipients(): array
    {
        $configured = '';

        if (
            PosHelpers::tableExists('app_settings')
            && PosHelpers::columnExists('app_settings', 'low_stock_email_recipients')
        ) {
            $row = DB::selectOne(
                'SELECT low_stock_email_recipients FROM app_settings ORDER BY id ASC LIMIT 1',
            );
            $configured = trim((string) ($row->low_stock_email_recipients ?? ''));
        }

        $emails = $this->parseEmailList($configured);
        if ($emails !== []) {
            return $emails;
        }

        $envRecipients = trim((string) env('LOW_STOCK_ALERT_EMAIL', ''));
        $emails = $this->parseEmailList($envRecipients);
        if ($emails !== []) {
            return $emails;
        }

        $fromAddress = trim((string) config('mail.from.address', ''));
        if ($this->isDeliverableEmail($fromAddress)) {
            return [$fromAddress];
        }

        if (! PosHelpers::tableExists('users')) {
            return [];
        }

        $admin = DB::selectOne(
            'SELECT email FROM users
             WHERE status = 1 AND role = "admin" AND email IS NOT NULL AND email != ""
             ORDER BY id ASC
             LIMIT 1',
        );

        if ($admin && $this->isDeliverableEmail((string) $admin->email)) {
            return [(string) $admin->email];
        }

        $fallback = DB::selectOne(
            'SELECT email FROM users
             WHERE status = 1 AND email IS NOT NULL AND email != ""
             ORDER BY id ASC
             LIMIT 1',
        );

        if ($fallback && $this->isDeliverableEmail((string) $fallback->email)) {
            return [(string) $fallback->email];
        }

        return [];
    }

    private function isDeliverableEmail(string $email): bool
    {
        if (! filter_var($email, FILTER_VALIDATE_EMAIL)) {
            return false;
        }

        $lower = strtolower($email);

        if (
            str_ends_with($lower, '.local')
            || str_ends_with($lower, '.test')
            || str_ends_with($lower, '.invalid')
            || str_contains($lower, '@example.')
        ) {
            return false;
        }

        return true;
    }

    /**
     * @return list<string>
     */
    private function parseEmailList(string $value): array
    {
        if ($value === '') {
            return [];
        }

        $parts = preg_split('/[,;\s]+/', $value) ?: [];
        $emails = [];

        foreach ($parts as $part) {
            $email = trim($part);
            if ($email !== '' && filter_var($email, FILTER_VALIDATE_EMAIL)) {
                $emails[] = $email;
            }
        }

        return array_values(array_unique($emails));
    }

    private function storeName(): string
    {
        if (
            ! PosHelpers::tableExists('app_settings')
            || ! PosHelpers::columnExists('app_settings', 'receipt_store_json')
        ) {
            return (string) config('app.name', 'POS');
        }

        $raw = DB::table('app_settings')->orderBy('id')->value('receipt_store_json');
        if (! is_string($raw) || $raw === '') {
            return (string) config('app.name', 'POS');
        }

        $decoded = json_decode($raw, true);
        if (! is_array($decoded)) {
            return (string) config('app.name', 'POS');
        }

        $name = trim((string) ($decoded['store_name'] ?? ''));

        return $name !== '' ? $name : (string) config('app.name', 'POS');
    }
}
