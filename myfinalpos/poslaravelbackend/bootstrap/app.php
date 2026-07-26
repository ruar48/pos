<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Middleware\HandleInertiaRequests;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
        then: function (): void {
            Route::middleware(['api', \App\Http\Middleware\LogPosApiRequests::class])
                ->prefix('pos_app')
                ->group(base_path('routes/pos_app.php'));
        },
    )
    ->withCommands([
        \App\Console\PosServeCommand::class,
    ])
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->web(append: [
            HandleInertiaRequests::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('pos_app/*')
                || $request->is('api/*')
                || ($request->is('pos/*') && $request->expectsJson()),
        );

        $exceptions->reportable(function (\Throwable $throwable): void {
            $request = request();
            if ($request === null || ! $request->is('pos_app/*')) {
                return;
            }

            \App\Support\PosApiLogger::error(
                'exception.reported',
                \App\Support\PosApiLogger::requestContext($request),
                $throwable,
            );
        });

        $exceptions->render(function (\Throwable $throwable, Request $request) {
            if (! $request->is('pos_app/*')) {
                return null;
            }

            if ($throwable instanceof \Illuminate\Http\Exceptions\HttpResponseException) {
                return null;
            }

            if ($throwable instanceof \Illuminate\Validation\ValidationException) {
                return null;
            }

            $status = $throwable instanceof \Symfony\Component\HttpKernel\Exception\HttpExceptionInterface
                ? $throwable->getStatusCode()
                : 500;

            if ($status < 500) {
                return null;
            }

            \App\Support\PosApiLogger::error(
                'pos_api.unhandled',
                \App\Support\PosApiLogger::requestContext($request),
                $throwable,
            );

            return response()->json([
                'success' => false,
                'message' => \App\Support\PosApiExceptionMessage::forClient($throwable),
            ], $status);
        });
    })->create();
