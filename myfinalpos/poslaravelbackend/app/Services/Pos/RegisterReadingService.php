<?php

namespace App\Services\Pos;

use App\Support\BusinessDay;
use App\Support\PosHelpers;
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
 * The statutory figures BIR requires — senior-citizen, PWD, NAAC and
 * solo-parent discounts, and the VATable / VAT-exempt / zero-rated split — are
 * captured per order at checkout by BirSalesBreakdown and merely summed here.
 * They are never recomputed from current product flags, so reclassifying a
 * product cannot rewrite an already-filed reading.
 *
 * [uncapturedBirFields] reports any of those columns that are missing (i.e.
 * the capture migration has not run). Anything listed there is printed as
 * "not captured" rather than 0.00, because a zero would assert that no such
 * sales occurred.
 *
 * Correct figures are necessary but not sufficient for accreditation: BIR also
 * requires a registered machine (MIN/serial on file), a permanent electronic
 * journal, and inspection. See docs/BIR-READINGS.md.
 * ---------------------------------------------------------------------------
 */
class RegisterReadingService
{
    /**
     * BIR figures that depend on point-of-sale capture. Each is reported only
     * when the column backing it exists; anything missing is listed on the
     * reading so a printed copy says "not captured" instead of implying a
     * truthful 0.00.
     *
     * Once the BIR capture migration has run this comes back empty and the
     * reading reports real figures.
     *
     * @return list<string>
     */
    public static function uncapturedBirFields(): array
    {
        $required = [
            'sc_discount' => 'sc_discount',
            'pwd_discount' => 'pwd_discount',
            'naac_discount' => 'naac_discount',
            'solo_parent_discount' => 'solo_parent_discount',
            'vat_exempt_sales' => 'vat_exempt_sales',
            'zero_rated_sales' => 'zero_rated_sales',
        ];

        $missing = [];
        foreach ($required as $field => $column) {
            if (! PosHelpers::columnExists('orders', $column)) {
                $missing[] = $field;
            }
        }

        return $missing;
    }

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

        // BIR classifications, captured on the order at checkout.
        $vatable = 0.0;
        $vatExempt = 0.0;
        $zeroRated = 0.0;
        $sc = 0.0;
        $pwd = 0.0;
        $naac = 0.0;
        $soloParent = 0.0;

        foreach ($completed as $order) {
            $gross += (float) $order->subtotal;
            $vat += (float) $order->vat;
            $discounts += (float) $order->discount_amount
                + (float) $order->coupon_discount
                + (float) $order->loyalty_discount;
            $refunded += (float) $order->refunded_amount;

            $vatable += (float) ($order->vatable_sales ?? 0);
            $vatExempt += (float) ($order->vat_exempt_sales ?? 0);
            $zeroRated += (float) ($order->zero_rated_sales ?? 0);
            $sc += (float) ($order->sc_discount ?? 0);
            $pwd += (float) ($order->pwd_discount ?? 0);
            $naac += (float) ($order->naac_discount ?? 0);
            $soloParent += (float) ($order->solo_parent_discount ?? 0);

            $method = trim((string) $order->payment_method) ?: 'Cash';
            $payments[$method] = ($payments[$method] ?? 0.0)
                + (float) $order->total_amount;
        }

        // Statutory discounts are reported on their own lines, so they must
        // not also be counted under "other".
        $statutory = $sc + $pwd + $naac + $soloParent;
        $otherDiscounts = max(0.0, $discounts - $statutory);

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
            'vatable_sales' => round($vatable, 2),
            'vat_exempt_sales' => round($vatExempt, 2),
            'zero_rated_sales' => round($zeroRated, 2),
            'sc_discount' => round($sc, 2),
            'pwd_discount' => round($pwd, 2),
            'naac_discount' => round($naac, 2),
            'solo_parent_discount' => round($soloParent, 2),
            'discount_total' => round($discounts, 2),
            'other_discount' => round($otherDiscounts, 2),
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
     * Machine and taxpayer identity for the reading header.
     *
     * BIR requires the registered name, address, TIN, MIN, machine serial and
     * permit number on every reading. Missing values are returned empty so the
     * printed copy can show "not set" — inventing a placeholder MIN on a filed
     * document would be worse than an obvious blank.
     *
     * @return array<string, string>
     */
    public function machineIdentity(): array
    {
        $store = (array) (
            app(AppSettingsService::class)->read()['receipt_store'] ?? []
        );

        $get = static fn (string $key) => trim((string) ($store[$key] ?? ''));

        return [
            'store_name' => $get('store_name'),
            'address_line1' => $get('address_line1'),
            'address_line2' => $get('address_line2'),
            'tin' => $get('tin'),
            'tax_status' => $get('tax_status'),
            'min_no' => $get('min_no'),
            'machine_serial_no' => $get('machine_serial_no'),
            'ptu_no' => $get('ptu_no'),
            'atp_no' => $get('atp_no'),
            'series_range' => $get('series_range'),
        ];
    }

    /**
     * Identity fields BIR requires that have not been filled in yet.
     *
     * @return list<string>
     */
    public function missingIdentityFields(): array
    {
        $identity = $this->machineIdentity();
        $required = ['store_name', 'tin', 'min_no', 'machine_serial_no', 'ptu_no'];

        return array_values(array_filter(
            $required,
            static fn ($key) => ($identity[$key] ?? '') === '',
        ));
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
            'vat_exempt_sales' => $totals['vat_exempt_sales'],
            'zero_rated_sales' => $totals['zero_rated_sales'],
            'sc_discount' => $totals['sc_discount'],
            'pwd_discount' => $totals['pwd_discount'],
            'naac_discount' => $totals['naac_discount'],
            'solo_parent_discount' => $totals['solo_parent_discount'],
            'other_discount' => $totals['other_discount'],
            'discount_total' => $totals['discount_total'],
            'refund_amount' => $totals['refund_amount'],
            'refund_count' => $totals['refund_count'],
            'void_amount' => $totals['void_amount'],
            'void_count' => $totals['void_count'],
            'transaction_count' => $totals['transaction_count'],
            'payment_breakdown' => $totals['payment_breakdown'],
            'uncaptured_fields' => self::uncapturedBirFields(),
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
