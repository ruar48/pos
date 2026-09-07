<?php

namespace App\Services\Pos;

use App\Support\BusinessDay;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * X reading and Z reading for a register (BIR).
 *
 * X reading  - interim. Reports the open shift's totals and changes nothing.
 *              May be taken any number of times.
 * Z reading  - end of shift. Closes the session, increments the terminal's Z
 *              counter, and rolls the shift's sales into the accumulated grand
 *              total that must never reset.
 *
 * ---------------------------------------------------------------------------
 * COMPLIANCE NOTE
 *
 * A BIR-accredited Z reading must break out senior-citizen, PWD, NAAC and
 * solo-parent discounts, and split sales into VATable / VAT-exempt /
 * zero-rated. The point of sale does not capture any of those today: orders
 * carry one flat `vat` column and generic discount columns with no statutory
 * classification, and no customer ID is recorded against a discount.
 *
 * Those figures are therefore NOT computed here. They are listed in
 * [UNCAPTURED_BIR_FIELDS] and stored on the reading so a printed copy can
 * state that they are unavailable. Reporting them as 0.00 would assert "no
 * senior citizen sales occurred", which is a different and possibly false
 * claim. This reading is not BIR-valid until that capture exists.
 * ---------------------------------------------------------------------------
 */
class RegisterReadingService
{
    /**
     * BIR figures that cannot be sourced from captured data yet. Stored on
     * every reading so the printed copy can mark them rather than imply zero.
     *
     * @var list<string>
     */
    public const UNCAPTURED_BIR_FIELDS = [
        'sc_discount',
        'pwd_discount',
        'naac_discount',
        'solo_parent_discount',
        'vat_exempt_sales',
        'zero_rated_sales',
    ];

    public function __construct(
        private readonly RegisterSessionService $sessions,
    ) {}

    /**
     * Interim reading. Reads the open session without altering any counter.
     *
     * @return array<string, mixed>
     */
    public function xReading(string $terminalId, ?int $takenByUserId = null): array
    {
        $session = $this->sessions->openSessionFor($terminalId);
        if ($session === null) {
            throw new RuntimeException(
                'No open register session for this terminal. Open a shift before taking an X reading.',
            );
        }

        $totals = $this->totalsForSession($session);
        $counters = $this->sessions->countersFor($terminalId);

        $reading = $this->composeReading(
            type: 'x',
            session: $session,
            totals: $totals,
            counters: $counters,
            zCounter: null,
            takenByUserId: $takenByUserId,
        );

        $id = DB::table('pos_register_readings')->insertGetId($this->toRow($reading));

        return $reading + ['id' => $id];
    }

    /**
     * Closing reading. Closes the shift, increments the Z counter and adds the
     * shift's net sales to the terminal's accumulated grand total.
     *
     * The whole thing runs in one transaction with the counter row locked, so
     * two registers closing at once cannot be handed the same Z number.
     *
     * @return array<string, mixed>
     */
    public function zReading(string $terminalId, ?int $takenByUserId = null): array
    {
        return DB::transaction(function () use ($terminalId, $takenByUserId) {
            $session = $this->sessions->openSessionFor($terminalId, lock: true);
            if ($session === null) {
                throw new RuntimeException(
                    'No open register session for this terminal. There is nothing to close.',
                );
            }

            $counters = $this->sessions->countersFor($terminalId, lock: true);
            $totals = $this->totalsForSession($session);

            $nextZ = ((int) $counters->z_counter) + 1;

            $reading = $this->composeReading(
                type: 'z',
                session: $session,
                totals: $totals,
                counters: $counters,
                zCounter: $nextZ,
                takenByUserId: $takenByUserId,
            );

            $id = DB::table('pos_register_readings')->insertGetId($this->toRow($reading));

            DB::table('pos_terminal_counters')
                ->where('id', $counters->id)
                ->update([
                    // Accumulate net sales — the figure BIR treats as the
                    // running lifetime total for the machine.
                    'grand_total_accumulated' => $reading['ending_grand_total'],
                    'z_counter' => $nextZ,
                    'last_z_at' => now(),
                    'updated_at' => now(),
                ]);

            DB::table('pos_register_sessions')
                ->where('id', $session->id)
                ->update([
                    'status' => 'closed',
                    'closed_at' => now(),
                    'updated_at' => now(),
                ]);

            return $reading + ['id' => $id];
        });
    }

    /**
     * Sales aggregates for one session, taken from orders tagged with it.
     *
     * @return array<string, mixed>
     */
    private function totalsForSession(object $session): array
    {
        $orders = DB::table('orders')
            ->where('register_session_id', $session->id)
            ->get();

        $completed = $orders->filter(
            static fn ($o) => strtolower((string) $o->status) !== 'void',
        );
        $voided = $orders->filter(
            static fn ($o) => strtolower((string) $o->status) === 'void',
        );

        $gross = 0.0;
        $vat = 0.0;
        $discounts = 0.0;
        $refunded = 0.0;
        $payments = [];

        foreach ($completed as $order) {
            $gross += (float) $order->subtotal;
            $vat += (float) $order->vat;
            $discounts += (float) $order->discount_amount
                + (float) $order->coupon_discount
                + (float) $order->loyalty_discount;
            $refunded += (float) $order->refunded_amount;

            $method = trim((string) $order->payment_method) ?: 'Cash';
            $payments[$method] = ($payments[$method] ?? 0.0)
                + (float) $order->total_amount;
        }

        $voidAmount = 0.0;
        foreach ($voided as $order) {
            $voidAmount += (float) $order->total_amount;
        }

        // Refund rows raised during the shift, counted separately from the
        // running refunded_amount so the reading can show how many happened.
        $refundCount = 0;
        if ($session->opened_at !== null) {
            $refundCount = (int) DB::table('refunds')
                ->join('orders', 'orders.id', '=', 'refunds.order_id')
                ->where('orders.register_session_id', $session->id)
                ->count();
        }

        $net = $gross - $discounts - $refunded;

        $orderIds = $completed->pluck('id')->all();
        sort($orderIds);

        return [
            'gross_sales' => round($gross, 2),
            'net_sales' => round($net, 2),
            'vat_amount' => round($vat, 2),
            // VATable is everything we can classify; without exempt/zero-rated
            // capture this is the whole of net sales rather than a real split.
            'vatable_sales' => round($net, 2),
            'discount_total' => round($discounts, 2),
            'other_discount' => round($discounts, 2),
            'refund_amount' => round($refunded, 2),
            'refund_count' => $refundCount,
            'void_amount' => round($voidAmount, 2),
            'void_count' => $voided->count(),
            'transaction_count' => $completed->count(),
            'payment_breakdown' => array_map(
                static fn ($v) => round($v, 2),
                $payments,
            ),
            'beginning_or' => $orderIds === [] ? null : self::invoiceNumber($orderIds[0]),
            'ending_or' => $orderIds === [] ? null : self::invoiceNumber(end($orderIds)),
            'covers_from' => $session->opened_at,
            'covers_to' => now()->toDateTimeString(),
        ];
    }

    /**
     * Matches the invoice number the receipt prints (INV-000030).
     */
    public static function invoiceNumber(int $orderId): string
    {
        return 'INV-' . str_pad((string) $orderId, 6, '0', STR_PAD_LEFT);
    }

    /**
     * @param array<string, mixed> $totals
     * @return array<string, mixed>
     */
    private function composeReading(
        string $type,
        object $session,
        array $totals,
        object $counters,
        ?int $zCounter,
        ?int $takenByUserId,
    ): array {
        $beginning = (float) $counters->grand_total_accumulated;

        return [
            'terminal_id' => $session->terminal_id,
            'register_session_id' => (int) $session->id,
            'type' => $type,
            'z_counter' => $zCounter,
            'reset_counter' => (int) $counters->reset_counter,
            'business_date' => $session->business_date,
            'taken_by_user_id' => $takenByUserId,
            'covers_from' => $totals['covers_from'],
            'covers_to' => $totals['covers_to'],
            'beginning_or' => $totals['beginning_or'],
            'ending_or' => $totals['ending_or'],
            'beginning_grand_total' => round($beginning, 2),
            'ending_grand_total' => round($beginning + $totals['net_sales'], 2),
            'gross_sales' => $totals['gross_sales'],
            'net_sales' => $totals['net_sales'],
            'vatable_sales' => $totals['vatable_sales'],
            'vat_amount' => $totals['vat_amount'],
            'vat_exempt_sales' => 0,
            'zero_rated_sales' => 0,
            'sc_discount' => 0,
            'pwd_discount' => 0,
            'naac_discount' => 0,
            'solo_parent_discount' => 0,
            'other_discount' => $totals['other_discount'],
            'discount_total' => $totals['discount_total'],
            'refund_amount' => $totals['refund_amount'],
            'refund_count' => $totals['refund_count'],
            'void_amount' => $totals['void_amount'],
            'void_count' => $totals['void_count'],
            'transaction_count' => $totals['transaction_count'],
            'payment_breakdown' => $totals['payment_breakdown'],
            'uncaptured_fields' => self::UNCAPTURED_BIR_FIELDS,
        ];
    }

    /**
     * @param array<string, mixed> $reading
     * @return array<string, mixed>
     */
    private function toRow(array $reading): array
    {
        $row = $reading;
        $row['payment_breakdown'] = json_encode($reading['payment_breakdown']);
        $row['uncaptured_fields'] = json_encode($reading['uncaptured_fields']);
        $row['created_at'] = now();

        return $row;
    }

    /**
     * Past readings for a terminal, newest first.
     *
     * @return array<int, array<string, mixed>>
     */
    public function history(string $terminalId, int $limit = 50): array
    {
        return DB::table('pos_register_readings')
            ->where('terminal_id', $terminalId)
            ->orderByDesc('id')
            ->limit(max(1, min($limit, 200)))
            ->get()
            ->map(static function ($row) {
                $data = (array) $row;
                $data['payment_breakdown'] = json_decode(
                    (string) ($row->payment_breakdown ?? '{}'),
                    true,
                ) ?: [];
                $data['uncaptured_fields'] = json_decode(
                    (string) ($row->uncaptured_fields ?? '[]'),
                    true,
                ) ?: [];

                return $data;
            })
            ->all();
    }

    /**
     * Business date for a moment, honouring the configured 5am rollover.
     */
    public static function businessDateFor(?Carbon $moment = null): string
    {
        return BusinessDay::currentDate($moment);
    }
}
