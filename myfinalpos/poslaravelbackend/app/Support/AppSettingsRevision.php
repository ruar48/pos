<?php

namespace App\Support;

use Illuminate\Support\Facades\Cache;

class AppSettingsRevision
{
    private const KEY = 'pos_app:settings_revision';

    public static function current(): string
    {
        return (string) Cache::get(self::KEY, '0');
    }

    public static function bump(): string
    {
        $revision = substr(md5((string) microtime(true).random_int(0, PHP_INT_MAX)), 0, 16);
        Cache::forever(self::KEY, $revision);

        return $revision;
    }
}
