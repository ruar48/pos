<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class BranchController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        try {
            if (! PosHelpers::tableExists('branches')) {
                return $this->posSuccess([
                    'data' => [[
                        'id' => 1,
                        'name' => 'Main Branch',
                        'code' => 'MAIN',
                        'location' => 'Head Office',
                        'is_active' => 1,
                    ]],
                ]);
            }

            if ($request->isMethod('get')) {
                $includeInactive = ! empty($request->query('include_inactive'));
                $actorUserId = PosHelpers::optionalInt($request->query('actor_user_id'));

                if ($includeInactive) {
                    PosHelpers::requireAdminActor($actorUserId);
                }

                $geoCols = PosHelpers::columnExists('branches', 'latitude')
                    ? ', latitude, longitude, geofence_radius_km'
                    : '';
                $sql = 'SELECT id, name, code, location, is_active, created_at'.$geoCols.' FROM branches';
                if (! $includeInactive) {
                    $sql .= ' WHERE is_active = 1';
                }
                $sql .= ' ORDER BY id ASC';

                $rows = DB::select($sql);

                return $this->posSuccess([
                    'data' => array_map(
                        fn ($row) => PosHelpers::branchRowToArray((array) $row),
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
                $branchId = (int) ($body['id'] ?? 0);
                if ($branchId <= 0) {
                    return $this->posError('Branch id is required', 400);
                }

                $existing = DB::selectOne('SELECT * FROM branches WHERE id = ? LIMIT 1', [$branchId]);
                if (! $existing) {
                    return $this->posError('Branch not found', 404);
                }
                $existing = (array) $existing;

                $newStatus = ((int) ($existing['is_active'] ?? 1) === 1) ? 0 : 1;
                DB::update('UPDATE branches SET is_active = ? WHERE id = ?', [$newStatus, $branchId]);

                PosHelpers::insertAuditLog(
                    (int) $actor['id'],
                    $newStatus === 1 ? 'activate' : 'deactivate',
                    'branches',
                    'branch',
                    $branchId,
                    'Branch status updated',
                    ['name' => $existing['name'], 'is_active' => $newStatus],
                );

                $updated = DB::selectOne('SELECT * FROM branches WHERE id = ? LIMIT 1', [$branchId]);

                return $this->posSuccess([
                    'message' => $newStatus === 1 ? 'Branch activated' : 'Branch deactivated',
                    'data' => PosHelpers::branchRowToArray((array) $updated),
                ]);
            }

            if ($action === 'update') {
                $branchId = (int) ($body['id'] ?? 0);
                if ($branchId <= 0) {
                    return $this->posError('Branch id is required', 400);
                }

                $existing = DB::selectOne('SELECT * FROM branches WHERE id = ? LIMIT 1', [$branchId]);
                if (! $existing) {
                    return $this->posError('Branch not found', 404);
                }
                $existing = (array) $existing;

                $name = trim((string) ($body['name'] ?? $existing['name']));
                $code = trim((string) ($body['code'] ?? (string) ($existing['code'] ?? '')));
                $location = trim((string) ($body['location'] ?? (string) ($existing['location'] ?? '')));
                $latitude = array_key_exists('latitude', $body)
                    ? ($body['latitude'] === null || $body['latitude'] === '' ? null : round((float) $body['latitude'], 7))
                    : ($existing['latitude'] ?? null);
                $longitude = array_key_exists('longitude', $body)
                    ? ($body['longitude'] === null || $body['longitude'] === '' ? null : round((float) $body['longitude'], 7))
                    : ($existing['longitude'] ?? null);
                $radiusKm = array_key_exists('geofence_radius_km', $body)
                    ? round((float) $body['geofence_radius_km'], 2)
                    : (float) ($existing['geofence_radius_km'] ?? 2.0);

                if ($name === '') {
                    return $this->posError('Branch name is required', 400);
                }

                if (PosHelpers::columnExists('branches', 'latitude')) {
                    DB::update(
                        'UPDATE branches SET name = ?, code = ?, location = ?, latitude = ?, longitude = ?, geofence_radius_km = ? WHERE id = ?',
                        [$name, $code !== '' ? $code : null, $location !== '' ? $location : null, $latitude, $longitude, $radiusKm, $branchId],
                    );
                } else {
                    DB::update(
                        'UPDATE branches SET name = ?, code = ?, location = ? WHERE id = ?',
                        [$name, $code !== '' ? $code : null, $location !== '' ? $location : null, $branchId],
                    );
                }

                PosHelpers::insertAuditLog(
                    (int) $actor['id'],
                    'update',
                    'branches',
                    'branch',
                    $branchId,
                    'Branch updated',
                    ['name' => $name],
                );

                $updated = DB::selectOne('SELECT * FROM branches WHERE id = ? LIMIT 1', [$branchId]);

                return $this->posSuccess([
                    'message' => 'Branch updated successfully',
                    'data' => PosHelpers::branchRowToArray((array) $updated),
                ]);
            }

            $name = trim((string) ($body['name'] ?? ''));
            $code = trim((string) ($body['code'] ?? ''));
            $location = trim((string) ($body['location'] ?? ''));

            if ($name === '') {
                return $this->posError('Branch name is required', 400);
            }

            DB::insert(
                'INSERT INTO branches (name, code, location, is_active) VALUES (?, ?, ?, 1)',
                [$name, $code ?: null, $location ?: null],
            );

            $branchId = (int) DB::getPdo()->lastInsertId();

            PosHelpers::insertAuditLog(
                (int) $actor['id'],
                'create',
                'branches',
                'branch',
                $branchId,
                'Branch created',
                ['name' => $name],
            );

            return $this->posSuccess([
                'message' => 'Branch created successfully',
                'data' => [
                    'id' => $branchId,
                    'name' => $name,
                    'code' => $code,
                    'location' => $location,
                    'is_active' => 1,
                ],
            ], 201);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
