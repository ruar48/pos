import {
    Check,
    FileSpreadsheet,
    FileText,
    Gift,
    Loader2,
    Minus,
    Plus,
    RefreshCw,
    Search,
} from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
    downloadLoyaltyActivityPdf,
    formatActivityDate,
    formatActivityTime,
} from '@/lib/loyalty-activity-pdf';
import { downloadLoyaltyActivityExcel, fetchLoyaltyActivity } from '@/lib/loyalty-api';
import type {
    LoyaltyActivityAction,
    LoyaltyActivityRow,
    LoyaltyActivityTotals,
} from '@/lib/loyalty-api';
import { cn } from '@/lib/utils';

const EXPORT_LIMIT = 5000;

const actionFilters: { key: LoyaltyActivityAction | ''; label: string }[] = [
    { key: '', label: 'All' },
    { key: 'earn', label: 'Earned' },
    { key: 'redeem', label: 'Redeemed' },
    { key: 'open_card', label: 'Card opened' },
    { key: 'refund', label: 'Refund' },
];

const actionStyles: Record<string, { label: string; className: string }> = {
    earn: { label: 'Earned', className: 'bg-primary/10 text-primary' },
    redeem: { label: 'Redeemed', className: 'bg-amber-500/10 text-amber-600' },
    open_card: { label: 'Card opened', className: 'bg-secondary text-muted-foreground' },
    refund: { label: 'Refund', className: 'bg-destructive/10 text-destructive' },
};

function formatInt(value: number): string {
    return value.toLocaleString();
}

function TotalTile({
    label,
    value,
    hint,
    tone,
}: {
    label: string;
    value: string;
    hint: string;
    tone: 'primary' | 'amber';
}) {
    return (
        <div className="agri-stat-card">
            <span className="agri-stat-label">{label}</span>
            <p
                className={cn(
                    'agri-stat-value mt-2',
                    tone === 'amber' ? 'text-amber-600' : 'text-primary',
                )}
            >
                {value}
            </p>
            <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
        </div>
    );
}

export function LoyaltyActivityPanel() {
    const [action, setAction] = useState<LoyaltyActivityAction | ''>('');
    const [query, setQuery] = useState('');
    const [from, setFrom] = useState('');
    const [to, setTo] = useState('');
    const [rows, setRows] = useState<LoyaltyActivityRow[]>([]);
    const [totals, setTotals] = useState<LoyaltyActivityTotals | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [exporting, setExporting] = useState<'excel' | 'pdf' | null>(null);

    const exportExcel = async () => {
        setExporting('excel');

        try {
            await downloadLoyaltyActivityExcel({ action, q: query, from, to });
        } catch (err) {
            toast.error(err instanceof Error ? err.message : 'Excel download failed');
        } finally {
            setExporting(null);
        }
    };

    // The table only shows the latest 200, so the PDF fetches the full set.
    const exportPdf = async () => {
        setExporting('pdf');

        try {
            const filters = { action, q: query, from, to };
            const res = await fetchLoyaltyActivity(filters, EXPORT_LIMIT);
            await downloadLoyaltyActivityPdf(res.data ?? [], res.totals, filters);
        } catch (err) {
            toast.error(err instanceof Error ? err.message : 'PDF download failed');
        } finally {
            setExporting(null);
        }
    };

    const load = useCallback(async () => {
        setLoading(true);
        setError(null);

        try {
            const res = await fetchLoyaltyActivity({ action, q: query, from, to });
            setRows(res.data ?? []);
            setTotals(res.totals ?? null);
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Failed to load points activity');
        } finally {
            setLoading(false);
        }
    }, [action, query, from, to]);

    useEffect(() => {
        const timer = setTimeout(() => load(), query.trim() === '' ? 0 : 250);

        return () => clearTimeout(timer);
    }, [load, query]);

    return (
        <>
            <div className="grid gap-4 sm:grid-cols-2">
                <TotalTile
                    label="Points earned"
                    value={`+${formatInt(totals?.earned ?? 0)}`}
                    hint={`${formatInt(totals?.earn_count ?? 0)} purchases`}
                    tone="primary"
                />
                <TotalTile
                    label="Points redeemed"
                    value={`-${formatInt(totals?.redeemed ?? 0)}`}
                    hint={`${formatInt(totals?.redeem_count ?? 0)} redemptions`}
                    tone="amber"
                />
            </div>

            <div className="agri-card space-y-3 p-4">
                <div className="flex flex-col gap-3 md:flex-row">
                    <div className="relative flex-1">
                        <Search className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                        <Input
                            placeholder="Search customer name..."
                            value={query}
                            onChange={(e) => setQuery(e.target.value)}
                            className="border-0 bg-secondary/40 pl-9"
                        />
                    </div>
                    <div className="flex items-center gap-2">
                        <Input
                            type="date"
                            aria-label="From date"
                            value={from}
                            onChange={(e) => setFrom(e.target.value)}
                            className="w-auto"
                        />
                        <span className="text-sm text-muted-foreground">to</span>
                        <Input
                            type="date"
                            aria-label="To date"
                            value={to}
                            onChange={(e) => setTo(e.target.value)}
                            className="w-auto"
                        />
                    </div>
                    <Button variant="outline" onClick={load} disabled={loading}>
                        {loading ? (
                            <Loader2 className="size-4 animate-spin" />
                        ) : (
                            <RefreshCw className="size-4" />
                        )}
                        Refresh
                    </Button>
                    <Button
                        variant="outline"
                        onClick={exportExcel}
                        disabled={exporting !== null || rows.length === 0}
                    >
                        {exporting === 'excel' ? (
                            <Loader2 className="size-4 animate-spin" />
                        ) : (
                            <FileSpreadsheet className="size-4" />
                        )}
                        Excel
                    </Button>
                    <Button
                        variant="outline"
                        onClick={exportPdf}
                        disabled={exporting !== null || rows.length === 0}
                    >
                        {exporting === 'pdf' ? (
                            <Loader2 className="size-4 animate-spin" />
                        ) : (
                            <FileText className="size-4" />
                        )}
                        PDF
                    </Button>
                </div>
                <div className="flex flex-wrap gap-2">
                    {actionFilters.map((filter) => {
                        const selected = action === filter.key;

                        return (
                            <button
                                key={filter.label}
                                type="button"
                                onClick={() => setAction(filter.key)}
                                className={cn(
                                    'inline-flex shrink-0 items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm font-semibold transition-colors',
                                    selected
                                        ? 'border-primary bg-primary/10 text-primary'
                                        : 'border-border/60 bg-secondary/40 text-muted-foreground hover:bg-secondary/70',
                                )}
                            >
                                {selected && <Check className="size-3.5" />}
                                {filter.label}
                            </button>
                        );
                    })}
                </div>
            </div>

            <div className="agri-card overflow-hidden">
                {loading && rows.length === 0 ? (
                    <div className="flex items-center justify-center gap-2 py-16 text-muted-foreground">
                        <Loader2 className="size-5 animate-spin" />
                        Loading...
                    </div>
                ) : error ? (
                    <p className="py-16 text-center text-sm text-destructive">{error}</p>
                ) : rows.length === 0 ? (
                    <div className="flex flex-col items-center justify-center gap-3 py-16 text-center">
                        <Gift className="size-10 text-muted-foreground" />
                        <p className="text-sm font-medium text-foreground">
                            No points activity for these filters
                        </p>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full min-w-[760px] text-sm">
                            <thead className="border-b border-border/60 bg-secondary/30 text-left text-xs font-semibold text-muted-foreground uppercase">
                                <tr>
                                    <th className="px-4 py-3">Date</th>
                                    <th className="px-4 py-3">Customer</th>
                                    <th className="px-4 py-3">Type</th>
                                    <th className="px-4 py-3 text-right">Points</th>
                                    <th className="px-4 py-3 text-right">Balance</th>
                                    <th className="px-4 py-3">Receipt</th>
                                    <th className="px-4 py-3">Cashier</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-border/40">
                                {rows.map((row) => {
                                    const style = actionStyles[row.action] ?? {
                                        label: row.action,
                                        className: 'bg-secondary text-muted-foreground',
                                    };
                                    const positive = row.points_change > 0;
                                    const negative = row.points_change < 0;

                                    return (
                                        <tr key={row.id} title={row.description}>
                                            <td className="px-4 py-3 whitespace-nowrap text-muted-foreground">
                                                {formatActivityDate(row.created_at)}
                                                <span className="block text-xs">
                                                    {formatActivityTime(row.created_at)}
                                                </span>
                                            </td>
                                            <td className="px-4 py-3 font-medium text-foreground">
                                                {row.customer_name ?? `Customer #${row.customer_id}`}
                                            </td>
                                            <td className="px-4 py-3">
                                                <span
                                                    className={cn(
                                                        'rounded-full px-2 py-0.5 text-[11px] font-semibold',
                                                        style.className,
                                                    )}
                                                >
                                                    {style.label}
                                                </span>
                                            </td>
                                            <td
                                                className={cn(
                                                    'px-4 py-3 text-right font-bold tabular-nums',
                                                    positive && 'text-primary',
                                                    negative && 'text-amber-600',
                                                    !positive && !negative && 'text-muted-foreground',
                                                )}
                                            >
                                                <span className="inline-flex items-center gap-0.5">
                                                    {positive && <Plus className="size-3" />}
                                                    {negative && <Minus className="size-3" />}
                                                    {formatInt(Math.abs(row.points_change))}
                                                </span>
                                            </td>
                                            <td className="px-4 py-3 text-right tabular-nums text-muted-foreground">
                                                {formatInt(row.points_balance_after)}
                                            </td>
                                            <td className="px-4 py-3 font-mono text-xs">
                                                {row.receipt_number ?? '—'}
                                            </td>
                                            <td className="px-4 py-3 text-muted-foreground">
                                                {row.actor_name ?? '—'}
                                            </td>
                                        </tr>
                                    );
                                })}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>
            {rows.length >= 200 && (
                <p className="text-center text-xs text-muted-foreground">
                    Showing the latest 200 entries. Narrow the dates to see older activity.
                </p>
            )}
        </>
    );
}
