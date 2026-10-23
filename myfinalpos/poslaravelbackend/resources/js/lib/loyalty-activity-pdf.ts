import type {
    LoyaltyActivityFilters,
    LoyaltyActivityRow,
    LoyaltyActivityTotals,
} from '@/lib/loyalty-api';

export const loyaltyActionLabels: Record<string, string> = {
    earn: 'Earned',
    redeem: 'Redeemed',
    open_card: 'Card opened',
    refund: 'Refund',
};

function parseDate(value: string): Date | null {
    const date = new Date(value.replace(' ', 'T'));

    return Number.isNaN(date.getTime()) ? null : date;
}

/** "Sep 5, 2026" */
export function formatActivityDate(value: string): string {
    const date = parseDate(value);

    return date
        ? date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
        : value;
}

/** "10:05 AM" */
export function formatActivityTime(value: string): string {
    const date = parseDate(value);

    return date ? date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }) : '';
}

function periodLabel(filters: LoyaltyActivityFilters): string {
    const from = filters.from ? formatActivityDate(filters.from) : null;
    const to = filters.to ? formatActivityDate(filters.to) : null;

    if (from && to) {
        return `${from} to ${to}`;
    }

    if (from) {
        return `From ${from}`;
    }

    if (to) {
        return `Up to ${to}`;
    }

    return 'All dates';
}

export async function downloadLoyaltyActivityPdf(
    rows: LoyaltyActivityRow[],
    totals: LoyaltyActivityTotals,
    filters: LoyaltyActivityFilters,
): Promise<void> {
    const [{ jsPDF }, { default: autoTable }] = await Promise.all([
        import('jspdf'),
        import('jspdf-autotable'),
    ]);

    const doc = new jsPDF({ orientation: 'landscape', unit: 'pt', format: 'a4' });

    doc.setFontSize(16);
    doc.text('Loyalty Points Activity', 40, 40);
    doc.setFontSize(10);
    doc.text(`Period: ${periodLabel(filters)}`, 40, 58);
    doc.text(
        `Points earned: ${totals.earned.toLocaleString()} (${totals.earn_count.toLocaleString()} purchases)` +
            `     Points redeemed: ${totals.redeemed.toLocaleString()} (${totals.redeem_count.toLocaleString()} redemptions)`,
        40,
        72,
    );

    autoTable(doc, {
        startY: 86,
        head: [['Date', 'Time', 'Customer', 'Type', 'Points', 'Balance', 'Receipt', 'Cashier']],
        body: rows.map((row) => [
            formatActivityDate(row.created_at),
            formatActivityTime(row.created_at),
            row.customer_name ?? `Customer #${row.customer_id}`,
            loyaltyActionLabels[row.action] ?? row.action,
            row.points_change > 0 ? `+${row.points_change}` : String(row.points_change),
            row.points_balance_after.toLocaleString(),
            row.receipt_number ?? '',
            row.actor_name ?? '',
        ]),
        styles: { fontSize: 9 },
        headStyles: { fillColor: [22, 101, 52] },
        columnStyles: { 4: { halign: 'right' }, 5: { halign: 'right' } },
    });

    doc.save(`loyalty_points_activity_${new Date().toISOString().slice(0, 10)}.pdf`);
}
