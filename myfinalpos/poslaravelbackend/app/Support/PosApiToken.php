<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Tablet sign-in tokens (pos_api_tokens). The plain token is returned once
 * at login and only its SHA-256 hash is stored.
 */
class PosApiToken
{
    public static function available(): bool
    {
        return Schema::hasTable('pos_api_tokens');
    }

    public static function issue(int $userId, ?string $deviceName = null): ?string
    {
        if (! self::available()) {
            return null;
        }

        $token = Str::random(64);
        DB::table('pos_api_tokens')->insert([
            'user_id' => $userId,
            'token_hash' => hash('sha256', $token),
            'device_name' => $deviceName !== null ? mb_substr($deviceName, 0, 120) : null,
            'last_used_at' => now(),
            'created_at' => now(),
        ]);

        return $token;
    }

    /**
     * The active user behind a token, or null when the token is unknown,
     * idle for too long, or its user was deactivated or can no longer sign in.
     *
     * @return array{id: int, role: string}|null
     */
    public static function resolve(string $token): ?array
    {
        if (! self::available() || strlen($token) < 32) {
            return null;
        }

        $row = DB::selectOne(
            'SELECT t.id AS token_id, t.last_used_at, t.expires_at, u.id, u.role'
            .(Schema::hasColumn('users', 'status') ? ', u.status' : ', 1 AS status')
            .' FROM pos_api_tokens t
             INNER JOIN users u ON u.id = t.user_id
             WHERE t.token_hash = ?
             LIMIT 1',
            [hash('sha256', $token)],
        );

        if (! $row) {
            return null;
        }

        $idleDays = max(1, (int) config('pos.token_idle_days', 30));
        $lastUsed = $row->last_used_at ? \Illuminate\Support\Carbon::parse($row->last_used_at) : null;
        $expired = ($row->expires_at !== null && now()->greaterThan($row->expires_at))
            || ($lastUsed !== null && $lastUsed->lt(now()->subDays($idleDays)));

        if ($expired
            || (int) ($row->status ?? 1) !== 1
            || ! PosHelpers::canLogin((string) ($row->role ?? ''))) {
            DB::table('pos_api_tokens')->where('id', $row->token_id)->delete();

            return null;
        }

        // Touch at most once a minute to keep writes low.
        if ($lastUsed === null || $lastUsed->lt(now()->subMinute())) {
            DB::table('pos_api_tokens')->where('id', $row->token_id)->update(['last_used_at' => now()]);
        }

        return ['id' => (int) $row->id, 'role' => (string) $row->role];
    }

    public static function revoke(string $token): void
    {
        if (self::available() && $token !== '') {
            DB::table('pos_api_tokens')->where('token_hash', hash('sha256', $token))->delete();
        }
    }

    public static function revokeAllForUser(int $userId): void
    {
        if (self::available()) {
            DB::table('pos_api_tokens')->where('user_id', $userId)->delete();
        }
    }
}
