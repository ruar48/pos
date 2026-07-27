<?php

namespace App\Providers;

use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Date;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\ServiceProvider;
use Illuminate\Validation\Rules\Password;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->bind(
            \Illuminate\Foundation\Console\ServeCommand::class,
            \App\Console\PosServeCommand::class,
        );
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->ensurePosUploadPaths();
        $this->configureDefaults();
    }

    protected function ensurePosUploadPaths(): void
    {
        $directory = public_path('uploads/products');
        if (! is_dir($directory)) {
            @mkdir($directory, 0777, true);
        }
    }

    /**
     * Configure default behaviors for production-ready applications.
     */
    protected function configureDefaults(): void
    {
        // Older MySQL/MariaDB servers cap index keys at ~767-1000 bytes;
        // utf8mb4 varchar(255) unique/primary keys exceed that. 191 chars
        // keeps every indexed string column under the limit regardless.
        Schema::defaultStringLength(191);

        $timezone = (string) config('app.timezone', 'Asia/Manila');
        date_default_timezone_set($timezone);

        Date::use(CarbonImmutable::class);

        DB::prohibitDestructiveCommands(
            app()->isProduction(),
        );

        $mysqlTimezone = config('database.connections.mysql.timezone');
        if (is_string($mysqlTimezone) && $mysqlTimezone !== '') {
            try {
                DB::statement('SET time_zone = ?', [$mysqlTimezone]);
            } catch (\Throwable) {
                // Ignore when MySQL timezone tables are unavailable.
            }
        }

        Password::defaults(fn (): ?Password => app()->isProduction()
            ? Password::min(12)
                ->mixedCase()
                ->letters()
                ->numbers()
                ->symbols()
                ->uncompromised()
            : null,
        );
    }
}
