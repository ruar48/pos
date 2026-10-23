<?php

namespace Tests\Unit;

use App\Support\PosHelpers;
use PHPUnit\Framework\TestCase;

class OrderDiscountMathTest extends TestCase
{
    private function order(float $subtotal, float $vat, float $total, float $manual, float $coupon = 0, float $loyalty = 0): object
    {
        return (object) [
            'subtotal' => $subtotal,
            'vat' => $vat,
            'total_amount' => $total,
            'discount_amount' => $manual,
            'coupon_discount' => $coupon,
            'loyalty_discount' => $loyalty,
        ];
    }

    public function test_refund_ratio_does_not_take_order_discounts_off_twice(): void
    {
        // INV-013507: lines 10,680 + 6,120 + 6,120 (already net of item
        // discounts), 3,720 manual discount, paid 19,200.
        $order = $this->order(19200, 0, 19200, 3720);

        $ratio = PosHelpers::refundMerchandiseRatio($order, 22920);

        $this->assertEqualsWithDelta(19200 / 22920, $ratio, 0.000001);
        // Refunding AGWAY alone gives back its share of what was paid
        // (8,946.60), not the old double-discounted 8,610.75.
        $this->assertSame(8946.6, round(10680 * $ratio, 2));
    }

    public function test_refund_ratio_with_item_manual_coupon_and_loyalty_stacked(): void
    {
        // Lines net 1,000; manual 300 + coupon 200 + loyalty 100 -> paid 400.
        // The old (subtotal - discounts) / subtotal = (400 - 600) / 400
        // clamped to 0, so a partial refund failed with "Refund amount must
        // be greater than zero".
        $order = $this->order(400, 0, 400, 300, 200, 100);

        $this->assertEqualsWithDelta(0.4, PosHelpers::refundMerchandiseRatio($order, 1000), 0.000001);
    }

    public function test_refund_ratio_with_vat(): void
    {
        $order = $this->order(400, 48, 448, 300, 200, 100);

        $ratio = PosHelpers::refundMerchandiseRatio($order, 1000);

        $this->assertEqualsWithDelta(0.4, $ratio, 0.000001);
        // Refunding the whole order's merchandise returns everything paid.
        $this->assertSame(448.0, PosHelpers::refundAmountIncludingVat($order, 1000 * $ratio));
    }

    public function test_refund_ratio_for_legacy_rows_with_pre_discount_subtotal(): void
    {
        // Legacy rows stored subtotal before order discounts.
        $order = $this->order(1000, 0, 400, 300, 200, 100);

        $this->assertEqualsWithDelta(0.4, PosHelpers::refundMerchandiseRatio($order, 1000), 0.000001);
    }

    public function test_refund_ratio_without_order_discounts_is_one(): void
    {
        $this->assertSame(1.0, PosHelpers::refundMerchandiseRatio($this->order(500, 0, 500, 0), 500));
    }

    public function test_cap_leaves_discounts_that_fit_alone(): void
    {
        $this->assertSame(
            ['manual' => 200.0, 'coupon' => 150.0, 'loyalty' => 50.0, 'points' => 500],
            PosHelpers::capOrderDiscounts(900, 200, 150, 50, 500),
        );
    }

    public function test_cap_trims_loyalty_first_and_shrinks_points_with_it(): void
    {
        // 500 + 300 + 400 = 1,200 against a 1,000 order: only 200 of the
        // 400 loyalty pesos fit, so only half the points are spent.
        $this->assertSame(
            ['manual' => 500.0, 'coupon' => 300.0, 'loyalty' => 200.0, 'points' => 2000],
            PosHelpers::capOrderDiscounts(1000, 500, 300, 400, 4000),
        );
    }

    public function test_cap_when_manual_alone_covers_the_order(): void
    {
        $this->assertSame(
            ['manual' => 100.0, 'coupon' => 0.0, 'loyalty' => 0.0, 'points' => 0],
            PosHelpers::capOrderDiscounts(100, 150, 20, 10, 100),
        );
    }
}
