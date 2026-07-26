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
