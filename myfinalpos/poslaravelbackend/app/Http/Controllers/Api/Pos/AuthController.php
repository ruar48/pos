<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosApiToken;
use App\Support\PosHelpers;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Schema;

class AuthController extends Controller
{
    use PosApiResponse;

    public function login(Request $request): JsonResponse
    {
        $email = trim((string) $request->input('email', ''));
        $password = (string) $request->input('password', '');

        if ($email === '' || $password === '') {
            return $this->posError('Email and password are required', 400);
        }

        // Tablet login used to allow unlimited guesses (the web login is
        // already throttled by Fortify). Limit wrong passwords per account
        // and per IP; a successful login clears the account counter.
        $accountKey = 'pos-login:'.sha1(strtolower($email)).'|'.$request->ip();
        $ipKey = 'pos-login-ip:'.$request->ip();
        foreach ([[$accountKey, 10], [$ipKey, 50]] as [$key, $max]) {
            if (RateLimiter::tooManyAttempts($key, $max)) {
                $minutes = max(1, (int) ceil(RateLimiter::availableIn($key) / 60));

                return $this->posError(
                    "Too many failed sign-in attempts. Try again in {$minutes} minute(s).",
                    429,
                );
            }
        }

        if (! Schema::hasTable('users')) {
            return $this->posError(
                'POS database is not ready. Import backend/sql/agriculture_system.sql first.',
                503,
            );
        }

        $hasStatus = Schema::hasColumn('users', 'status');
        $statusColumn = $hasStatus ? ', status' : ', 1 AS status';

        $user = DB::selectOne(
            "SELECT id, full_name, username, email, password_hash, role {$statusColumn}
             FROM users
             WHERE email = ? OR username = ?
             LIMIT 1",
            [$email, $email],
        );

        if (! $user || ! password_verify($password, (string) $user->password_hash)) {
            RateLimiter::hit($accountKey, 300);
            RateLimiter::hit($ipKey, 300);

            return $this->posError('Invalid username or password', 401);
        }

        RateLimiter::clear($accountKey);

        if ($hasStatus && (int) ($user->status ?? 1) !== 1) {
            return $this->posError(
                'Your account is inactive. Contact an administrator.',
                403,
            );
        }

        if (! PosHelpers::canLogin((string) ($user->role ?? ''))) {
            return $this->posError(
                'This account type cannot sign in. Labor staff use attendance only.',
                403,
            );
        }

        // Sign-in token for newer tablet builds (older ones ignore it). The
        // tablet sends it on every request so the server knows who is acting.
        $token = PosApiToken::issue(
            (int) $user->id,
            trim((string) $request->input('device_name', '')) ?: null,
        );

        return $this->posSuccess([
            'message' => 'Login successful',
            'token' => $token,
            'user' => [
                'id' => (int) $user->id,
                'full_name' => $user->full_name,
                'username' => (string) ($user->username ?? ''),
                'email' => $user->email,
                'role' => $user->role,
            ],
        ]);
    }

    /** Signs this tablet out: its token stops working immediately. */
    public function logout(Request $request): JsonResponse
    {
        if ($request->isMethod('options')) {
            return $this->posSuccess();
        }

        PosApiToken::revoke((string) $request->bearerToken());

        return $this->posSuccess(['message' => 'Signed out']);
    }

    public function changePassword(Request $request): JsonResponse
    {
        try {
            if ($request->isMethod('options')) {
                return $this->posSuccess();
            }

            $body = $request->all();
            $actorUserId = PosHelpers::currentActorId($request, $body);
            $currentPassword = (string) ($body['current_password'] ?? '');
            $newPassword = (string) ($body['password'] ?? '');

            if ($actorUserId === null || $actorUserId <= 0) {
                return $this->posError('Authentication required', 401);
            }

            if ($currentPassword === '' || $newPassword === '') {
                return $this->posError('Current password and new password are required', 400);
            }

            if (strlen($newPassword) < 6) {
                return $this->posError('New password must be at least 6 characters', 400);
            }

            if (! Schema::hasTable('users')) {
                return $this->posError(
                    'POS database is not ready. Import backend/sql/agriculture_system.sql first.',
                    503,
                );
            }

            $user = DB::selectOne(
                'SELECT id, full_name, password_hash, role FROM users WHERE id = ? LIMIT 1',
                [$actorUserId],
            );

            if (! $user) {
                return $this->posError('User not found', 404);
            }

            if (PosHelpers::isLaborRole((string) ($user->role ?? ''))) {
                return $this->posError('Labor staff do not use login passwords', 400);
            }

            if (! PosHelpers::canLogin((string) ($user->role ?? ''))) {
                return $this->posError('This account type cannot change password', 403);
            }

            if (! password_verify($currentPassword, (string) $user->password_hash)) {
                return $this->posError('Current password is incorrect', 401);
            }

            DB::update(
                'UPDATE users SET password_hash = ? WHERE id = ?',
                [password_hash($newPassword, PASSWORD_BCRYPT), $actorUserId],
            );

            PosHelpers::insertAuditLog(
                $actorUserId,
                'change_password',
                'users',
                'user',
                $actorUserId,
                'Password changed',
                ['full_name' => $user->full_name],
            );

            return $this->posSuccess(['message' => 'Password changed successfully']);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }

    public function forgotPassword(Request $request): JsonResponse
    {
        try {
            if ($request->isMethod('options')) {
                return $this->posSuccess();
            }

            $identifier = trim((string) $request->input('email', ''));
            if ($identifier === '') {
                return $this->posError('Email is required', 400);
            }

            if (! Schema::hasTable('users')) {
                return $this->posError(
                    'POS database is not ready. Import backend/sql/agriculture_system.sql first.',
                    503,
                );
            }

            $user = DB::selectOne(
                'SELECT id, email, role, status FROM users WHERE email = ? OR username = ? LIMIT 1',
                [$identifier, $identifier],
            );

            $genericMessage = 'If that account exists, a reset link has been sent to its email.';

            if (
                ! $user
                || ! PosHelpers::canLogin((string) ($user->role ?? ''))
                || PosHelpers::isLaborRole((string) ($user->role ?? ''))
                || (Schema::hasColumn('users', 'status') && (int) ($user->status ?? 1) !== 1)
            ) {
                return $this->posSuccess(['message' => $genericMessage]);
            }

            $status = Password::sendResetLink(['email' => (string) $user->email]);

            if ($status === Password::RESET_LINK_SENT) {
                PosHelpers::insertAuditLog(
                    (int) $user->id,
                    'forgot_password',
                    'users',
                    'user',
                    (int) $user->id,
                    'Password reset link requested',
                    ['email' => $user->email],
                );

                return $this->posSuccess(['message' => $genericMessage]);
            }

            if ($status === Password::RESET_THROTTLED) {
                return $this->posError(
                    'Please wait before requesting another reset link.',
                    429,
                );
            }

            return $this->posSuccess(['message' => $genericMessage]);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
