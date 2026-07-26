<?php

namespace App\Support;

use Illuminate\Support\Facades\Cache;

class CashDrawerRevision
{
    private const TTL_SECONDS = 172800;

    public static function current(string $businessDate): string
    {
        return (string) Cache::get(self::key($businessDate), '');
    }

    public static function ensure(string $businessDate): string
    {
        $current = self::current($businessDate);
        if ($current !== '') {
            return $current;
        }

        return self::bump($businessDate);
    }

    public static function bump(?string $businessDate = null): string
    {
        $date = $businessDate ?? BusinessDay::currentDate();
        $revision = hash('sha256', $date.microtime(true).random_int(0, PHP_INT_MAX));
        Cache::put(self::key($date), $revision, self::TTL_SECONDS);

        return $revision;
    }

    private static function key(string $businessDate): string
    {
        return 'cash_drawer:revision:'.$businessDate;
    }
}
