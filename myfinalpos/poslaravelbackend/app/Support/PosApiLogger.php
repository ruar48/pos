<?php

namespace App\Support;

use Illuminate\Http\Request;
use Throwable;

class PosApiLogger
{
    public static function info(string $event, array $context = []): void
    {
        self::write('info', $event, $context);
    }

    public static function warning(string $event, array $context = []): void
    {
        self::write('warning', $event, $context);
    }

    public static function error(string $event, array $context = [], ?Throwable $throwable = null): void
    {
        if ($throwable !== null) {
            $context['exception_class'] = $throwable::class;
            $context['exception_message'] = $throwable->getMessage();
            $context['exception_file'] = $throwable->getFile();
            $context['exception_line'] = $throwable->getLine();
            $context['exception_trace'] = $throwable->getTraceAsString();
        }

        self::write('error', $event, $context);
    }

    /**
     * @return array<string, mixed>
     */
    public static function requestContext(Request $request): array
    {
        $rawBody = (string) $request->getContent();
        $imageBase64 = trim((string) $request->input('image_base64', ''));

        return [
            'method' => $request->method(),
            'path' => $request->path(),
            'ip' => $request->ip(),
            'content_length_header' => $request->header('Content-Length'),
            'raw_body_bytes' => strlen($rawBody),
            'content_type' => $request->header('Content-Type'),
            'post_max_size' => ini_get('post_max_size'),
            'upload_max_filesize' => ini_get('upload_max_filesize'),
            'upload_tmp_dir' => ini_get('upload_tmp_dir'),
            'display_errors' => ini_get('display_errors'),
            'memory_limit' => ini_get('memory_limit'),
            'has_image_base64_field' => $request->has('image_base64'),
            'image_base64_chars' => strlen($imageBase64),
            'image_filename' => $request->input('image_filename'),
            'image_mime_type' => $request->input('image_mime_type'),
            'product_name' => $request->input('name'),
            'product_category' => $request->input('category'),
            'upload_dir_exists' => is_dir(public_path('uploads/products')),
            'upload_dir_writable' => is_writable(public_path('uploads/products')),
            'tmp_dir_exists' => is_dir(storage_path('app/tmp')),
            'tmp_dir_writable' => is_writable(storage_path('app/tmp')),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public static function phpEnvironmentContext(): array
    {
        return [
            'post_max_size' => ini_get('post_max_size'),
            'upload_max_filesize' => ini_get('upload_max_filesize'),
            'upload_tmp_dir' => ini_get('upload_tmp_dir'),
            'display_errors' => ini_get('display_errors'),
            'memory_limit' => ini_get('memory_limit'),
            'public_uploads_exists' => is_dir(public_path('uploads/products')),
            'public_uploads_writable' => is_writable(public_path('uploads/products')),
            'storage_tmp_exists' => is_dir(storage_path('app/tmp')),
            'storage_tmp_writable' => is_writable(storage_path('app/tmp')),
        ];
    }

    public static function bootstrap(string $event, array $context = []): void
    {
        $line = sprintf(
            "[%s] [%s] %s %s\n",
            date('Y-m-d H:i:s'),
            strtoupper($event),
            $context['message'] ?? 'bootstrap',
            json_encode($context, JSON_UNESCAPED_SLASHES),
        );

        @file_put_contents(storage_path('logs/pos-api.log'), $line, FILE_APPEND);
    }

    private static function write(string $level, string $event, array $context): void
    {
        try {
            logger()->channel('pos_api')->log($level, "[POS] {$event}", $context);
        } catch (Throwable) {
            $line = sprintf(
                "[%s] [%s] [POS] %s %s\n",
                date('Y-m-d H:i:s'),
                strtoupper($level),
                $event,
                json_encode($context, JSON_UNESCAPED_SLASHES),
            );

            @file_put_contents(storage_path('logs/pos-api.log'), $line, FILE_APPEND);
        }
    }
}
