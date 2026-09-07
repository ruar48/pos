<?php

namespace Tests\Unit;

use App\Services\Pos\BirSalesBreakdown;
use Tests\TestCase;

class BirSalesBreakdownTest extends TestCase
{
    private const VAT = 0.12;

    /** @return array<int, array{total: float, classification?: string}> */
    private function lines(float $total, string $class = 'vatable'): array
    {
        return [['total' => $total, 'classification' => $class]];
    }

    // -----------------------------------------------------------------
    // Exclusive pricing — what this POS actually does today
    // (PosHelpers::saleVatAndTotal adds VAT on top of the line totals).
    // -----------------------------------------------------------------

    public function test_exclusive_pricing_adds_vat_on_top_of_the_base(): void
    {
        $result = BirSalesBreakdown::compute(
            $this->lines(1000),
            vatRegistered: true,
            vatRate: self::VAT,
        );

        $this->assertSame(1000.00, $result['vatable_sales']);
        $this->assertSame(120.00, $result['vat_amount']);
        $this->assertSame(0.0, $result['vat_exempt_sales']);
    }

    public function test_exclusive_senior_citizen_sale_is_exempt_and_discounted_on_the_base(): void
    {
        // No VAT is added for an exempt sale; 20% comes off the 1000 base.
        $result = BirSalesBreakdown::compute(
            $this->lines(1000),
            vatRegistered: true,
            vatRate: self::VAT,
            statutoryType: 'sc',
        );

        $this->assertSame(0.0, $result['vatable_sales']);
        $this->assertSame(0.0, $result['vat_amount']);
        $this->assertSame(1000.00, $result['vat_exempt_sales']);
        $this->assertSame(200.00, $result['sc_discount']);
    }

    // -----------------------------------------------------------------
    // Inclusive pricing — supported for when checkout switches over.
    // -----------------------------------------------------------------

    public function test_inclusive_pricing_backs_vat_out_of_the_price(): void
    {
        // 1120 inclusive of 12% VAT => 1000 net + 120 VAT.
        $result = BirSalesBreakdown::compute(
            $this->lines(1120),
            vatRegistered: true,
            vatRate: self::VAT,
            pricesIncludeVat: true,
        );

        $this->assertSame(1000.00, $result['vatable_sales']);
        $this->assertSame(120.00, $result['vat_amount']);
    }

    public function test_inclusive_statutory_discount_is_taken_after_vat_is_removed(): void
    {
        $result = BirSalesBreakdown::compute(
            $this->lines(1120),
            vatRegistered: true,
            vatRate: self::VAT,
            statutoryType: 'sc',
            pricesIncludeVat: true,
        );

        $this->assertSame(1000.00, $result['vat_exempt_sales']);
        $this->assertSame(200.00, $result['sc_discount']);
        // Must not be 20% of the VAT-bearing 1120 (= 224).
        $this->assertNotSame(224.00, $result['sc_discount']);
    }

    // -----------------------------------------------------------------
    // VAT registration status
    // -----------------------------------------------------------------

    public function test_non_vat_store_produces_no_output_vat(): void
    {
        $result = BirSalesBreakdown::compute(
            $this->lines(1000),
            vatRegistered: false,
            vatRate: self::VAT,
        );

        $this->assertSame(0.00, $result['vat_amount']);
        $this->assertSame(1000.00, $result['vatable_sales']);
    }

    public function test_non_vat_registered_status_is_not_read_as_vat_registered(): void
    {
        // "NON-VAT REGISTERED" contains "VAT" — the negative must win.
        $this->assertFalse(BirSalesBreakdown::isVatRegistered('NON-VAT REGISTERED'));
        $this->assertFalse(BirSalesBreakdown::isVatRegistered('NONVAT'));
        $this->assertTrue(BirSalesBreakdown::isVatRegistered('VAT REGISTERED'));
        $this->assertFalse(BirSalesBreakdown::isVatRegistered(''));
        $this->assertFalse(BirSalesBreakdown::isVatRegistered(null));
    }

    // -----------------------------------------------------------------
    // Statutory discount routing
    // -----------------------------------------------------------------

    public function test_pwd_discount_lands_on_its_own_line(): void
    {
        $result = BirSalesBreakdown::compute(
            $this->lines(1000),
            vatRegistered: true,
            vatRate: self::VAT,
            statutoryType: 'pwd',
        );

        $this->assertSame(200.00, $result['pwd_discount']);
        $this->assertSame(0.0, $result['sc_discount']);
        $this->assertSame('pwd', $result['statutory_discount_type']);
    }

    public function test_naac_and_solo_parent_are_reported_separately(): void
    {
        $naac = BirSalesBreakdown::compute(
            $this->lines(1000),
            vatRegistered: true,
            vatRate: self::VAT,
            statutoryType: 'naac',
        );
        $solo = BirSalesBreakdown::compute(
            $this->lines(1000),
            vatRegistered: true,
            vatRate: self::VAT,
            statutoryType: 'solo_parent',
        );

        $this->assertSame(200.00, $naac['naac_discount']);
        $this->assertSame(0.0, $naac['solo_parent_discount']);
        $this->assertSame(200.00, $solo['solo_parent_discount']);
        $this->assertSame(0.0, $solo['naac_discount']);
    }

    public function test_unknown_statutory_type_is_ignored(): void
    {
        $result = BirSalesBreakdown::compute(
            $this->lines(1000),
            vatRegistered: true,
            vatRate: self::VAT,
            statutoryType: 'bogus',
        );

        $this->assertNull($result['statutory_discount_type']);
        $this->assertSame(1000.00, $result['vatable_sales']);
        $this->assertSame(0.0, $result['sc_discount']);
    }

    public function test_ordinary_discounts_stay_out_of_the_statutory_lines(): void
    {
        $result = BirSalesBreakdown::compute(
            $this->lines(1000),
            vatRegistered: true,
            vatRate: self::VAT,
            otherDiscounts: 75,
        );

        $this->assertSame(75.00, $result['other_discount']);
        $this->assertSame(0.0, $result['sc_discount']);
    }

    // -----------------------------------------------------------------
    // Product classification
    // -----------------------------------------------------------------

    public function test_exempt_and_zero_rated_products_keep_their_own_buckets(): void
    {
        $result = BirSalesBreakdown::compute(
            [
                ['total' => 1000, 'classification' => 'vatable'],
                ['total' => 500, 'classification' => 'vat_exempt'],
                ['total' => 300, 'classification' => 'zero_rated'],
            ],
            vatRegistered: true,
            vatRate: self::VAT,
        );

        $this->assertSame(1000.00, $result['vatable_sales']);
        $this->assertSame(120.00, $result['vat_amount'], 'VAT only on the vatable part');
        $this->assertSame(500.00, $result['vat_exempt_sales']);
        $this->assertSame(300.00, $result['zero_rated_sales']);
    }

    public function test_statutory_sale_moves_vatable_lines_into_the_exempt_bucket(): void
    {
        $result = BirSalesBreakdown::compute(
            [
                ['total' => 1000, 'classification' => 'vatable'],
                ['total' => 500, 'classification' => 'vat_exempt'],
            ],
            vatRegistered: true,
            vatRate: self::VAT,
            statutoryType: 'sc',
        );

        $this->assertSame(0.0, $result['vatable_sales']);
        $this->assertSame(1500.00, $result['vat_exempt_sales']);
        $this->assertSame(300.00, $result['sc_discount'], '20% of the whole exempt base');
    }

    public function test_unclassified_product_defaults_to_vatable(): void
    {
        $result = BirSalesBreakdown::compute(
            [['total' => 1000]],
            vatRegistered: true,
            vatRate: self::VAT,
        );

        $this->assertSame(1000.00, $result['vatable_sales']);
        $this->assertSame(0.0, $result['vat_exempt_sales']);
    }
}
