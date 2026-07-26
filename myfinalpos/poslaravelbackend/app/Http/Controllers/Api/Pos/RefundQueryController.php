<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use App\Support\PosHelpers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class RefundQueryController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        if ($request->isMethod('OPTIONS')) {
            return $this->posSuccess();
        }

        if (! $request->isMethod('get')) {
            return $this->posError('Method not allowed', 405);
        }

        if (! PosHelpers::tableExists('refunds')) {
            return $this->posSuccess(['data' => []]);
        }

        try {
            $refunds = DB::select(
                'SELECT
                    r.id,
                    r.order_id,
                    r.refund_type,
                    r.amount,
                    r.reason,
                    r.created_at,
                    o.payment_method,
                    o.total_amount AS order_total,
                    COALESCE(o.refunded_amount, 0) AS order_refunded_amount,
                    COALESCE(o.status, "completed") AS order_status,
                    COALESCE(c.customer_name, "Walk In Farmer") AS customer_name
                 FROM refunds r
                 INNER JOIN orders o ON o.id = r.order_id
                 LEFT JOIN customers c ON c.id = o.customer_id
                 ORDER BY r.created_at DESC, r.id DESC',
            );

            $data = [];
            foreach ($refunds as $refund) {
                $row = (array) $refund;

                $items = DB::select(
                    'SELECT
                        ri.id,
                        ri.order_item_id,
                        ri.quantity,
                        ri.amount,
                        oi.product_id,
                        oi.product_name
                     FROM refund_items ri
                     INNER JOIN order_items oi ON oi.id = ri.order_item_id
                     WHERE ri.refund_id = ?
                     ORDER BY ri.id ASC',
                    [(int) $row['id']],
                );

                $row['items'] = array_map(fn ($item) => (array) $item, $items);
                $data[] = $row;
            }

            return $this->posSuccess(['data' => $data]);
        } catch (\Throwable $e) {
            return $this->posServerError($e);
        }
    }
}
