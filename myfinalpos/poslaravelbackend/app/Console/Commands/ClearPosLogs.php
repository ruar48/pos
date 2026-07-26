<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;

class ClearPosLogs extends Command
{
    protected $signature = 'pos:clear-logs';

    protected $description = 'Remove laravel.log and pos-api.log from storage/logs';

    public function handle(): int
    {
        $files = [
            storage_path('logs/laravel.log'),
            storage_path('logs/pos-api.log'),
        ];

        $removed = 0;

        foreach ($files as $path) {
            if (! is_file($path)) {
                continue;
            }

            if (@unlink($path)) {
                $removed++;
                $this->line('Removed '.basename($path));
            } else {
                $this->warn('Could not remove '.basename($path));
            }
        }

        if ($removed === 0) {
            $this->info('No log files to remove.');
        } else {
            $this->info("Removed {$removed} log file(s).");
        }

        return self::SUCCESS;
    }
}
