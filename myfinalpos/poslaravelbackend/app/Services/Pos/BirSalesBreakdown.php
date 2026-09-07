<?php

namespace App\Services\Pos;

/**
 * Splits a sale into the VAT classes and statutory discounts a BIR Z reading
 * must report.
 *
 * Philippine rules this encodes:
 *
 *  - Senior citizen and PWD sales are VAT-EXEMPT and take a 20% discount. The
 *    VAT comes off FIRST, then the 20% is taken on the VAT-exempt base —
 *    taking 20% of a VAT-bearing price inflates the discount and understates
 *    the exempt sale.
 *  - NAAC (national athletes/coaches) and solo parent discounts follow the
 *    same exempt-then-discount treatment.
 *  - A NON-VAT registered store has no output VAT at all, so no VAT line is
 *    produced and nothing is backed out of the price.
 *
 * PRICING CONVENTION: this POS adds VAT on top of the line totals
 * (PosHelpers::saleVatAndTotal computes net + net * rate), so prices are
 * VAT-EXCLUSIVE and [pricesIncludeVat] defaults to false. The reading has to
 * report what was actually charged, so it follows the checkout maths rather
 * than assuming the VAT-inclusive display prices common in PH retail. Pass
 * true if checkout is ever switched to inclusive pricing.
 *
 * Everything is computed at checkout and stored on the order, so a later
 * change to a product's classification cannot alter a filed reading.
 */
class BirSalesBreakdown
{
    public const STATUTORY_TYPES = ['sc', 'pwd', 'naac', 'solo_parent'];

    /** Statutory discount rate for SC / PWD / NAAC / solo parent. */
    public const STATUTORY_RATE = 0.20;

    /**
     * @param array<int, array{total: float, classification?: string}> $lines
     *        Line totals as rung up (VAT-inclusive when the store is VAT
     *        registered), with the product's VAT classification.
     * @param string $statutoryType One of STATUTORY_TYPES, or '' for none.
     * @param float $otherDiscounts Manual/coupon/loyalty discounts, which are
     *        ordinary reductions and are not statutory.
     *
     * @return array<string, float|string|null>
     */
    public static function compute(
        array $lines,
        bool $vatRegistered,
        float $vatRate,
        string $statutoryType = '',
        float $otherDiscounts = 0,
        bool $pricesIncludeVat = false,
    ): array {
        $statutoryType = in_array($statutoryType, self::STATUTORY_TYPES, true)
            ? $statutoryType
            : '';

        $vatableGross = 0.0;
        $exemptGross = 0.0;
        $zeroRatedGross = 0.0;

        foreach ($lines as $line) {
            $total = (float) ($line['total'] ?? 0);
            $class = (string) ($line['classification'] ?? 'vatable');

            match ($class) {
                'vat_exempt' => $exemptGross += $total,
                'zero_rated' => $zeroRatedGross += $total,
                default => $vatableGross += $total,
            };
        }

        // A statutory customer's whole purchase becomes VAT-exempt, so what
        // would have been VATable moves across before any VAT is worked out.
        if ($statutoryType !== '') {
            $exemptGross += $vatableGross;
            $vatableGross = 0.0;
        }

        $vatAmount = 0.0;
        $vatableNet = $vatableGross;

        if ($vatRegistered && $vatRate > 0 && $vatableGross > 0) {
            if ($pricesIncludeVat) {
                $vatableNet = $vatableGross / (1 + $vatRate);
                $vatAmount = $vatableGross - $vatableNet;
            } else {
                // VAT was added on top, so the line total already is the base.
                $vatableNet = $vatableGross;
                $vatAmount = $vatableGross * $vatRate;
            }
        }

        // An exempt sale carries no VAT. With inclusive pricing the VAT has to
        // be stripped out first; with exclusive pricing it was never added.
        $exemptNet = $exemptGross;
        if ($vatRegistered && $vatRate > 0 && $exemptGross > 0 && $pricesIncludeVat) {
            $exemptNet = $exemptGross / (1 + $vatRate);
        }

        $statutoryDiscount = 0.0;
        if ($statutoryType !== '') {
            $statutoryDiscount = $exemptNet * self::STATUTORY_RATE;
        }

        $breakdown = [
            'vatable_sales' => round($vatableNet, 2),
            'vat_amount' => round($vatAmount, 2),
            'vat_exempt_sales' => round($exemptNet, 2),
            'zero_rated_sales' => round($zeroRatedGross, 2),
            'sc_discount' => 0.0,
            'pwd_discount' => 0.0,
            'naac_discount' => 0.0,
            'solo_parent_discount' => 0.0,
            'other_discount' => round($otherDiscounts, 2),
            'statutory_discount_type' => $statutoryType === '' ? null : $statutoryType,
        ];

        if ($statutoryType !== '') {
            $breakdown[$statutoryType . '_discount'] = round($statutoryDiscount, 2);
        }

        return $breakdown;
    }

    /**
     * True when the configured tax status means output VAT applies.
     *
     * "NON-VAT REGISTERED" contains the substring "VAT", so the negative is
     * checked first — a naive contains('VAT') would treat every non-VAT store
     * as VAT registered and invent output tax that was never collected.
     */
    public static function isVatRegistered(?string $taxStatus): bool
    {
        $status = strtoupper(trim((string) $taxStatus));
        if ($status === '') {
            return false;
        }
        if (str_contains($status, 'NON-VAT') || str_contains($status, 'NONVAT')) {
            return false;
        }

        return str_contains($status, 'VAT');
    }
}
