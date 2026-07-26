<?php

namespace App\Support;

use Throwable;

class PosApiExceptionMessage
{
    public const GENERIC = 'Something went wrong. Please try again or contact support.';

    public static function forClient(Throwable $throwable): string
    {
        return self::sanitizeMessage($throwable->getMessage(), true);
    }

    public static function sanitizeMessage(string $message, bool $forceGeneric = false): string
    {
        $message = trim($message);
        if ($message === '') {
            return self::GENERIC;
        }

        foreach ([
            'Server error: ',
            'Failed to load transaction report: ',
            'Could not save image: ',
        ] as $prefix) {
            if (str_starts_with($message, $prefix)) {
                $message = trim(substr($message, strlen($prefix)));
            }
        }

        if (self::isTechnicalMessage($message)) {
            return self::friendlyMessageFor($message);
        }

        if ($forceGeneric) {
            return self::GENERIC;
        }

        return $message;
    }

    public static function isTechnicalMessage(string $message): bool
    {
        $patterns = [
            '/SQLSTATE/i',
            '/General error:\s*\d+/i',
            '/Connection:\s*mysql/i',
            '/Host:\s*[\d.]+/i',
            '/Port:\s*\d+/i',
            '/Database:\s*\w+/i',
            '/\bSQL:\s/i',
            '/INSERT INTO/i',
            '/UPDATE\s+`/i',
            '/SELECT\s+/i',
            '/PDOException/i',
            '/QueryException/i',
            "/doesn't have a default value/i",
            '/Duplicate entry/i',
            '/foreign key constraint/i',
            '/stack trace/i',
            '/\.php on line \d+/i',
            '/Undefined (array key|index|variable)/i',
        ];

        foreach ($patterns as $pattern) {
            if (preg_match($pattern, $message)) {
                return true;
            }
        }

        return false;
    }

    public static function friendlyMessageFor(string $message): string
    {
        if (preg_match("/doesn't have a default value|1364/i", $message)) {
            return 'We could not complete this action. Please ask your administrator to check the server database setup.';
        }

        if (preg_match('/Duplicate entry/i', $message)) {
            return 'This record already exists. Please refresh and try again.';
        }

        if (preg_match('/foreign key constraint/i', $message)) {
            return 'Related data is missing or was removed. Please refresh and try again.';
        }

        if (preg_match('/Could not save image|upload/i', $message)) {
            return 'Could not save the image. Please try again or contact support.';
        }

        if (preg_match('/SQLSTATE|Connection:\s*mysql|INSERT INTO|UPDATE `/i', $message)) {
            return 'We could not save your changes. Please try again or contact support.';
        }

        return self::GENERIC;
    }
}
