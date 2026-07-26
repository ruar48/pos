<?php

namespace App\Services\Pos;

use App\Support\AppSettingsRevision;
use App\Support\CatalogStockRevision;

class PosCatalogSyncService
{
    /**
     * Long-poll until catalog stock or app settings revision changes.
     *
     * @return array{
     *     changed: bool,
     *     stock_revision: string,
     *     settings_revision: string,
     *     stock_changed: bool,
     *     settings_changed: bool
     * }
     */
    public function watch(?string $stockRevision, ?string $settingsRevision): array
    {
        @set_time_limit(0);

        $holdSeconds = 25.0;
        $deadline = microtime(true) + $holdSeconds;
        $stockRevision = $stockRevision ?? '';
        $settingsRevision = $settingsRevision ?? '';

        do {
            $stock = CatalogStockRevision::current();
            $settings = AppSettingsRevision::current();

            $stockChanged = $stockRevision === '' || ! hash_equals($stock, $stockRevision);
            $settingsChanged = $settingsRevision === '' || ! hash_equals($settings, $settingsRevision);

            if ($stockChanged || $settingsChanged) {
                return [
                    'changed' => true,
                    'stock_revision' => $stock,
                    'settings_revision' => $settings,
                    'stock_changed' => $stockChanged,
                    'settings_changed' => $settingsChanged,
                ];
            }

            usleep(500000);
        } while (microtime(true) < $deadline);

        return [
            'changed' => false,
            'stock_revision' => $stock,
            'settings_revision' => $settings,
            'stock_changed' => false,
            'settings_changed' => false,
        ];
    }
}
