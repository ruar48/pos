<?php

namespace App\Http\Middleware;

use App\Support\PosApiToken as Tokens;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Identifies the tablet API caller from its sign-in token.
 *
 * Before this, every pos_app endpoint took "who is calling" from an
 * actor_user_id in the request, so anyone could act as any user (including
 * an admin). With a valid "Authorization: Bearer <token>" the token's user
 * replaces whatever user id the request carried. Requests without a token
 * pass through unchanged until config('pos.require_token') is switched on.
 */
class PosApiToken
{
    /** Reachable without signing in even when tokens are required. */
    private const PUBLIC_PATHS = [
        'pos_app/login.php',
        'pos_app/forgot_password.php',
        'pos_app/product_image.php',
        'pos_app/health',
    ];

    public function handle(Request $request, Closure $next): Response
    {
        if ($request->isMethod('OPTIONS')) {
            return $next($request);
        }

        $token = (string) $request->bearerToken();
        $isPublic = $request->is(...self::PUBLIC_PATHS);

        if ($token !== '') {
            $user = Tokens::resolve($token);
            if ($user === null && $isPublic) {
                // An expired token must never stop the tablet from signing
                // in again.
                return $next($request);
            }
            if ($user === null) {
                return response()->json([
                    'success' => false,
                    'message' => 'Your session has expired. Please sign in again.',
                    'code' => 'token_invalid',
                ], 401);
            }

            // The token decides who is acting - drop any id the client sent.
            $request->merge(['actor_user_id' => $user['id']]);
            $request->query->set('actor_user_id', (string) $user['id']);
            $request->headers->set('X-User-Id', (string) $user['id']);
            $request->attributes->set('pos_token_user', $user);

            return $next($request);
        }

        if (config('pos.require_token') && ! $isPublic) {
            return response()->json([
                'success' => false,
                'message' => 'Please sign in again to continue.',
                'code' => 'token_required',
            ], 401);
        }

        return $next($request);
    }
}
