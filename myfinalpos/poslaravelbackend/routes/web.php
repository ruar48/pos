<?php

use App\Http\Controllers\DashboardPageController;
use App\Http\Controllers\Pos\InventoryPageController;
use App\Http\Controllers\Pos\ItemsPageController;
use App\Http\Controllers\Pos\LoyaltyPageController;
use App\Http\Controllers\Pos\OverviewPageController;
use App\Http\Controllers\Pos\PosMonitorPageController;
use App\Http\Controllers\Pos\PromotionsPageController;
use App\Http\Controllers\Pos\ReportsPageController;
use App\Http\Controllers\Pos\StaffPageController;
use App\Http\Controllers\Pos\CashDrawerPageController;
use App\Http\Controllers\Pos\TransactionsPageController;
use App\Support\AttendancePhotoStorage;
use App\Support\ProductImageStorage;
use Illuminate\Support\Facades\Route;

Route::get('/uploads/products/{filename}', function (string $filename) {
    $path = ProductImageStorage::resolveStoredPath($filename);
    if ($path === null) {
        abort(404);
    }

    return response()->file($path, [
        'Access-Control-Allow-Origin' => '*',
        'Cross-Origin-Resource-Policy' => 'cross-origin',
    ]);
})->where('filename', '[A-Za-z0-9._-]+');

Route::get('/uploads/attendance/{filename}', function (string $filename) {
    $path = AttendancePhotoStorage::resolveStoredPath($filename);
    if ($path === null) {
        abort(404);
    }

    return response()->file($path, [
        'Access-Control-Allow-Origin' => '*',
        'Cross-Origin-Resource-Policy' => 'cross-origin',
    ]);
})->where('filename', '[A-Za-z0-9._-]+');

Route::inertia('/', 'welcome')->name('home');

Route::middleware(['auth'])->group(function () {
    Route::get('/dashboard', [DashboardPageController::class, 'index'])->name('dashboard');
    Route::get('/dashboard/data', [DashboardPageController::class, 'data'])->name('dashboard.data');
    Route::get('/pos', [OverviewPageController::class, 'index'])->name('pos.overview');
    Route::get('/pos/live-wall', [OverviewPageController::class, 'liveWall'])->name('pos.live-wall');
    Route::get('/pos/health', [OverviewPageController::class, 'health'])->name('pos.health');
    Route::post('/pos/monitor/subscribe', [PosMonitorPageController::class, 'subscribe'])->name('pos.monitor.subscribe');
    Route::post('/pos/monitor/unsubscribe', [PosMonitorPageController::class, 'unsubscribe'])->name('pos.monitor.unsubscribe');
    Route::get('/pos/monitor/live', [PosMonitorPageController::class, 'live'])->name('pos.monitor.live');
    Route::get('/pos/monitor/watch', [PosMonitorPageController::class, 'watch'])->name('pos.monitor.watch');
    Route::get('/pos/monitor/sales', [PosMonitorPageController::class, 'sales'])->name('pos.monitor.sales');
    Route::get('/pos/items', [ItemsPageController::class, 'index'])->name('pos.items');
    Route::get('/pos/items/sheet', [ItemsPageController::class, 'sheet'])->name('pos.items.sheet');
    Route::get('/pos/items/categories', [ItemsPageController::class, 'categories'])->name('pos.items.categories');
    Route::post('/pos/items/categories', [ItemsPageController::class, 'storeCategory'])->name('pos.items.categories.store');
    Route::put('/pos/items/categories', [ItemsPageController::class, 'updateCategory'])->name('pos.items.categories.update');
    Route::get('/pos/items/products', [ItemsPageController::class, 'products'])->name('pos.items.products');
    Route::post('/pos/items/products', [ItemsPageController::class, 'storeProduct'])->name('pos.items.products.store');
    Route::put('/pos/items/products', [ItemsPageController::class, 'updateProduct'])->name('pos.items.products.update');
    Route::delete('/pos/items/products', [ItemsPageController::class, 'deleteProduct'])->name('pos.items.products.destroy');
    Route::get('/pos/items/products/export', [ItemsPageController::class, 'exportProducts'])->name('pos.items.products.export');
    Route::post('/pos/items/products/import', [ItemsPageController::class, 'importProducts'])->name('pos.items.products.import');
    Route::get('/pos/inventory', [InventoryPageController::class, 'index'])->name('pos.inventory');
    Route::get('/pos/inventory/report', [InventoryPageController::class, 'report'])->name('pos.inventory.report');
    Route::post('/pos/inventory/stock', [InventoryPageController::class, 'adjustStock'])->name('pos.inventory.stock');
    Route::get('/pos/reports', [ReportsPageController::class, 'index'])->name('pos.reports');
    Route::get('/pos/reports/summary', [ReportsPageController::class, 'summary'])->name('pos.reports.summary');
    Route::get('/pos/reports/sales-visuals', [ReportsPageController::class, 'salesVisuals'])->name('pos.reports.sales-visuals');
    Route::get('/pos/reports/charts', [ReportsPageController::class, 'charts'])->name('pos.reports.charts');
    Route::get('/pos/reports/product-mix', [ReportsPageController::class, 'productMix'])->name('pos.reports.product-mix');
    Route::get('/pos/reports/customers', [ReportsPageController::class, 'customers'])->name('pos.reports.customers');
    Route::get('/pos/reports/audit-trail', [ReportsPageController::class, 'auditTrail'])->name('pos.reports.audit-trail');
    Route::get('/pos/reports/attendance-punctuality', [ReportsPageController::class, 'attendancePunctuality'])->name('pos.reports.attendance-punctuality');
    Route::get('/pos/cash-drawer', [CashDrawerPageController::class, 'index'])->name('pos.cash-drawer');
    Route::post('/pos/cash-drawer/verify-pin', [CashDrawerPageController::class, 'verifyPin'])->name('pos.cash-drawer.verify-pin');
    Route::get('/pos/cash-drawer/summary', [CashDrawerPageController::class, 'summary'])->name('pos.cash-drawer.summary');
    Route::get('/pos/cash-drawer/watch', [CashDrawerPageController::class, 'watch'])->name('pos.cash-drawer.watch');
    Route::patch('/pos/cash-drawer/starting-cash', [CashDrawerPageController::class, 'updateStartingCash'])->name('pos.cash-drawer.starting-cash');
    Route::post('/pos/cash-drawer/cash-additions', [CashDrawerPageController::class, 'addCash'])->name('pos.cash-drawer.cash-additions.store');
    Route::put('/pos/cash-drawer/cash-additions/{additionId}', [CashDrawerPageController::class, 'updateCashAddition'])->name('pos.cash-drawer.cash-additions.update');
    Route::delete('/pos/cash-drawer/cash-additions/{additionId}', [CashDrawerPageController::class, 'deleteCashAddition'])->name('pos.cash-drawer.cash-additions.delete');
    Route::get('/pos/cash-drawer/cash-additions/export', [CashDrawerPageController::class, 'exportCashAdditions'])->name('pos.cash-drawer.cash-additions.export');
    Route::post('/pos/cash-drawer/expenses', [CashDrawerPageController::class, 'addExpense'])->name('pos.cash-drawer.expenses.store');
    Route::put('/pos/cash-drawer/expenses/{expenseId}', [CashDrawerPageController::class, 'updateExpense'])->name('pos.cash-drawer.expenses.update');
    Route::delete('/pos/cash-drawer/expenses/{expenseId}', [CashDrawerPageController::class, 'deleteExpense'])->name('pos.cash-drawer.expenses.delete');
    Route::get('/pos/cash-drawer/expenses/export', [CashDrawerPageController::class, 'exportExpenses'])->name('pos.cash-drawer.expenses.export');
    Route::get('/pos/transactions', [TransactionsPageController::class, 'index'])->name('pos.transactions');
    Route::get('/pos/transactions/data', [TransactionsPageController::class, 'data'])->name('pos.transactions.data');
    Route::post('/pos/transactions/refund', [TransactionsPageController::class, 'refund'])->name('pos.transactions.refund');
    Route::get('/pos/staff', [StaffPageController::class, 'index'])->name('pos.staff');
    Route::get('/pos/staff/users', [StaffPageController::class, 'users'])->name('pos.staff.users');
    Route::post('/pos/staff/users', [StaffPageController::class, 'storeUser'])->name('pos.staff.users.store');
    Route::get('/pos/staff/attendance', [StaffPageController::class, 'attendance'])->name('pos.staff.attendance');
    Route::get('/pos/staff/attendance/export', [StaffPageController::class, 'exportAttendance'])->name('pos.staff.attendance.export');
    Route::post('/pos/staff/attendance', [StaffPageController::class, 'clockAttendance'])->name('pos.staff.attendance.clock');
    Route::get('/pos/staff/attendance/photos', [StaffPageController::class, 'attendancePhotoStats'])->name('pos.staff.attendance.photos');
    Route::post('/pos/staff/attendance/photos/purge', [StaffPageController::class, 'purgeAttendancePhotos'])->name('pos.staff.attendance.photos.purge');
    Route::get('/pos/payroll', [StaffPageController::class, 'payrollPage'])->name('pos.payroll');
    Route::get('/pos/payroll/report', [StaffPageController::class, 'payrollReport'])->name('pos.payroll.report');
    Route::post('/pos/payroll/rate', [StaffPageController::class, 'updatePayrollRate'])->name('pos.payroll.rate');
    Route::get('/pos/staff/face-profiles', [StaffPageController::class, 'faceProfiles'])->name('pos.staff.face-profiles');
    Route::post('/pos/staff/face-profiles', [StaffPageController::class, 'enrollFace'])->name('pos.staff.face-profiles.enroll');
    Route::post('/pos/staff/face-profiles/verify', [StaffPageController::class, 'verifyFace'])->name('pos.staff.face-profiles.verify');
    Route::delete('/pos/staff/face-profiles/{userId}', [StaffPageController::class, 'deleteFace'])->name('pos.staff.face-profiles.delete');
    Route::get('/pos/loyalty', [LoyaltyPageController::class, 'loyalty'])->name('pos.loyalty');
    Route::get('/pos/loyalty/overview', [LoyaltyPageController::class, 'overview'])->name('pos.loyalty.overview');
    Route::get('/pos/loyalty/cards', [LoyaltyPageController::class, 'cards'])->name('pos.loyalty.cards');
    Route::post('/pos/loyalty/settings', [LoyaltyPageController::class, 'updateSettings'])->name('pos.loyalty.settings');
    Route::get('/pos/promotions', [PromotionsPageController::class, 'index'])->name('pos.promotions');
    Route::get('/pos/promotions/coupons', [PromotionsPageController::class, 'coupons'])->name('pos.promotions.coupons');
    Route::post('/pos/promotions/coupons', [PromotionsPageController::class, 'storeCoupon'])->name('pos.promotions.coupons.store');
    Route::get('/pos/customers/list', [LoyaltyPageController::class, 'customerList'])->name('pos.customers.list');
    Route::post('/pos/customers', [LoyaltyPageController::class, 'storeCustomer'])->name('pos.customers.store');
    Route::get('/pos/customers', fn () => redirect('/pos/loyalty'))->name('pos.customers');
    Route::post('/pos/customers/issue-card', [LoyaltyPageController::class, 'issueCard'])->name('pos.customers.issue-card');
    Route::post('/pos/customers/link-nfc', [LoyaltyPageController::class, 'linkNfc'])->name('pos.customers.link-nfc');
});

require __DIR__.'/settings.php';
