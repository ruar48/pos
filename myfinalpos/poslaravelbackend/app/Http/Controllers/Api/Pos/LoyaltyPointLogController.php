<?php



namespace App\Http\Controllers\Api\Pos;



use App\Http\Controllers\Controller;

use App\Support\PosApiResponse;

use App\Support\PosHelpers;

use Illuminate\Http\JsonResponse;

use Illuminate\Http\Request;

use Illuminate\Support\Facades\DB;



class LoyaltyPointLogController extends Controller

{

    use PosApiResponse;



    public function handle(Request $request): JsonResponse

    {

        try {

            if (! $request->isMethod('get')) {

                return $this->posError('Method not allowed', 405);

            }



            if (! PosHelpers::tableExists('loyalty_point_logs')) {

                return $this->posSuccess(['data' => []]);

            }



            $customerId = (int) $request->query('customer_id', 0);

            if ($customerId <= 0) {

                return $this->posError('customer_id is required', 400);

            }



            $limit = max(1, min(200, (int) $request->query('limit', 50)));



            $rows = DB::select(

                'SELECT

                    lpl.id,

                    lpl.customer_id,

                    lpl.loyalty_card_id,

                    lpl.order_id,

                    lpl.action,

                    lpl.points_change,

                    lpl.points_balance_after,

                    lpl.order_amount,

                    lpl.description,

                    lpl.actor_user_id,

                    u.full_name AS actor_name,

                    lpl.created_at

                 FROM loyalty_point_logs lpl

                 LEFT JOIN users u ON u.id = lpl.actor_user_id

                 WHERE lpl.customer_id = ?

                 ORDER BY lpl.created_at DESC, lpl.id DESC

                 LIMIT '.$limit,

                [$customerId],

            );



            return $this->posSuccess([

                'data' => array_map(

                    fn ($row) => PosHelpers::loyaltyPointLogRowToArray((array) $row),

                    $rows,

                ),

            ]);

        } catch (\Throwable $e) {

            return $this->posServerError($e);

        }

    }

}

