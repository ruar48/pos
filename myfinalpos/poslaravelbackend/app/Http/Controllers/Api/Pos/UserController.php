<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class UserController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        try {
            if ($request->isMethod('options')) {
                return $this->posSuccess();
            }

            if ($request->isMethod('get')) {
                $actorUserId = PosHelpers::optionalInt($request->query('actor_user_id'));
                PosHelpers::requireAdminActor($actorUserId);

                $rows = DB::select(
                    'SELECT u.*, b.name AS branch_name
                     FROM users u
                     LEFT JOIN branches b ON b.id = u.branch_id
                     ORDER BY u.full_name ASC',
                );

                return $this->posSuccess([
                    'data' => array_map(
                        fn ($row) => PosHelpers::userRowToArray((array) $row),
                        $rows,
                    ),
                ]);
            }

            if (! $request->isMethod('post')) {
                return $this->posError('Method not allowed', 405);
            }

            $body = $request->all();
            $action = strtolower(trim((string) ($body['action'] ?? 'create')));
            $actorUserId = PosHelpers::currentActorId($request, $body);
            $actor = PosHelpers::requireAdminActor($actorUserId);

            if ($action === 'toggle') {
                return $this->toggleUser($body, $actor);
            }

            if ($action === 'reset_password') {
                return $this->resetPassword($body, $actor);
            }

            if ($action === 'update') {
                return $this->updateUser($body, $actor);
            }

            return $this->createUser($body, $actor);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }

    /**
     * @param  array<string, mixed>  $actor
     */
    private function createUser(array $body, array $actor): JsonResponse
    {
        $fullName = trim((string) ($body['full_name'] ?? ''));
        $username = trim((string) ($body['username'] ?? ''));
        $email = trim((string) ($body['email'] ?? ''));
        $password = (string) ($body['password'] ?? '');
        $role = PosHelpers::normalizeStoredRole(trim((string) ($body['role'] ?? 'cashier')));
        $branchId = PosHelpers::optionalInt($body['branch_id'] ?? null);

        if ($fullName === '') {
            return $this->posError('Full name is required', 400);
        }

        if (! PosHelpers::isAllowedRole($role)) {
            return $this->posError('Role must be admin, cashier, or labor', 400);
        }

        if ($role === 'labor') {
            $generated = $this->generateLaborCredentials($fullName);
            $username = $generated['username'];
            $email = $generated['email'];
            $password = $generated['password'];
        } elseif ($username === '' || $email === '' || $password === '') {
            return $this->posError('Full name, username, email and password are required', 400);
        }

        $exists = DB::selectOne(
            'SELECT id FROM users WHERE username = ? OR email = ? LIMIT 1',
            [$username, $email],
        );
        if ($exists) {
            return $this->posError('Username or email already exists', 409);
        }

        DB::insert(
            'INSERT INTO users (full_name, username, email, password_hash, role, status, branch_id, created_at)
             VALUES (?, ?, ?, ?, ?, 1, ?, NOW())',
            [$fullName, $username, $email, password_hash($password, PASSWORD_BCRYPT), $role, $branchId],
        );

        $userId = (int) DB::getPdo()->lastInsertId();

        PosHelpers::insertAuditLog(
            (int) $actor['id'],
            'create',
            'users',
            'user',
            $userId,
            'Staff account created',
            ['full_name' => $fullName, 'role' => $role],
        );

        $row = DB::selectOne(
            'SELECT u.*, b.name AS branch_name FROM users u
             LEFT JOIN branches b ON b.id = u.branch_id WHERE u.id = ? LIMIT 1',
            [$userId],
        );

        return $this->posSuccess([
            'message' => $role === 'labor'
                ? 'Labor staff added (attendance only — no login)'
                : 'User created successfully',
            'data' => PosHelpers::userRowToArray((array) $row),
        ], 201);
    }

    /**
     * @param  array<string, mixed>  $actor
     */
    private function updateUser(array $body, array $actor): JsonResponse
    {
        $userId = (int) ($body['id'] ?? 0);
        if ($userId <= 0) {
            return $this->posError('User id is required', 400);
        }

        $existing = DB::selectOne('SELECT * FROM users WHERE id = ? LIMIT 1', [$userId]);
        if (! $existing) {
            return $this->posError('User not found', 404);
        }
        $existing = (array) $existing;

        $fullName = trim((string) ($body['full_name'] ?? $existing['full_name']));
        $username = trim((string) ($body['username'] ?? $existing['username']));
        $email = trim((string) ($body['email'] ?? $existing['email']));
        $role = PosHelpers::normalizeStoredRole(trim((string) ($body['role'] ?? $existing['role'])));

        if (! PosHelpers::isAllowedRole($role)) {
            return $this->posError('Role must be admin, cashier, or labor', 400);
        }

        if ($role === 'labor') {
            if ($username === '') {
                $username = $this->generateLaborCredentials($fullName)['username'];
            }
            if ($email === '') {
                $email = $this->generateLaborCredentials($fullName)['email'];
            }
        } elseif ($username === '' || $email === '') {
            return $this->posError('Username and email are required', 400);
        }

        $branchId = array_key_exists('branch_id', $body)
            ? PosHelpers::optionalInt($body['branch_id'])
            : ($existing['branch_id'] !== null ? (int) $existing['branch_id'] : null);

        $duplicate = DB::selectOne(
            'SELECT id FROM users WHERE (username = ? OR email = ?) AND id <> ? LIMIT 1',
            [$username, $email, $userId],
        );
        if ($duplicate) {
            return $this->posError('Username or email already exists', 409);
        }

        DB::update(
            'UPDATE users SET full_name = ?, username = ?, email = ?, role = ?, branch_id = ? WHERE id = ?',
            [$fullName, $username, $email, $role, $branchId, $userId],
        );

        PosHelpers::insertAuditLog(
            (int) $actor['id'],
            'update',
            'users',
            'user',
            $userId,
            'Staff account updated',
            ['full_name' => $fullName, 'role' => $role],
        );

        $row = DB::selectOne(
            'SELECT u.*, b.name AS branch_name FROM users u
             LEFT JOIN branches b ON b.id = u.branch_id WHERE u.id = ? LIMIT 1',
            [$userId],
        );

        return $this->posSuccess([
            'message' => 'User updated successfully',
            'data' => PosHelpers::userRowToArray((array) $row),
        ]);
    }

    /**
     * @param  array<string, mixed>  $actor
     */
    private function toggleUser(array $body, array $actor): JsonResponse
    {
        $userId = (int) ($body['id'] ?? 0);
        if ($userId <= 0) {
            return $this->posError('User id is required', 400);
        }

        $existing = DB::selectOne('SELECT * FROM users WHERE id = ? LIMIT 1', [$userId]);
        if (! $existing) {
            return $this->posError('User not found', 404);
        }

        $newStatus = ((int) ($existing->status ?? 1) === 1) ? 0 : 1;
        DB::update('UPDATE users SET status = ? WHERE id = ?', [$newStatus, $userId]);

        PosHelpers::insertAuditLog(
            (int) $actor['id'],
            $newStatus === 1 ? 'activate' : 'deactivate',
            'users',
            'user',
            $userId,
            $newStatus === 1 ? 'Staff account activated' : 'Staff account deactivated',
            ['full_name' => $existing->full_name],
        );

        $row = DB::selectOne(
            'SELECT u.*, b.name AS branch_name FROM users u
             LEFT JOIN branches b ON b.id = u.branch_id WHERE u.id = ? LIMIT 1',
            [$userId],
        );

        return $this->posSuccess([
            'message' => $newStatus === 1 ? 'User activated' : 'User deactivated',
            'data' => PosHelpers::userRowToArray((array) $row),
        ]);
    }

    /**
     * @param  array<string, mixed>  $actor
     */
    private function resetPassword(array $body, array $actor): JsonResponse
    {
        $userId = (int) ($body['id'] ?? 0);
        $password = (string) ($body['password'] ?? '');

        if ($userId <= 0 || $password === '') {
            return $this->posError('User id and password are required', 400);
        }

        $existing = DB::selectOne('SELECT id, full_name, role FROM users WHERE id = ? LIMIT 1', [$userId]);
        if (! $existing) {
            return $this->posError('User not found', 404);
        }

        if (PosHelpers::isLaborRole((string) ($existing->role ?? ''))) {
            return $this->posError('Labor staff do not use login passwords', 400);
        }

        DB::update(
            'UPDATE users SET password_hash = ? WHERE id = ?',
            [password_hash($password, PASSWORD_BCRYPT), $userId],
        );

        PosHelpers::insertAuditLog(
            (int) $actor['id'],
            'reset_password',
            'users',
            'user',
            $userId,
            'Staff password reset',
            ['full_name' => $existing->full_name],
        );

        return $this->posSuccess(['message' => 'Password reset successfully']);
    }

    /**
     * @return array{username: string, email: string, password: string}
     */
    private function generateLaborCredentials(string $fullName): array
    {
        $slug = preg_replace('/[^a-z0-9]+/', '_', strtolower($fullName)) ?: 'worker';
        $slug = trim($slug, '_');
        $unique = substr(str_replace('.', '', uniqid('', true)), -8);
        $username = "labor_{$slug}_{$unique}";
        $email = "labor+{$unique}@no-login.local";

        return [
            'username' => $username,
            'email' => $email,
            'password' => bin2hex(random_bytes(16)),
        ];
    }
}
