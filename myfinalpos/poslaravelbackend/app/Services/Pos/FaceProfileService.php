<?php

namespace App\Services\Pos;

use App\Support\PosHelpers;
use Illuminate\Support\Facades\DB;

class FaceProfileService
{
    public const DESCRIPTOR_LENGTH = 128;

    /** Stricter threshold when blocking duplicate enrollment (L2-normalized vectors). */
    public const DUPLICATE_THRESHOLD = 0.38;

    /** Verify threshold — multi-template min-distance improves same-person match. */
    public const VERIFY_THRESHOLD = 0.46;

    /** Minimum confidence % required to accept a verify result. */
    public const MIN_VERIFY_CONFIDENCE = 50;

    /** Best match must be this much closer than the runner-up. */
    public const MIN_MATCH_SEPARATION = 0.12;

    /**
     * @return array<string, mixed>
     */
    public function statusForUser(int $userId): array
    {
        if (! PosHelpers::tableExists('staff_face_profiles')) {
            return [
                'user_id' => $userId,
                'enrolled' => false,
                'confidence' => 0,
            ];
        }

        $row = DB::selectOne(
            'SELECT fp.user_id, fp.confidence_score, fp.enrolled_at
             FROM staff_face_profiles fp
             INNER JOIN users u ON u.id = fp.user_id
             WHERE fp.user_id = ? AND u.status = 1
             LIMIT 1',
            [$userId],
        );

        if (! $row) {
            return [
                'user_id' => $userId,
                'enrolled' => false,
                'confidence' => 0,
            ];
        }

        return [
            'user_id' => $userId,
            'enrolled' => true,
            'confidence' => (int) ($row->confidence_score ?? 0),
            'enrolled_at' => (string) ($row->enrolled_at ?? ''),
        ];
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function staffDirectory(): array
    {
        if (! PosHelpers::tableExists('users')) {
            return [];
        }

        $statusFilter = PosHelpers::columnExists('users', 'status')
            ? 'WHERE u.status = 1'
            : '';

        $rows = DB::select(
            "SELECT u.id, u.full_name, u.role
             FROM users u
             {$statusFilter}
             ORDER BY u.full_name ASC",
        );

        $enrolled = [];
        if (PosHelpers::tableExists('staff_face_profiles')) {
            foreach (DB::select('SELECT user_id, confidence_score FROM staff_face_profiles') as $profile) {
                $enrolled[(int) $profile->user_id] = (int) ($profile->confidence_score ?? 0);
            }
        }

        return array_map(static function (object $row) use ($enrolled): array {
            $userId = (int) $row->id;

            return [
                'user_id' => $userId,
                'full_name' => (string) ($row->full_name ?? ''),
                'role' => (string) ($row->role ?? ''),
                'enrolled' => array_key_exists($userId, $enrolled),
                'confidence' => $enrolled[$userId] ?? 0,
            ];
        }, $rows);
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function list(): array
    {
        if (! PosHelpers::tableExists('staff_face_profiles')) {
            return [];
        }

        $rows = DB::select(
            'SELECT fp.user_id, fp.enrolled_at, fp.confidence_score, u.full_name, u.role, u.status
             FROM staff_face_profiles fp
             INNER JOIN users u ON u.id = fp.user_id
             ORDER BY u.full_name ASC',
        );

        return array_map(static function (object $row): array {
            return [
                'user_id' => (int) $row->user_id,
                'full_name' => (string) ($row->full_name ?? ''),
                'role' => (string) ($row->role ?? ''),
                'status' => (int) ($row->status ?? 0),
                'enrolled_at' => (string) ($row->enrolled_at ?? ''),
                'confidence' => (int) ($row->confidence_score ?? 0),
            ];
        }, $rows);
    }

    /**
     * @param  list<float|int>|list<list<float|int>>  $descriptorInput  Single 128-d vector or list of templates (far/mid/close).
     * @return array<string, mixed>
     */
    public function enroll(int $userId, array $descriptorInput, int $actorUserId, ?int $confidence = null): array
    {
        if (! PosHelpers::tableExists('staff_face_profiles')) {
            throw new \RuntimeException('Face profiles are not ready. Run database migrations.');
        }

        $user = DB::selectOne('SELECT id, full_name, role, status FROM users WHERE id = ? LIMIT 1', [$userId]);
        if (! $user) {
            throw new \RuntimeException('Staff member not found.');
        }
        if ((int) ($user->status ?? 0) !== 1) {
            throw new \RuntimeException('Cannot enroll face for inactive staff.');
        }

        $templates = $this->parseEnrollmentInput($descriptorInput);
        $confidenceScore = max(0, min(100, (int) ($confidence ?? 0)));

        foreach ($templates as $template) {
            $duplicate = $this->findBestMatch(
                $template,
                $userId,
                self::DUPLICATE_THRESHOLD,
            );
            if ($duplicate !== null) {
                $name = (string) ($duplicate['full_name'] ?? 'another staff member');

                throw new \RuntimeException(
                    "This face is already enrolled for {$name}. Each person can only be linked to one staff account.",
                );
            }
        }

        DB::statement(
            'INSERT INTO staff_face_profiles (user_id, descriptor_json, confidence_score, enrolled_by, enrolled_at, updated_at)
             VALUES (?, ?, ?, ?, NOW(), NOW())
             ON DUPLICATE KEY UPDATE
                descriptor_json = VALUES(descriptor_json),
                confidence_score = VALUES(confidence_score),
                enrolled_by = VALUES(enrolled_by),
                updated_at = NOW()',
            [
                $userId,
                json_encode($templates, JSON_UNESCAPED_UNICODE),
                $confidenceScore,
                $actorUserId,
            ],
        );

        PosHelpers::insertAuditLog(
            $actorUserId,
            'upsert',
            'face_profile',
            'staff_face_profiles',
            $userId,
            'Staff face profile enrolled',
            ['user_id' => $userId, 'confidence' => $confidenceScore],
        );

        return [
            'user_id' => $userId,
            'full_name' => (string) ($user->full_name ?? ''),
            'role' => (string) ($user->role ?? ''),
            'enrolled_at' => now()->toIso8601String(),
            'confidence' => $confidenceScore,
        ];
    }

    /**
     * @param  list<float|int>  $descriptor
     * @return array<string, mixed>
     */
    public function verify(array $descriptor): array
    {
        if (! PosHelpers::tableExists('staff_face_profiles')) {
            throw new \RuntimeException('Face profiles are not ready.');
        }

        $probe = $this->prepareTemplate($descriptor);
        $ranked = $this->rankMatches($probe, null, self::VERIFY_THRESHOLD);

        if ($ranked['best'] === null) {
            return [
                'matched' => false,
                'message' => PosHelpers::tableExists('staff_face_profiles')
                    ? 'No matching face found.'
                    : 'No enrolled faces yet — enroll staff first.',
            ];
        }

        $match = $ranked['best'];

        if ($match['confidence'] < self::MIN_VERIFY_CONFIDENCE) {
            return [
                'matched' => false,
                'distance' => $match['distance'],
                'confidence' => $match['confidence'],
                'message' => 'Face match is not strong enough. Only the enrolled person can verify.',
            ];
        }

        if (
            $ranked['second'] !== null
            && ($ranked['second']['distance'] - $match['distance']) < self::MIN_MATCH_SEPARATION
        ) {
            return [
                'matched' => false,
                'distance' => $match['distance'],
                'confidence' => $match['confidence'],
                'message' => 'Face match is ambiguous. Re-enroll with 3 captures on web admin.',
            ];
        }

        return [
            'matched' => true,
            'user_id' => $match['user_id'],
            'full_name' => $match['full_name'],
            'role' => $match['role'],
            'distance' => $match['distance'],
            'confidence' => $match['confidence'],
        ];
    }

    /**
     * @param  list<float>  $probe
     * @return array{user_id: int, full_name: string, role: string, distance: float, confidence: int}|null
     */
    private function findBestMatch(
        array $probe,
        ?int $excludeUserId = null,
        float $threshold = self::DUPLICATE_THRESHOLD,
    ): ?array {
        $ranked = $this->rankMatches($probe, $excludeUserId, $threshold);

        return $ranked['best'];
    }

    /**
     * @return array{
     *     best: array{user_id: int, full_name: string, role: string, distance: float, confidence: int}|null,
     *     second: array{user_id: int, full_name: string, role: string, distance: float, confidence: int}|null
     * }
     */
    private function rankMatches(
        array $probe,
        ?int $excludeUserId = null,
        float $threshold = self::VERIFY_THRESHOLD,
    ): array
    {
        if (! PosHelpers::tableExists('staff_face_profiles')) {
            return ['best' => null, 'second' => null];
        }

        $rows = DB::select(
            'SELECT fp.user_id, fp.descriptor_json, u.full_name, u.role
             FROM staff_face_profiles fp
             INNER JOIN users u ON u.id = fp.user_id
             WHERE u.status = 1',
        );

        $candidates = [];

        foreach ($rows as $row) {
            $rowUserId = (int) $row->user_id;
            if ($excludeUserId !== null && $rowUserId === $excludeUserId) {
                continue;
            }

            $stored = json_decode((string) ($row->descriptor_json ?? '[]'), true);
            $templates = $this->parseStoredTemplates($stored);
            if ($templates === []) {
                continue;
            }

            $distance = $this->minDistanceToTemplates($probe, $templates);
            $candidates[] = [
                'user_id' => $rowUserId,
                'full_name' => (string) ($row->full_name ?? ''),
                'role' => (string) ($row->role ?? ''),
                'distance' => round($distance, 4),
                'confidence' => $this->distanceToConfidence($distance, $threshold),
            ];
        }

        if ($candidates === []) {
            return ['best' => null, 'second' => null];
        }

        usort($candidates, static fn (array $a, array $b): int => $a['distance'] <=> $b['distance']);

        $best = $candidates[0];
        if ($best['distance'] > $threshold) {
            return ['best' => null, 'second' => null];
        }

        return [
            'best' => $best,
            'second' => $candidates[1] ?? null,
        ];
    }

    public function remove(int $userId, int $actorUserId): void
    {
        if (! PosHelpers::tableExists('staff_face_profiles')) {
            return;
        }

        DB::delete('DELETE FROM staff_face_profiles WHERE user_id = ?', [$userId]);

        PosHelpers::insertAuditLog(
            $actorUserId,
            'delete',
            'face_profile',
            'staff_face_profiles',
            $userId,
            'Staff face profile removed',
            ['user_id' => $userId],
        );
    }

    public function distanceToConfidence(
        float $distance,
        float $threshold = self::VERIFY_THRESHOLD,
    ): int {
        return (int) max(0, min(100, round((1 - ($distance / $threshold)) * 100)));
    }

    /**
     * @param  list<float|int>|list<list<float|int>>  $input
     * @return list<list<float>>
     */
    private function parseEnrollmentInput(array $input): array
    {
        if ($input === []) {
            throw new \RuntimeException('Face descriptor is required.');
        }

        if (is_array($input[0] ?? null)) {
            $templates = [];
            foreach ($input as $item) {
                if (! is_array($item)) {
                    continue;
                }
                $templates[] = $this->prepareTemplate($item);
            }

            if ($templates === []) {
                throw new \RuntimeException('Invalid face descriptors.');
            }

            return $templates;
        }

        return [$this->prepareTemplate($input)];
    }

    /**
     * @return list<list<float>>
     */
    private function parseStoredTemplates(mixed $stored): array
    {
        if (! is_array($stored) || $stored === []) {
            return [];
        }

        if (isset($stored[0]) && is_numeric($stored[0])) {
            if (count($stored) !== self::DESCRIPTOR_LENGTH) {
                return [];
            }

            return [$this->l2Normalize(array_map('floatval', $stored))];
        }

        $templates = [];
        foreach ($stored as $item) {
            if (! is_array($item) || count($item) !== self::DESCRIPTOR_LENGTH) {
                continue;
            }

            $templates[] = $this->l2Normalize(array_map('floatval', $item));
        }

        return $templates;
    }

    /**
     * @param  list<float|int>  $descriptor
     * @return list<float>
     */
    private function normalizeDescriptor(array $descriptor): array
    {
        if (count($descriptor) !== self::DESCRIPTOR_LENGTH) {
            throw new \RuntimeException('Face descriptor must contain exactly '.self::DESCRIPTOR_LENGTH.' values.');
        }

        $normalized = [];
        foreach ($descriptor as $value) {
            if (! is_numeric($value)) {
                throw new \RuntimeException('Invalid face descriptor value.');
            }
            $normalized[] = (float) $value;
        }

        return $normalized;
    }

    /**
     * @param  list<float|int>  $descriptor
     * @return list<float>
     */
    private function prepareTemplate(array $descriptor): array
    {
        return $this->l2Normalize($this->normalizeDescriptor($descriptor));
    }

    /**
     * @param  list<float>  $vector
     * @return list<float>
     */
    private function l2Normalize(array $vector): array
    {
        $sum = 0.0;
        foreach ($vector as $value) {
            $sum += $value * $value;
        }

        $norm = sqrt($sum);
        if ($norm < 1e-10) {
            throw new \RuntimeException('Invalid face descriptor (zero magnitude).');
        }

        return array_map(static fn (float $value): float => $value / $norm, $vector);
    }

    /**
     * @param  list<float>  $probe
     * @param  list<list<float>>  $templates
     */
    private function minDistanceToTemplates(array $probe, array $templates): float
    {
        $best = PHP_FLOAT_MAX;

        foreach ($templates as $template) {
            $distance = $this->euclideanDistance($probe, $template);
            if ($distance < $best) {
                $best = $distance;
            }
        }

        return $best;
    }

    /**
     * @param  list<float>  $a
     * @param  list<float>  $b
     */
    private function euclideanDistance(array $a, array $b): float
    {
        $sum = 0.0;
        for ($i = 0; $i < self::DESCRIPTOR_LENGTH; $i++) {
            $delta = $a[$i] - $b[$i];
            $sum += $delta * $delta;
        }

        return sqrt($sum);
    }
}
