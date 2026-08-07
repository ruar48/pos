<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosDateTime;
use App\Support\PosHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class OrderQueryController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        if (! $request->isMethod('get')) {
            return $this->posError('Method not allowed', 405);
        }

        try {
            $useRefunds = PosHelpers::tableExists('refunds');

            $statusSql = $useRefunds
                ? "CASE
                    WHEN COALESCE(rf.refunded_amount, 0) >= o.total_amount AND o.total_amount > 0 THEN 'refunded'
                    WHEN COALESCE(rf.refunded_amount, 0) > 0 THEN 'partial_refund'
                    ELSE 'completed'
                   END AS status,
                   COALESCE(rf.refunded_amount, 0) AS refunded_amount,"
                : "'completed' AS status, 0.00 AS refunded_amount,";

            $refundJoin = $useRefunds
                ? 'LEFT JOIN (SELECT order_id, SUM(amount) AS refunded_amount FROM refunds GROUP BY order_id) rf ON rf.order_id = o.id'
                : '';

            $hasItemDiscount = PosHelpers::columnExists('order_items', 'discount_amount');
            $itemDiscountSelect = $hasItemDiscount ? 'COALESCE(idisc.item_discount, 0)' : '0';
            $itemDiscountJoin = $hasItemDiscount
                ? 'LEFT JOIN (SELECT order_id, SUM(COALESCE(discount_amount, 0)) AS item_discount FROM order_items GROUP BY order_id) idisc ON idisc.order_id = o.id'
                : '';

            $hasBranchId = PosHelpers::columnExists('orders', 'branch_id');
            $hasCashierUserId = PosHelpers::columnExists('orders', 'cashier_user_id');
            $hasBranchesTable = PosHelpers::tableExists('branches');

            $branchSelect = $hasBranchId ? 'COALESCE(o.branch_id, 1) AS branch_id,' : '1 AS branch_id,';
            $branchNameSelect = ($hasBranchId && $hasBranchesTable)
                ? 'COALESCE(b.name, "Main Branch") AS branch_name,'
                : '"Main Branch" AS branch_name,';
            $cashierSelect = $hasCashierUserId ? 'o.cashier_user_id,' : 'NULL AS cashier_user_id,';
            $cashierNameSelect = $hasCashierUserId ? 'cashier.full_name AS cashier_name,' : 'NULL AS cashier_name,';
            $branchJoin = ($hasBranchId && $hasBranchesTable) ? 'LEFT JOIN branches b ON b.id = o.branch_id' : '';
            $cashierJoin = $hasCashierUserId ? 'LEFT JOIN users cashier ON cashier.id = o.cashier_user_id' : '';

            $orders = DB::select(
                "SELECT
                    o.id,
                    o.customer_id,
                    {$branchSelect}
                    {$branchNameSelect}
                    {$cashierSelect}
                    {$cashierNameSelect}
                    o.subtotal,
                    o.vat,
                    o.total_amount,
                    COALESCE(o.discount_amount, 0) + {$itemDiscountSelect} AS discount_amount,
                    COALESCE(o.coupon_discount, 0) AS coupon_discount,
                    COALESCE(o.loyalty_discount, 0) AS loyalty_discount,
                    COALESCE(o.loyalty_points_redeemed, 0) AS loyalty_points_redeemed,
                    o.client_change,
                    o.payment_method,
                    o.reference,
                    o.created_at,
                    {$statusSql}
                    COALESCE(c.customer_name, 'Walk In Farmer') AS customer_name,
                    COALESCE(c.table_name, '') AS table_name,
                    COALESCE(c.order_type, 'Retail') AS customer_order_type
                 FROM orders o
                 LEFT JOIN customers c ON c.id = o.customer_id
                 {$branchJoin}
                 {$cashierJoin}
                 {$refundJoin}
                 {$itemDiscountJoin}
                 ORDER BY o.created_at DESC, o.id DESC",
            );

            $hasRefundedQty = PosHelpers::columnExists('order_items', 'refunded_quantity');
            $refundedCol = $hasRefundedQty ? 'oi.refunded_quantity' : '0 AS refunded_quantity';

            $hasVariety = PosHelpers::columnExists('order_items', 'variety_id');
            $varietySelect = $hasVariety
                ? 'oi.variety_id, oi.variety_name,'
                : 'NULL AS variety_id, NULL AS variety_name,';

            $itemDiscountColSelect = $hasItemDiscount
                ? 'COALESCE(oi.discount_amount, 0) AS discount_amount,'
                : '0 AS discount_amount,';

            $data = [];
            foreach ($orders as $order) {
                $orderRow = (array) $order;

                $items = DB::select(
                    "SELECT
                        oi.id,
                        oi.id AS order_item_id,
                        oi.order_id,
                        oi.product_id,
                        {$varietySelect}
                        oi.product_name,
                        oi.quantity,
                        {$refundedCol},
                        oi.price,
                        {$itemDiscountColSelect}
                        oi.total
                     FROM order_items oi
                     WHERE oi.order_id = ?
                     ORDER BY oi.id ASC",
                    [(int) $orderRow['id']],
                );

                $orderRow['customer_email'] = null;
                $orderRow['customer_phone'] = $orderRow['table_name']
                    ? 'Location: '.$orderRow['table_name']
                    : ($orderRow['customer_order_type'] ?? 'Retail');
                $orderRow['created_at'] = PosDateTime::formatIso(
                    (string) ($orderRow['created_at'] ?? ''),
                );
                $orderRow['payments'] = PosHelpers::loadOrderPayments((int) $orderRow['id']);
                $orderRow['items'] = array_map(fn ($item) => (array) $item, $items);

                $data[] = $orderRow;
            }

            return $this->posSuccess(['data' => $data]);
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
