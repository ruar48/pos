<?php

namespace App\Http\Middleware;

use App\Support\PosApiLogger;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;
use Throwable;

class LogPosApiRequests
{
    /**
     * @param  Closure(Request): Response  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        PosApiLogger::info('request.start', PosApiLogger::requestContext($request));

        if ((int) $request->header('Content-Length') > 0 && strlen((string) $request->getContent()) === 0) {
            PosApiLogger::warning('request.empty_body_with_content_length', [
                'hint' => 'PHP may have discarded POST data. Check post_max_size and upload_tmp_dir.',
                'php' => PosApiLogger::phpEnvironmentContext(),
            ]);
        }

        try {
            $response = $next($request);
        } catch (Throwable $throwable) {
            PosApiLogger::error('request.exception', PosApiLogger::requestContext($request), $throwable);
            throw $throwable;
        }

        $context = [
            'status' => $response->getStatusCode(),
            'path' => $request->path(),
            'method' => $request->method(),
        ];

        if ($response->getStatusCode() >= 400) {
            PosApiLogger::warning('request.failed', $context + [
                'response_preview' => substr((string) $response->getContent(), 0, 500),
            ]);
        } else {
            PosApiLogger::info('request.completed', $context);
        }

        return $response;
    }
}
