<?php

/**
 * Runs before Laravel on every API request.
 */
$basePath = dirname(__DIR__);
$logFile = $basePath.DIRECTORY_SEPARATOR.'storage'.DIRECTORY_SEPARATOR.'logs'.DIRECTORY_SEPARATOR.'pos-api.log';

$bootstrapLog = static function (string $level, string $message, array $context = []) use ($logFile): void {
    $line = sprintf(
        "[%s] [%s] [BOOTSTRAP] %s %s\n",
        date('Y-m-d H:i:s'),
        strtoupper($level),
        $message,
        json_encode($context, JSON_UNESCAPED_SLASHES),
    );
    @file_put_contents($logFile, $line, FILE_APPEND);
};

if (! ob_get_level()) {
    ob_start();
}

@ini_set('display_errors', '0');
@ini_set('log_errors', '1');

$uploadDirectory = $basePath.DIRECTORY_SEPARATOR.'public'.DIRECTORY_SEPARATOR.'uploads'.DIRECTORY_SEPARATOR.'products';
if (! is_dir($uploadDirectory)) {
    @mkdir($uploadDirectory, 0777, true);
}

$tmpDirectory = $basePath.DIRECTORY_SEPARATOR.'storage'.DIRECTORY_SEPARATOR.'app'.DIRECTORY_SEPARATOR.'tmp';
if (! is_dir($tmpDirectory)) {
    @mkdir($tmpDirectory, 0777, true);
}

@ini_set('upload_tmp_dir', $tmpDirectory);

$bootstrapLog('info', 'php.bootstrap', [
    'post_max_size' => ini_get('post_max_size'),
    'upload_max_filesize' => ini_get('upload_max_filesize'),
    'upload_tmp_dir' => ini_get('upload_tmp_dir'),
    'content_length' => $_SERVER['CONTENT_LENGTH'] ?? null,
    'request_method' => $_SERVER['REQUEST_METHOD'] ?? null,
    'request_uri' => $_SERVER['REQUEST_URI'] ?? null,
    'upload_dir_writable' => is_writable($uploadDirectory),
    'tmp_dir_writable' => is_writable($tmpDirectory),
]);

if (isset($_SERVER['CONTENT_LENGTH']) && (int) $_SERVER['CONTENT_LENGTH'] > 0 && ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
    $postMaxBytes = 8 * 1024 * 1024;
    $postMaxRaw = ini_get('post_max_size');
    if (is_string($postMaxRaw) && $postMaxRaw !== '') {
        $unit = strtolower(substr($postMaxRaw, -1));
        $value = (float) $postMaxRaw;
        $postMaxBytes = match ($unit) {
            'g' => (int) ($value * 1024 * 1024 * 1024),
            'm' => (int) ($value * 1024 * 1024),
            'k' => (int) ($value * 1024),
            default => (int) $value,
        };
    }

    if ((int) $_SERVER['CONTENT_LENGTH'] > $postMaxBytes) {
        $bootstrapLog('warning', 'post.body_larger_than_post_max_size', [
            'content_length' => (int) $_SERVER['CONTENT_LENGTH'],
            'post_max_size' => ini_get('post_max_size'),
        ]);
    }
}
