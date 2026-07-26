<?php

namespace App\Support;

use Illuminate\Support\Str;

class ProductImageStorage
{
    private const MAX_BYTES = 5_242_880; // 5 MB

    /** @var list<string> */
    private const ALLOWED_EXTENSIONS = ['jpg', 'jpeg', 'png', 'webp', 'gif'];

    /**
     * @return array{image_url: string, public_url: string}
     */
    public static function saveBase64(
        string $base64,
        string $filename = 'upload.jpg',
        string $mimeType = 'image/jpeg',
    ): array {
        if (str_contains($base64, ',')) {
            $base64 = substr($base64, (int) strrpos($base64, ',') + 1);
        }

        $binary = base64_decode($base64, true);
        if ($binary === false || $binary === '') {
            throw new \InvalidArgumentException('Invalid image data. Try a smaller photo.');
        }

        if (strlen($binary) > self::MAX_BYTES) {
            throw new \InvalidArgumentException('Image must be 5 MB or smaller');
        }

        $extension = self::detectExtension($binary, $filename, $mimeType);
        if ($extension === '') {
            throw new \InvalidArgumentException('Use a JPG, PNG, WEBP, or GIF image');
        }

        return self::writeBinary($binary, $extension);
    }

    /**
     * @return array{image_url: string, public_url: string}
     */
    public static function writeBinary(string $binary, string $extension): array
    {
        if ($binary === '') {
            throw new \InvalidArgumentException('Empty image data');
        }

        $directory = public_path('uploads/products');
        if (! is_dir($directory) && ! @mkdir($directory, 0777, true) && ! is_dir($directory)) {
            throw new \RuntimeException('Could not create public/uploads/products folder.');
        }

        if (! is_writable($directory)) {
            throw new \RuntimeException('public/uploads/products is not writable.');
        }

        $filename = 'prod_'.now()->format('YmdHis').'_'.Str::lower(Str::random(8)).'.'.$extension;
        $fullPath = $directory.DIRECTORY_SEPARATOR.$filename;

        if (@file_put_contents($fullPath, $binary) === false) {
            PosApiLogger::error('product.image.write_failed', [
                'target_path' => $fullPath,
                'directory_writable' => is_writable($directory),
                'binary_bytes' => strlen($binary),
                'extension' => $extension,
            ]);

            throw new \RuntimeException('Could not save image file.');
        }

        PosApiLogger::info('product.image.write_success', [
            'target_path' => $fullPath,
            'binary_bytes' => strlen($binary),
            'extension' => $extension,
        ]);

        $relativePath = '/uploads/products/'.$filename;

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

        $paths = [
            public_path('uploads/products/'.$safeName),
            storage_path('app/product-images/'.$safeName),
        ];

        foreach ($paths as $fullPath) {
            if (is_file($fullPath)) {
                return $fullPath;
            }
        }

        return null;
    }

    private static function detectExtension(
        string $binary,
        string $filename,
        string $mimeType,
    ): string {
        $fromMeta = self::resolveExtension(
            strtolower(pathinfo($filename, PATHINFO_EXTENSION)),
            $mimeType,
        );
        if ($fromMeta !== '') {
            return $fromMeta;
        }

        if (function_exists('finfo_open')) {
            $finfo = finfo_open(FILEINFO_MIME_TYPE);
            if ($finfo !== false) {
                $detected = finfo_buffer($finfo, $binary) ?: '';
                finfo_close($finfo);
                $fromFinfo = self::resolveExtension('', $detected);
                if ($fromFinfo !== '') {
                    return $fromFinfo;
                }
            }
        }

        if (str_starts_with($binary, "\xFF\xD8\xFF")) {
            return 'jpg';
        }
        if (str_starts_with($binary, "\x89PNG\r\n\x1A\n")) {
            return 'png';
        }
        if (str_starts_with($binary, 'GIF87a') || str_starts_with($binary, 'GIF89a')) {
            return 'gif';
        }
        if (str_starts_with($binary, 'RIFF') && substr($binary, 8, 4) === 'WEBP') {
            return 'webp';
        }

        return '';
    }

    private static function resolveExtension(string $extension, string $mimeType): string
    {
        if ($extension === 'jpeg') {
            $extension = 'jpg';
        }

        if (in_array($extension, self::ALLOWED_EXTENSIONS, true)) {
            return $extension === 'jpeg' ? 'jpg' : $extension;
        }

        $normalizedMime = strtolower(trim(explode(';', $mimeType)[0]));

        return match ($normalizedMime) {
            'image/jpeg', 'image/jpg', 'image/pjpeg' => 'jpg',
            'image/png', 'image/x-png' => 'png',
            'image/webp' => 'webp',
            'image/gif' => 'gif',
            'application/octet-stream' => '',
            default => '',
        };
    }
}
