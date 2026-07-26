<?php

namespace App\Support;

use Illuminate\Support\Carbon;

/**
 * Order timestamps are stored as Philippines local wall clock (Asia/Manila).
 * MySQL connection uses DB_TIMEZONE=+08:00 so phpMyAdmin matches register time.
 */
class PosDateTime
{
    public static function fromDatabase(?string $value): ?Carbon
    {
        if ($value === null || trim($value) === '') {
            return null;
        }

        return Carbon::parse(trim($value), BusinessDay::timezone());
    }

    public static function formatDate(?string $value): string
    {
        $moment = self::fromDatabase($value);

        return $moment ? $moment->format('d M Y') : '—';
    }

    public static function formatTime(?string $value): string
    {
        $moment = self::fromDatabase($value);

        return $moment ? strtolower($moment->format('g:ia')) : '—';
    }

    public static function formatIso(?string $value): string
    {
        $moment = self::fromDatabase($value);

        return $moment ? $moment->toIso8601String() : '';
    }

    /**
     * Format a Manila-local moment for MySQL comparisons (orders use wall-clock +08:00).
     */
    public static function toDatabaseLocal(Carbon $moment): string
    {
        return $moment->copy()->timezone(BusinessDay::timezone())->format('Y-m-d H:i:s');
    }

    /**
     * @deprecated Orders are stored as local wall clock; prefer toDatabaseLocal().
     */
    public static function toDatabaseUtc(Carbon $moment): string
    {
        return self::toDatabaseLocal($moment);
    }

    /**
     * Parse sold_at from the POS tablet (ISO-8601 UTC or legacy local clock).
     */
    public static function parseSoldAtFromClient(string $raw): ?Carbon
    {
        $raw = trim($raw);
        if ($raw === '') {
            return null;
        }

        if (is_numeric($raw) && (float) $raw > 0) {
            $epoch = (int) round((float) $raw);

            if ($epoch > 1_000_000_000_000) {
                return Carbon::createFromTimestampMs($epoch, 'UTC');
            }

            return Carbon::createFromTimestamp($epoch, 'UTC');
        }

        $hasOffset = (bool) preg_match('/Z$/i', $raw)
            || preg_match('/[+-]\d{2}:?\d{2}$/', $raw);

        if ($hasOffset) {
            return Carbon::parse($raw)->utc();
        }

        return Carbon::parse($raw, BusinessDay::timezone())->utc();
    }
}
