<?php

namespace App\Support;

use Illuminate\Support\Carbon;

class BusinessDay
{
    /**
     * @return array{0: string, 1: string, 2: Carbon, 3: Carbon}
     */
    public static function rangeFor(string $businessDate, bool $capEndAtNow = false): array
    {
        $timezone = self::timezone();
        $start = Carbon::parse($businessDate, $timezone)
            ->setTime(self::resetHour(), 0, 0);
        $end = $start->copy()->addDay()->subSecond();

        if ($capEndAtNow && self::isCurrent($businessDate)) {
            $now = self::now();
            if ($now->lessThan($end)) {
                $end = $now;
            }
        }

        return [
            PosDateTime::toDatabaseLocal($start),
            PosDateTime::toDatabaseLocal($end),
            $start,
            $end,
        ];
    }

    public static function currentDate(?Carbon $moment = null): string
    {
        return self::dateForMoment($moment ?? self::now());
    }

    public static function dateForMoment(Carbon $moment): string
    {
        $moment = $moment->copy()->timezone(self::timezone());

        if ((int) $moment->hour < self::resetHour()) {
            return $moment->copy()->subDay()->format('Y-m-d');
        }

        return $moment->format('Y-m-d');
    }

    public static function isCurrent(string $businessDate): bool
    {
        return $businessDate === self::currentDate();
    }

    public static function now(): Carbon
    {
        return Carbon::now(self::timezone());
    }

    public static function timezone(): string
    {
        return (string) config('app.timezone', 'Asia/Manila');
    }

    public static function resetHour(): int
    {
        return max(0, min(23, (int) config('app.business_day_reset_hour', 5)));
    }
}
