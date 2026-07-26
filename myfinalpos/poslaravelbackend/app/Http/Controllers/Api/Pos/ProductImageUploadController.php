<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\ProductImageStorage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ProductImageUploadController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        if ($request->isMethod('OPTIONS')) {
            return $this->posSuccess();
        }

        if (! $request->isMethod('POST')) {
            return $this->posError('Method not allowed', 405);
        }

        $base64 = trim((string) $request->input('image_base64', ''));
        if ($base64 === '') {
            return $this->posError('Image data is required', 400);
        }

        try {
            $saved = ProductImageStorage::saveBase64(
                $base64,
                (string) $request->input('filename', 'upload.jpg'),
                (string) $request->input('mime_type', 'image/jpeg'),
            );
        } catch (\InvalidArgumentException $e) {
            return $this->posError($e->getMessage(), 400);
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }

        return $this->posSuccess([
            'message' => 'Image uploaded successfully',
            'data' => $saved,
        ], 201);
    }
}
