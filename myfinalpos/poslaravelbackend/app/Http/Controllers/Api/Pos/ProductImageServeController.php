<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\ProductImageStorage;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

class ProductImageServeController extends Controller
{
    public function show(Request $request): BinaryFileResponse|\Illuminate\Http\Response
    {
        if ($request->isMethod('OPTIONS')) {
            return response('', 204);
        }

        $filename = basename((string) $request->query('file', ''));
        if ($filename === '' || $filename === '.' || $filename === '..') {
            abort(404);
        }

        $path = ProductImageStorage::resolveStoredPath($filename);
        if ($path === null) {
            abort(404);
        }

        return response()->file($path, [
            'Content-Type' => mime_content_type($path) ?: 'application/octet-stream',
            'Cache-Control' => 'public, max-age=86400',
            'Access-Control-Allow-Origin' => '*',
            'Cross-Origin-Resource-Policy' => 'cross-origin',
        ]);
    }
}
