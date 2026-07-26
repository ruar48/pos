<?php



namespace App\Http\Controllers\Pos;



use App\Http\Controllers\Api\Pos\CategoryController;

use App\Http\Controllers\Api\Pos\ProductController;

use App\Http\Controllers\Controller;

use App\Services\Pos\ProductImportExportService;

use App\Support\PosHelpers;

use Illuminate\Http\JsonResponse;

use Illuminate\Http\Request;

use Inertia\Inertia;

use Inertia\Response;

use Symfony\Component\HttpFoundation\StreamedResponse;



class ItemsPageController extends Controller

{

    public function index(): Response

    {

        return Inertia::render('pos/items');

    }



    public function sheet(): Response

    {

        return Inertia::render('pos/items-sheet');

    }



    public function categories(Request $request): JsonResponse

    {

        return app(CategoryController::class)->handle($request);

    }



    public function storeCategory(Request $request): JsonResponse

    {

        return app(CategoryController::class)->handle($request);

    }



    public function updateCategory(Request $request): JsonResponse

    {

        return app(CategoryController::class)->handle($request);

    }



    public function products(Request $request): JsonResponse

    {

        return app(ProductController::class)->handle($request);

    }



    public function storeProduct(Request $request): JsonResponse

    {

        return app(ProductController::class)->handle($request);

    }



    public function updateProduct(Request $request): JsonResponse

    {

        return app(ProductController::class)->handle($request);

    }



    public function deleteProduct(Request $request): JsonResponse
    {
        return app(ProductController::class)->handle($request);
    }



    public function exportProducts(): JsonResponse

    {

        $rows = app(ProductImportExportService::class)->exportRows();



        return response()->json([

            'success' => true,

            'headers' => ProductImportExportService::EXPORT_HEADERS,

            'rows' => $rows,

        ]);

    }



    public function importProducts(Request $request): JsonResponse
    {
        @set_time_limit(300);
        @ini_set('max_execution_time', '300');

        $request->validate([
            'file' => ['required', 'file', 'mimes:csv,txt,xlsx,xls', 'max:20480'],
        ]);

        $file = $request->file('file');
        $path = $file?->getRealPath();
        if ($path === false || $path === null) {
            return response()->json([
                'success' => false,
                'message' => 'Could not read uploaded file',
            ], 400);
        }

        $extension = strtolower((string) $file->getClientOriginalExtension());

        try {
            $result = app(ProductImportExportService::class)->importFromFile(
                $path,
                $extension !== '' ? $extension : 'csv',
                PosHelpers::currentActorId($request),
            );
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'Import failed: '.$e->getMessage(),
            ], 500);
        }

        return response()->json([
            'success' => true,
            'message' => sprintf(
                'Import complete: %d created, %d updated, %d skipped',
                $result['created'],
                $result['updated'],
                $result['skipped'],
            ),
            'data' => $result,
        ]);
    }
}

