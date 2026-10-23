<?php

// Browsers only: the Android/Windows tablet app is not subject to CORS, and
// the admin web is same-origin. Allowing every origin ('*') let any website a
// staff member visited call the (token-less) POS API from their browser.
// Set CORS_ALLOWED_ORIGINS to a comma-separated list to allow others, or "*"
// to restore the old behaviour.
$appUrl = rtrim((string) env('APP_URL', 'http://localhost'), '/');
$host = parse_url($appUrl, PHP_URL_HOST) ?: 'localhost';
$scheme = parse_url($appUrl, PHP_URL_SCHEME) ?: 'https';

$configured = array_values(array_filter(array_map(
    'trim',
    explode(',', (string) env('CORS_ALLOWED_ORIGINS', '')),
)));

$defaultOrigins = array_values(array_unique([
    $appUrl,
    $scheme.'://'.(str_starts_with($host, 'www.') ? substr($host, 4) : 'www.'.$host),
]));

return [

    'paths' => ['pos_app/*', 'api/*'],

    'allowed_methods' => ['*'],

    'allowed_origins' => $configured !== [] ? $configured : $defaultOrigins,

    // Local development (flutter run -d chrome, Vite dev server).
    'allowed_origins_patterns' => $configured !== []
        ? []
        : ['#^https?://(localhost|127\.0\.0\.1|10\.0\.2\.2|192\.168\.\d+\.\d+)(:\d+)?$#'],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => false,

];
