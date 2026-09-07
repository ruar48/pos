# X / Z Readings and BIR compliance

## What this system does

Every completed sale is stamped with the register (`orders.terminal_id`) and
the open shift (`orders.register_session_id`). At checkout, `BirSalesBreakdown`
splits the sale into the classes BIR reports on and stores the result **on the
order**:

| Column | Meaning |
| --- | --- |
| `vatable_sales` | Sales subject to output VAT |
| `vat_exempt_sales` | Exempt sales, including all SC/PWD/NAAC/solo-parent sales |
| `zero_rated_sales` | Zero-rated sales |
| `sc_discount`, `pwd_discount`, `naac_discount`, `solo_parent_discount` | Statutory discounts, each reported on its own line |
| `statutory_discount_type`, `statutory_id_number`, `statutory_customer_name` | Who the statutory discount was granted to |

The split is captured at the time of sale and never recomputed. Reclassifying
a product later cannot rewrite a reading that has already been filed.

`pos_terminal_counters` holds the figures BIR requires to be monotonic — the
accumulated grand total, the Z counter and the reset counter — one row per
machine. Only a Z reading updates them, inside a transaction with the row
locked, so two lanes closing at once can never be issued the same Z number.

## Where to take a reading

- **Register (Flutter):** drawer → System → *X / Z Reading*
- **Admin (Laravel):** sidebar → Management → *X / Z Reading*

Both call the same service, so figures and the Z counter are identical
whichever one is used.

X may be taken any number of times and changes nothing. Z closes the shift and
is irreversible; it requires the cash drawer PIN.

## VAT treatment

This POS prices **VAT-exclusive** — `PosHelpers::saleVatAndTotal` computes
`net + net × rate`, i.e. VAT is added on top of the shelf price. The breakdown
follows that convention so the reading reports what customers were actually
charged.

> **Worth reviewing with your accountant.** Philippine VAT-registered sellers
> are generally required to display VAT-inclusive prices. If you switch
> checkout to inclusive pricing, pass `pricesIncludeVat: true` to
> `BirSalesBreakdown::compute` — the inclusive path is implemented and tested,
> but changing it will change the totals customers pay, so it is deliberately
> not switched on automatically.

Statutory sales are made VAT-exempt **before** the 20% is applied, per the
rules. Taking 20% off a VAT-bearing price would overstate the discount and
understate the exempt sale.

Set a product's class in `products.vat_classification`
(`vatable` | `vat_exempt` | `zero_rated`). New products default to `vatable`.

## Before you can file these

Correct figures are necessary but **not sufficient** for accreditation. Still
outstanding, none of which is a code change this repo can make for you:

1. **Register the machine with BIR** and fill in Settings → the MIN and machine
   serial number. Until they are set, both the register and admin screens warn
   that the machine registration is incomplete. They are intentionally blank by
   default — a placeholder MIN on a filed document is worse than an obvious gap.
2. **Permit to Use (PTU)** for the machine, recorded in the same settings.
3. **Electronic journal / audit trail.** BIR requires a permanent, tamper-evident
   record of every transaction. Readings are stored in `pos_register_readings`
   and never deleted by the app, but there is no separate immutable journal or
   backup routine here.
4. **Accreditation inspection.** BIR must inspect and accredit the system. That
   is a filing process, not a software feature.
5. **Sequential invoice numbering.** Invoice numbers derive from the order id
   (`INV-000030`), which is gapless and never resets — but it is a single
   global sequence shared by all terminals, not per-machine series. Confirm
   with your BIR RDO whether that satisfies your permit's series range.

## Verifying the maths

`tests/Unit/BirSalesBreakdownTest.php` covers both pricing conventions, the
SC/PWD/NAAC/solo-parent routing, the exempt/zero-rated buckets, and the
`NON-VAT REGISTERED` trap (the string contains "VAT", so a naive check reads a
non-VAT store as VAT-registered and invents output tax).

```bash
php artisan test --filter=BirSalesBreakdownTest
```
