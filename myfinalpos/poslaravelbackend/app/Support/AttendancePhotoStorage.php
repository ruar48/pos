<?php

namespace App\Support;

use Illuminate\Support\Str;

class AttendancePhotoStorage
{
    private const MAX_BYTES = 5_242_880; // 5 MB

    /** @var list<string> */
    private const ALLOWED_EXTENSIONS = ['jpg', 'jpeg', 'png', 'webp'];

    /**
     * @return array{image_url: string, public_url: string}
     */
    public static function saveBase64(string $base64, string $mimeType = 'image/jpeg'): array
    {
        if (str_contains($base64, ',')) {
            $base64 = substr($base64, (int) strrpos($base64, ',') + 1);
        }

        $binary = base64_decode($base64, true);
        if ($binary === false || $binary === '') {
            throw new \InvalidArgumentException('Invalid attendance photo. Try again.');
        }

        if (strlen($binary) > self::MAX_BYTES) {
            throw new \InvalidArgumentException('Attendance photo must be 5 MB or smaller');
        }

        $extension = self::detectExtension($binary, $mimeType);
        if ($extension === '') {
            throw new \InvalidArgumentException('Use a JPG, PNG, or WEBP photo');
        }

        $directory = public_path('uploads/attendance');
        if (! is_dir($directory) && ! @mkdir($directory, 0777, true) && ! is_dir($directory)) {
            throw new \RuntimeException('Could not create public/uploads/attendance folder.');
        }

        if (! is_writable($directory)) {
            throw new \RuntimeException('public/uploads/attendance is not writable.');
        }

        $filename = 'att_'.now()->format('YmdHis').'_'.Str::lower(Str::random(8)).'.'.$extension;
        $fullPath = $directory.DIRECTORY_SEPARATOR.$filename;

        if (@file_put_contents($fullPath, $binary) === false) {
            throw new \RuntimeException('Could not save attendance photo.');
        }

        $relativePath = '/uploads/attendance/'.$filename;

        return [
            'image_url' => $relativePath,
            'public_url' => url($relativePath),
        ];
    }

    public static function resolveStoredPath(string $filename): ?string
    {
        $safeName = basename($filename);
        if ($safeName === '' || $safeName === '.' || $safeName === '..') {
            return null;
        }

        $fullPath = public_path('uploads/attendance/'.$safeName);

        return is_file($fullPath) ? $fullPath : null;
    }

    public static function deleteByUrl(?string $photoUrl): bool
    {
        if ($photoUrl === null || trim($photoUrl) === '') {
            return false;
        }

        $filename = basename(parse_url($photoUrl, PHP_URL_PATH) ?: $photoUrl);
        $path = self::resolveStoredPath($filename);
        if ($path === null) {
            return false;
        }

        return @unlink($path);
    }

    /**
     * @return array{file_count: int, total_bytes: int, directory: string}
     */
    public static function storageStats(): array
    {
        $directory = public_path('uploads/attendance');
        $fileCount = 0;
        $totalBytes = 0;

        if (is_dir($directory)) {
            foreach (scandir($directory) ?: [] as $entry) {
                if ($entry === '.' || $entry === '..') {
                    continue;
                }
                $full = $directory.DIRECTORY_SEPARATOR.$entry;
                if (! is_file($full)) {
                    continue;
                }
                $fileCount++;
                $totalBytes += (int) filesize($full);
            }
        }

        return [
            'file_count' => $fileCount,
            'total_bytes' => $totalBytes,
            'directory' => 'uploads/attendance',
        ];
    }

    /**
     * Delete attendance selfie files older than (or all), and clear DB photo_url.
     *
     * @return array{deleted_files: int, cleared_rows: int, freed_bytes: int}
     */
    public static function purge(?\DateTimeInterface $olderThan = null, bool $all = false): array
    {
        $deletedFiles = 0;
        $clearedRows = 0;
        $freedBytes = 0;
        $keptUrls = [];

        if (\Illuminate\Support\Facades\Schema::hasTable('staff_attendance')
            && \Illuminate\Support\Facades\Schema::hasColumn('staff_attendance', 'photo_url')
        ) {
            $query = \Illuminate\Support\Facades\DB::table('staff_attendance')
                ->whereNotNull('photo_url')
                ->where('photo_url', '!=', '');

            if (! $all && $olderThan !== null) {
                $query->where('created_at', '<', $olderThan->format('Y-m-d H:i:s'));
            } elseif (! $all) {
                // Default: older than 30 days
                $query->where('created_at', '<', now()->subDays(30)->format('Y-m-d H:i:s'));
            }

            $rows = $query->get(['id', 'photo_url']);
            foreach ($rows as $row) {
                $url = (string) ($row->photo_url ?? '');
                $filename = basename(parse_url($url, PHP_URL_PATH) ?: $url);
                $path = self::resolveStoredPath($filename);
                if ($path !== null) {
                    $size = (int) filesize($path);
                    if (@unlink($path)) {
                        $deletedFiles++;
                        $freedBytes += $size;
                    }
                }
                \Illuminate\Support\Facades\DB::table('staff_attendance')
                    ->where('id', $row->id)
                    ->update(['photo_url' => null]);
                $clearedRows++;
            }

            // Remaining referenced photos should not be treated as orphans.
            $kept = \Illuminate\Support\Facades\DB::table('staff_attendance')
                ->whereNotNull('photo_url')
                ->where('photo_url', '!=', '')
                ->pluck('photo_url');
            foreach ($kept as $url) {
                $keptUrls[basename(parse_url((string) $url, PHP_URL_PATH) ?: (string) $url)] = true;
            }
        }

        // Remove orphan files on disk (not linked in DB).
        $directory = public_path('uploads/attendance');
        if (is_dir($directory)) {
            foreach (scandir($directory) ?: [] as $entry) {
                if ($entry === '.' || $entry === '..') {
                    continue;
                }
                if (isset($keptUrls[$entry])) {
                    continue;
                }
                // When not purging all, only delete orphan files older than cutoff by mtime.
                $full = $directory.DIRECTORY_SEPARATOR.$entry;
                if (! is_file($full)) {
                    continue;
                }
                if (! $all) {
                    $cutoff = $olderThan?->getTimestamp() ?? now()->subDays(30)->getTimestamp();
                    if (filemtime($full) >= $cutoff) {
                        continue;
                    }
                }
                $size = (int) filesize($full);
                if (@unlink($full)) {
                    $deletedFiles++;
                    $freedBytes += $size;
                }
            }
        }

        return [
            'deleted_files' => $deletedFiles,
            'cleared_rows' => $clearedRows,
            'freed_bytes' => $freedBytes,
        ];
    }

    private static function detectExtension(string $binary, string $mimeType): string
    {
        $normalizedMime = strtolower(trim(explode(';', $mimeType)[0]));
        $fromMime = match ($normalizedMime) {
            'image/jpeg', 'image/jpg', 'image/pjpeg' => 'jpg',
            'image/png', 'image/x-png' => 'png',
            'image/webp' => 'webp',
            default => '',
        };
        if ($fromMime !== '') {
            return $fromMime;
        }

        if (str_starts_with($binary, "\xFF\xD8\xFF")) {
            return 'jpg';
        }
        if (str_starts_with($binary, "\x89PNG\r\n\x1A\n")) {
            return 'png';
        }
        if (str_starts_with($binary, 'RIFF') && substr($binary, 8, 4) === 'WEBP') {
            return 'webp';
        }

        return '';
    }
}
