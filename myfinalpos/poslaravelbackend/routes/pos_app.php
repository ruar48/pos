<?php

use App\Http\Controllers\Api\Pos\AccountingSummaryController;
use App\Http\Controllers\Api\Pos\AttendanceController;
use App\Http\Controllers\Api\Pos\AuditLogController;
use App\Http\Controllers\Api\Pos\AuthController;
use App\Http\Controllers\Api\Pos\BranchController;
use App\Http\Controllers\Api\Pos\CategoryController;
use App\Http\Controllers\Api\Pos\CouponController;
use App\Http\Controllers\Api\Pos\CustomerController;
use App\Http\Controllers\Api\Pos\FaceProfileController;
use App\Http\Controllers\Api\Pos\InventoryController;
use App\Http\Controllers\Api\Pos\InventoryReportController;
use App\Http\Controllers\Api\Pos\LoyaltyCardController;
use App\Http\Controllers\Api\Pos\LoyaltyPointLogController;
use App\Http\Controllers\Api\Pos\OrderController;
use App\Http\Controllers\Api\Pos\PosMonitorController;
use App\Http\Controllers\Api\Pos\OrderQueryController;
use App\Http\Controllers\Api\Pos\ProductController;
use App\Http\Controllers\Api\Pos\StaffPaymentController;
use App\Http\Controllers\Api\Pos\TransactionReportController;
use App\Http\Controllers\Api\Pos\UserController;
use App\Http\Controllers\Api\Pos\ProductImageServeController;
use App\Http\Controllers\Api\Pos\ProductImageUploadController;
use App\Http\Controllers\Api\Pos\RefundController;
use App\Http\Controllers\Api\Pos\RefundQueryController;
use App\Http\Controllers\Api\Pos\SettingsController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Agriculture POS tablet API (Flutter compatibility)
|--------------------------------------------------------------------------
| These routes mirror the legacy backend/pos_app/*.php filenames so the
| Flutter app can point API_BASE_URL to http://your-host/pos_app
*/

Route::match(['POST', 'OPTIONS'], 'login.php', [AuthController::class, 'login']);
Route::match(['POST', 'OPTIONS'], 'change_password.php', [AuthController::class, 'changePassword']);
Route::match(['POST', 'OPTIONS'], 'forgot_password.php', [AuthController::class, 'forgotPassword']);

Route::match(['GET', 'POST', 'PUT', 'OPTIONS'], 'categories.php', [CategoryController::class, 'handle']);
Route::match(['GET', 'POST', 'PUT', 'PATCH', 'OPTIONS'], 'items.php', [ProductController::class, 'handle']);
Route::match(['POST', 'OPTIONS'], 'upload_product_image.php', [ProductImageUploadController::class, 'handle']);
Route::match(['GET', 'OPTIONS'], 'product_image.php', [ProductImageServeController::class, 'show']);
Route::match(['GET', 'POST', 'OPTIONS'], 'inventory.php', [InventoryController::class, 'handle']);
Route::match(['GET', 'POST', 'OPTIONS'], 'inventory_report.php', [InventoryReportController::class, 'handle']);

Route::match(['GET', 'POST', 'OPTIONS'], 'customers.php', [CustomerController::class, 'handle']);
Route::match(['GET', 'POST', 'OPTIONS'], 'loyalty_cards.php', [LoyaltyCardController::class, 'handle']);
Route::match(['GET', 'OPTIONS'], 'loyalty_point_logs.php', [LoyaltyPointLogController::class, 'handle']);
Route::match(['GET', 'POST', 'OPTIONS'], 'coupons.php', [CouponController::class, 'handle']);
Route::match(['GET', 'POST', 'OPTIONS'], 'branches.php', [BranchController::class, 'handle']);
Route::match(['GET', 'POST', 'OPTIONS'], 'settings.php', [SettingsController::class, 'handle']);
Route::match(['GET', 'POST', 'OPTIONS'], 'monitor.php', [PosMonitorController::class, 'handle']);

Route::match(['GET', 'OPTIONS'], 'get_orders.php', [OrderQueryController::class, 'handle']);
Route::match(['GET', 'OPTIONS'], 'accounting_summary.php', [AccountingSummaryController::class, 'handle']);
Route::match(['GET', 'OPTIONS'], 'transaction_reports.php', [TransactionReportController::class, 'handle']);
Route::match(['GET', 'OPTIONS'], 'get_refunds.php', [RefundQueryController::class, 'handle']);
Route::match(['POST', 'OPTIONS'], 'orders.php', [OrderController::class, 'handle']);
Route::match(['POST', 'OPTIONS'], 'process_refund.php', [RefundController::class, 'handle']);

Route::match(['GET', 'POST', 'OPTIONS'], 'users.php', [UserController::class, 'handle']);
Route::match(['GET', 'POST', 'OPTIONS'], 'staff_payments.php', [StaffPaymentController::class, 'handle']);
Route::match(['GET', 'OPTIONS'], 'audit_logs.php', [AuditLogController::class, 'handle']);
Route::match(['GET', 'POST', 'OPTIONS'], 'attendance.php', [AttendanceController::class, 'handle']);
Route::match(['GET', 'POST', 'OPTIONS'], 'face_profiles.php', [FaceProfileController::class, 'handle']);
Route::get('health', function () {
    $database = config('database.connections.mysql.database');
    $connected = false;
    $error = null;

    try {
        \Illuminate\Support\Facades\DB::connection()->getPdo();
        $connected = true;
    } catch (\Throwable $e) {
        $error = $e->getMessage();
    }

    return response()->json([
        'success' => $connected,
        'message' => $connected
            ? 'Agriculture POS Laravel API is running'
            : 'API is up but database connection failed',
        'database' => $database,
        'database_connected' => $connected,
        'database_error' => $connected ? null : $error,
    ], $connected ? 200 : 503);
});
