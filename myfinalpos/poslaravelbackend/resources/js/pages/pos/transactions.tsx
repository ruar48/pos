import { Head } from '@inertiajs/react';
import {
    ArrowLeftRight,
    CalendarRange,
    ChevronDown,
    ChevronRight,
    Download,
    Loader2,
    RefreshCw,
    Search,
    type LucideIcon,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { PageHeader } from '@/components/page-header';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
    fetchTransactionReport,
    type TransactionLineItem,
    type TransactionOrderRow,
    type TransactionPeriodRow,
    type TransactionReportData,
    type TransactionView,
} from '@/lib/transactions-api';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';

/** Server caps per_page at 100 (see TransactionReportService); export walks
 * every page at that ceiling instead of relying on whatever page/perPage
 * the table happens to be showing, so CSV export covers the full date
 * range, not just what's currently on screen. */
const EXPORT_PAGE_SIZE = 100;

async function fetchAllTransactionRows(options: {
    view: TransactionView;
    start: string;
    end: string;
    search?: string;
}): Promise<(TransactionOrderRow | TransactionPeriodRow)[]> {
    const rows: (TransactionOrderRow | TransactionPeriodRow)[] = [];
    let page = 1;

    for (;;) {
        const result = await fetchTransactionReport({
            ...options,
            page,
            perPage: EXPORT_PAGE_SIZE,
        });
        rows.push(...result.rows);
        if (page >= (result.pagination.total_pages || 1)) {
            break;
        }
        page += 1;
    }

    return rows;
}

const TABS: { key: TransactionView; label: string; icon: LucideIcon }[] = [
    { key: 'details', label: 'Details', icon: ArrowLeftRight },
    { key: 'transactions', label: 'Transactions', icon: ArrowLeftRight },
    { key: 'hourly', label: 'Hourly', icon: CalendarRange },
    { key: 'daily', label: 'Daily', icon: CalendarRange },
    { key: 'monthly', label: 'Monthly', icon: CalendarRange },
];

function pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
}

function toIsoDate(date: Date): string {
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function isoDateStartOfMonth(date = new Date()): string {
    return toIsoDate(new Date(date.getFullYear(), date.getMonth(), 1));
}

function formatMoney(value: number): string {
    return value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
}

function shouldShowRefunded(status: string | undefined, value: number): boolean {
    return status === 'refunded' && Math.abs(value) < 0.01;
}

function formatReportMoney(value: number, status?: string): string {
    if (shouldShowRefunded(status, value)) {
        return 'Refunded';
    }

    return `₱${formatMoney(value)}`;
}

function formatRefundColumn(value: number): string {
    if (value < 0.01) {
        return '—';
    }

    return `₱${formatMoney(value)}`;
}

function formatOrderStatus(status: string): string {
    if (status === 'refunded') return 'Refunded';
    if (status === 'partial_refund') return 'Partial refund';
    return 'Completed';
}

function isSplitPayment(row: TransactionOrderRow): boolean {
    if ((row.payments?.length ?? 0) >= 2) {
        return true;
    }

    return row.payment_method.toLowerCase().startsWith('split');
}

function paymentListLabel(row: TransactionOrderRow): string {
    if (isSplitPayment(row) && row.payments && row.payments.length >= 2) {
        return row.payments
            .map(
                (payment) =>
                    `${payment.payment_method} ₱${formatMoney(payment.amount)}`,
            )
            .join(' + ');
    }

    return row.payment_method;
}

/** Excel-safe payment text (ASCII currency label, no ₱ mojibake). */
function paymentCsvLabel(row: TransactionOrderRow): string {
    if (isSplitPayment(row) && row.payments && row.payments.length >= 2) {
        return row.payments
            .map(
                (payment) =>
                    `${payment.payment_method} PHP ${formatMoney(payment.amount)}`,
            )
            .join('; ');
    }

    return row.payment_method;
}

function TransactionPaymentSummary({
    row,
    compact = false,
}: {
    row: TransactionOrderRow;
    compact?: boolean;
}) {
    if (isSplitPayment(row)) {
        return (
            <div className={compact ? 'space-y-0.5' : 'space-y-1'}>
                <p
                    className={cn(
                        'font-semibold text-primary',
                        compact && 'text-xs',
                    )}
                >
                    Split payment
                </p>
                {row.payments && row.payments.length >= 2 ? (
                    row.payments.map((payment, index) => (
                        <p
                            key={`${row.id}-payment-${index}`}
                            className={cn(
                                'text-foreground',
                                compact ? 'text-xs' : undefined,
                            )}
                        >
                            {payment.payment_method}
                            {' · '}
                            <span className="tabular-nums">
                                ₱{formatMoney(payment.amount)}
                            </span>
                            {payment.reference ? (
                                <span className="text-muted-foreground">
                                    {' '}
                                    · Ref {payment.reference}
                                </span>
                            ) : null}
                        </p>
                    ))
                ) : (
                    <p
                        className={cn(
                            'text-foreground',
                            compact ? 'text-xs' : undefined,
                        )}
                    >
                        {row.payment_method}
                    </p>
                )}
            </div>
        );
    }

    return (
        <p className={cn('font-semibold', compact && 'text-xs')}>
            {row.payment_method}
        </p>
    );
}

function statusBadgeClass(status: string): string {
    if (status === 'refunded') {
        return 'border-muted-foreground/30 bg-muted text-muted-foreground';
    }
    if (status === 'partial_refund') {
        return 'border-amber-500/40 bg-amber-50 text-amber-800';
    }
    return 'border-primary/20 bg-primary/5 text-primary';
}

function downloadCsv(filename: string, header: string[], rows: (string | number)[][]) {
    const escape = (v: string | number) => {
        const s = String(v);
        return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const lines = [
        header.join(','),
        ...rows.map((row) => row.map(escape).join(',')),
    ];
    const blob = new Blob(['\uFEFF', lines.join('\n')], {
        type: 'text/csv;charset=utf-8;',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
}

function isOrderRow(
    row: TransactionOrderRow | TransactionPeriodRow,
): row is TransactionOrderRow {
    return 'receipt_number' in row;
}

function isPeriodRow(
    row: TransactionOrderRow | TransactionPeriodRow,
): row is TransactionPeriodRow {
    return 'period_key' in row;
}

function itemDisplayName(item: TransactionLineItem): string {
    if (item.variety_name) {
        return `${item.product_name} · ${item.variety_name}`;
    }

    return item.product_name;
}

function itemNetQuantity(item: TransactionLineItem): number {
    return Math.max(item.quantity - item.refunded_quantity, 0);
}

function itemNetTotal(item: TransactionLineItem): number {
    const netQty = itemNetQuantity(item);
    if (netQty <= 0) {
        return 0;
    }

    return Math.round(item.price * netQty * 100) / 100;
}

function TransactionLineItemsTable({
    items,
    compact = false,
}: {
    items: TransactionLineItem[];
    compact?: boolean;
}) {
    if (items.length === 0) {
        return (
            <p className="text-sm text-muted-foreground">No products recorded.</p>
        );
    }

    return (
        <div className="overflow-hidden rounded-lg border border-border/60 bg-background">
            <table className="w-full text-sm">
                <thead>
                    <tr className="border-b border-border/60 bg-muted/40 text-left text-xs font-semibold tracking-wide text-muted-foreground uppercase">
                        <th className="px-3 py-2">Product</th>
                        <th className="px-3 py-2 text-right">Qty</th>
                        {!compact && (
                            <>
                                <th className="px-3 py-2 text-right">Unit</th>
                                <th className="px-3 py-2 text-right">Total</th>
                            </>
                        )}
                    </tr>
                </thead>
                <tbody>
                    {items.map((item) => {
                        const netQty = itemNetQuantity(item);
                        const fullyRefunded =
                            netQty === 0 && item.refunded_quantity > 0;
                        const partiallyRefunded =
                            item.refunded_quantity > 0 && netQty > 0;

                        return (
                            <tr
                                key={item.order_item_id}
                                className="border-b border-border/40 last:border-0"
                            >
                                <td className="px-3 py-2">
                                    <p
                                        className={cn(
                                            'font-medium text-foreground',
                                            fullyRefunded &&
                                                'text-muted-foreground line-through',
                                        )}
                                    >
                                        {itemDisplayName(item)}
                                    </p>
                                    {fullyRefunded && (
                                        <p className="text-xs text-amber-700">
                                            Fully refunded
                                        </p>
                                    )}
                                    {partiallyRefunded && (
                                        <p className="text-xs text-amber-700">
                                            {item.refunded_quantity} refunded ·{' '}
                                            {netQty} remaining
                                        </p>
                                    )}
                                </td>
                                <td className="px-3 py-2 text-right font-semibold tabular-nums">
                                    {netQty > 0 ? netQty : item.quantity}
                                </td>
                                {!compact && (
                                    <>
                                        <td className="px-3 py-2 text-right tabular-nums text-muted-foreground">
                                            ₱{formatMoney(item.price)}
                                        </td>
                                        <td
                                            className={cn(
                                                'px-3 py-2 text-right font-semibold tabular-nums',
                                                fullyRefunded
                                                    ? 'text-muted-foreground line-through'
                                                    : 'text-foreground',
                                            )}
                                        >
                                            ₱
                                            {formatMoney(
                                                netQty > 0
                                                    ? itemNetTotal(item)
                                                    : item.total,
                                            )}
                                        </td>
                                    </>
                                )}
                            </tr>
                        );
                    })}
                </tbody>
            </table>
        </div>
    );
}

export default function PosTransactions() {
    const today = useMemo(() => toIsoDate(new Date()), []);
    const [tab, setTab] = useState<TransactionView>('details');
    const [start, setStart] = useState(() => isoDateStartOfMonth());
    const [end, setEnd] = useState(today);
    const [search, setSearch] = useState('');
    const [page, setPage] = useState(1);
    const [perPage, setPerPage] = useState(25);
    const [loading, setLoading] = useState(true);
    const [refreshing, setRefreshing] = useState(false);
    const [exporting, setExporting] = useState(false);
    const [data, setData] = useState<TransactionReportData | null>(null);
    const [expandedId, setExpandedId] = useState<number | null>(null);

    const load = useCallback(
        async (opts?: { silent?: boolean; nextPage?: number }) => {
            if (opts?.silent) setRefreshing(true);
            else setLoading(true);

            try {
                const result = await fetchTransactionReport({
                    view: tab,
                    start,
                    end,
                    page: opts?.nextPage ?? page,
                    perPage,
                    search: tab === 'details' || tab === 'transactions' ? search : undefined,
                });
                setData(result);
                setExpandedId(null);
            } catch (error) {
                toast.error(
                    error instanceof Error ? error.message : 'Failed to load transactions',
                );
            } finally {
                setLoading(false);
                setRefreshing(false);
            }
        },
        [tab, start, end, page, perPage, search],
    );

    useEffect(() => {
        void load();
    }, [load]);

    const handleGo = () => {
        setPage(1);
        void load({ nextPage: 1 });
    };

    const handleTabChange = (next: TransactionView) => {
        if (next === tab) return;
        setTab(next);
        setPage(1);
        setData(null);
        setLoading(true);
        setExpandedId(null);
    };

    const handleDownload = async () => {
        if (!data) return;
        setExporting(true);
        try {
            const allRows = await fetchAllTransactionRows({
                view: tab,
                start,
                end,
                search: tab === 'details' || tab === 'transactions' ? search : undefined,
            });
            if (tab === 'details' || tab === 'transactions') {
                const rows = allRows.filter(isOrderRow);
                downloadCsv(
                    `transactions-${tab}-${start}-${end}.csv`,
                    [
                        'Receipt',
                        'Date',
                        'Time',
                        'Cashier',
                        'Customer',
                        'Payment',
                        'Total',
                        'Refunded',
                        'Discount',
                        'Costs',
                        'Profits',
                        'Items',
                        'Status',
                        'Notes',
                    ],
                    rows.map((row) => [
                        row.receipt_number,
                        row.date,
                        row.time,
                        row.cashier_name,
                        row.customer_name,
                        paymentCsvLabel(row),
                        row.status === 'refunded' && row.total < 0.01
                            ? 'Refunded'
                            : row.total,
                        row.refunded_amount,
                        row.discount,
                        row.status === 'refunded' && row.costs < 0.01
                            ? 'Refunded'
                            : row.costs,
                        row.profits,
                        row.items_count,
                        row.status,
                        row.notes ?? '',
                    ]),
                );
            } else {
                const rows = allRows as TransactionPeriodRow[];
                downloadCsv(
                    `transactions-${tab}-${start}-${end}.csv`,
                    [
                        'Period',
                        'Gross Sales',
                        'Refunded',
                        'Net Total',
                        'Transactions',
                        'Refunded Txns',
                        'Items',
                        'Discount',
                        'Costs',
                        'Expenses',
                        'Profits',
                        'Bank Transfer',
                        'Best Seller',
                    ],
                    rows.map((row) => [
                        row.label,
                        row.gross_total,
                        row.refunded_amount,
                        shouldShowRefunded(row.status, row.total)
                            ? 'Refunded'
                            : row.total,
                        row.transactions,
                        row.refunded_transactions,
                        row.items,
                        row.discount,
                        shouldShowRefunded(row.status, row.costs)
                            ? 'Refunded'
                            : row.costs,
                        row.expenses,
                        shouldShowRefunded(row.status, row.profits)
                            ? 'Refunded'
                            : row.profits,
                        shouldShowRefunded(row.status, row.bank_transfer)
                            ? 'Refunded'
                            : row.bank_transfer,
                        row.best_seller,
                    ]),
                );
            }
            toast.success('CSV downloaded');
        } catch (error) {
            toast.error(
                error instanceof Error ? error.message : 'Failed to export CSV',
            );
        } finally {
            setExporting(false);
        }
    };

    const rowsMatchView = data?.view === tab;
    const pagination = rowsMatchView ? data?.pagination : undefined;
    const orderRows = rowsMatchView
        ? (data?.rows ?? []).filter(isOrderRow)
        : [];
    const periodRows = rowsMatchView
        ? (data?.rows ?? []).filter(isPeriodRow)
        : [];

    const periodLabel =
        tab === 'hourly' ? 'Hour' : tab === 'daily' ? 'Day' : 'Month';

    return (
        <>
            <Head title="Transactions" />
            <div className="agri-page-container">
                <PageHeader
                    badge="Operations"
                    title="Transactions"
                    description="Sales reporting for the web admin. Refunds are issued on the POS tablet (Orders); this page shows those refund totals."
                    actions={
                        <>
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={() => load({ silent: true })}
                                disabled={loading || refreshing}
                            >
                                {refreshing ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <RefreshCw className="size-4" />
                                )}
                                Refresh
                            </Button>
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={handleDownload}
                                disabled={!data || data.rows.length === 0 || exporting}
                            >
                                {exporting ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <Download className="size-4" />
                                )}
                                {exporting ? 'Exporting…' : 'Download'}
                            </Button>
                        </>
                    }
                />

                <div className="mt-6 rounded-2xl border border-border/60 bg-card p-4 shadow-sm">
                    <div className="flex flex-wrap items-end gap-3">
                        <div>
                            <Label htmlFor="tx-start">From</Label>
                            <Input
                                id="tx-start"
                                type="date"
                                value={start}
                                max={end}
                                onChange={(e) => setStart(e.target.value)}
                                className="mt-1 w-40"
                            />
                        </div>
                        <div>
                            <Label htmlFor="tx-end">To</Label>
                            <Input
                                id="tx-end"
                                type="date"
                                value={end}
                                min={start}
                                onChange={(e) => setEnd(e.target.value)}
                                className="mt-1 w-40"
                            />
                        </div>
                        <Button onClick={handleGo} disabled={loading}>
                            Go
                        </Button>
                        {(tab === 'details' || tab === 'transactions') && (
                            <div className="min-w-[220px] flex-1">
                                <Label htmlFor="tx-search">Search</Label>
                                <div className="relative mt-1">
                                    <Search className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                    <Input
                                        id="tx-search"
                                        value={search}
                                        onChange={(e) => setSearch(e.target.value)}
                                        onKeyDown={(e) => e.key === 'Enter' && handleGo()}
                                        placeholder="Receipt, cashier, customer, item…"
                                        className="pl-9"
                                    />
                                </div>
                            </div>
                        )}
                    </div>
                    <p className="mt-2 text-xs text-muted-foreground">
                        Defaults to this month through today. Widen the range to see older
                        sales. Transactions can be viewed for a maximum 2-month date range.
                        Refunds are processed on the POS tablet under Orders — not from this
                        admin page.
                    </p>
                </div>

                <div className="mt-4 flex flex-wrap gap-2">
                    {TABS.map(({ key, label, icon: Icon }) => (
                        <button
                            key={key}
                            type="button"
                            onClick={() => handleTabChange(key)}
                            className={cn(
                                'inline-flex items-center gap-2 rounded-full border px-4 py-2 text-sm font-semibold transition-colors',
                                tab === key
                                    ? 'border-primary bg-primary/10 text-primary'
                                    : 'border-border/60 bg-secondary/30 text-muted-foreground hover:bg-secondary/60',
                            )}
                        >
                            <Icon className="size-4" />
                            {label}
                        </button>
                    ))}
                </div>

                {pagination && (
                    <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border/50 bg-primary/5 px-4 py-2.5 text-sm">
                        <span className="font-medium text-primary">
                            Page {pagination.page} of{' '}
                            {pagination.total_pages || 1} · {pagination.total} records
                        </span>
                        <div className="flex flex-wrap items-center gap-2">
                            <select
                                value={perPage}
                                onChange={(e) => {
                                    setPerPage(Number(e.target.value));
                                    setPage(1);
                                }}
                                className="rounded-md border border-border bg-background px-2 py-1.5 text-sm"
                            >
                                <option value={10}>10 rows</option>
                                <option value={25}>25 rows</option>
                                <option value={50}>50 rows</option>
                            </select>
                            <Button
                                variant="outline"
                                size="sm"
                                disabled={pagination.page <= 1 || loading}
                                onClick={() => {
                                    const p = pagination.page - 1;
                                    setPage(p);
                                    void load({ nextPage: p });
                                }}
                            >
                                Previous
                            </Button>
                            <Button
                                variant="outline"
                                size="sm"
                                disabled={
                                    pagination.page >= pagination.total_pages || loading
                                }
                                onClick={() => {
                                    const p = pagination.page + 1;
                                    setPage(p);
                                    void load({ nextPage: p });
                                }}
                            >
                                Next
                            </Button>
                        </div>
                    </div>
                )}

                <div className="mt-4 rounded-2xl border border-border/60 bg-card shadow-sm">
                    {loading ? (
                        <div className="flex items-center justify-center py-20">
                            <Loader2 className="size-8 animate-spin text-primary" />
                        </div>
                    ) : !data || data.rows.length === 0 ? (
                        <p className="py-16 text-center text-muted-foreground">
                            No transactions in this date range.
                        </p>
                    ) : tab === 'details' ? (
                        <div className="divide-y divide-border/60">
                            {orderRows.map((row) => {
                                const open = expandedId === row.id;
                                return (
                                    <div key={row.id} className="p-4">
                                        <div className="flex flex-wrap items-center gap-3">
                                            <button
                                                type="button"
                                                onClick={() =>
                                                    setExpandedId(open ? null : row.id)
                                                }
                                                className="flex min-w-0 flex-1 items-center gap-2 text-left"
                                            >
                                                {open ? (
                                                    <ChevronDown className="size-4 shrink-0 text-muted-foreground" />
                                                ) : (
                                                    <ChevronRight className="size-4 shrink-0 text-muted-foreground" />
                                                )}
                                                <div className="min-w-0">
                                                    <p className="font-bold text-foreground">
                                                        {row.receipt_number}
                                                    </p>
                                                    <p className="text-xs text-muted-foreground">
                                                        {row.date} · {row.time} ·{' '}
                                                        {row.cashier_name}
                                                    </p>
                                                    <p
                                                        className={cn(
                                                            'mt-0.5 text-xs font-semibold',
                                                            isSplitPayment(row)
                                                                ? 'text-primary'
                                                                : 'text-foreground',
                                                        )}
                                                    >
                                                        {isSplitPayment(row)
                                                            ? `Split · ${paymentListLabel(row)}`
                                                            : row.payment_method}
                                                    </p>
                                                </div>
                                            </button>
                                            <p
                                                className={cn(
                                                    'text-lg font-bold tabular-nums',
                                                    row.status === 'refunded'
                                                        ? 'text-muted-foreground'
                                                        : 'text-primary',
                                                )}
                                            >
                                                {formatReportMoney(row.total, row.status)}
                                            </p>
                                            <span
                                                className={cn(
                                                    'rounded-full border px-2.5 py-0.5 text-xs font-semibold',
                                                    statusBadgeClass(row.status),
                                                )}
                                            >
                                                {formatOrderStatus(row.status)}
                                            </span>
                                            {row.refunded_amount > 0.01 && (
                                                <span className="text-xs font-medium text-amber-700 tabular-nums">
                                                    −₱{formatMoney(row.refunded_amount)}
                                                </span>
                                            )}
                                        </div>
                                        {open && (
                                            <div className="mt-3 space-y-3 rounded-xl bg-muted/30 p-3">
                                                <div className="flex flex-wrap items-center justify-between gap-2">
                                                    <p className="font-semibold text-foreground">
                                                        {row.customer_name}
                                                    </p>
                                                    <span className="rounded-full border border-border/60 bg-background px-2.5 py-0.5 text-xs font-semibold text-muted-foreground">
                                                        {row.items_count}{' '}
                                                        {row.items_count === 1
                                                            ? 'item'
                                                            : 'items'}
                                                    </span>
                                                </div>
                                                <TransactionLineItemsTable
                                                    items={row.items ?? []}
                                                />
                                                <div className="grid gap-2 rounded-lg border border-border/50 bg-background p-3 text-xs sm:grid-cols-2 lg:grid-cols-3">
                                                    <div>
                                                        <p className="text-muted-foreground">
                                                            Original total
                                                        </p>
                                                        <p className="font-semibold tabular-nums">
                                                            ₱
                                                            {formatMoney(
                                                                row.gross_total ??
                                                                    row.total,
                                                            )}
                                                        </p>
                                                    </div>
                                                    <div>
                                                        <p className="text-muted-foreground">
                                                            Refunded
                                                        </p>
                                                        <p className="font-semibold tabular-nums text-amber-700">
                                                            ₱
                                                            {formatMoney(
                                                                row.refunded_amount,
                                                            )}
                                                        </p>
                                                    </div>
                                                    <div>
                                                        <p className="text-muted-foreground">
                                                            Net remaining
                                                        </p>
                                                        <p className="font-semibold tabular-nums text-primary">
                                                            ₱
                                                            {formatMoney(row.total)}
                                                        </p>
                                                    </div>
                                                    <div>
                                                        <p className="text-muted-foreground">
                                                            Discount
                                                        </p>
                                                        <p className="font-semibold tabular-nums">
                                                            {row.discount > 0
                                                                ? `₱${formatMoney(row.discount)}`
                                                                : '—'}
                                                        </p>
                                                    </div>
                                                    <div>
                                                        <p className="text-muted-foreground">
                                                            Payment
                                                        </p>
                                                        <TransactionPaymentSummary row={row} />
                                                    </div>
                                                    <div>
                                                        <p className="text-muted-foreground">
                                                            Status
                                                        </p>
                                                        <p className="font-semibold">
                                                            {formatOrderStatus(
                                                                row.status,
                                                            )}
                                                        </p>
                                                    </div>
                                                    {row.notes && (
                                                        <div className="sm:col-span-2 lg:col-span-3">
                                                            <p className="text-muted-foreground">
                                                                Notes
                                                            </p>
                                                            <p className="font-medium whitespace-pre-wrap">
                                                                {row.notes}
                                                            </p>
                                                        </div>
                                                    )}
                                                </div>
                                                {row.items_count <= 0 &&
                                                    row.total > 0.01 && (
                                                        <p className="text-xs text-amber-700">
                                                            Remaining ₱
                                                            {formatMoney(row.total)}{' '}
                                                            is VAT from the original
                                                            sale (items already
                                                            refunded on the POS
                                                            tablet).
                                                        </p>
                                                    )}
                                            </div>
                                        )}
                                    </div>
                                );
                            })}
                        </div>
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full min-w-[900px] text-sm">
                                <thead>
                                    <tr className="border-b border-border/60 bg-primary/10 text-left text-xs font-bold tracking-wide text-primary uppercase">
                                        {tab === 'transactions' ? (
                                            <>
                                                <th className="px-4 py-3">Date</th>
                                                <th className="px-4 py-3">Time</th>
                                                <th className="px-4 py-3">Receipt</th>
                                                <th className="px-4 py-3">Cashier</th>
                                                <th className="px-4 py-3">Payment</th>
                                                <th className="px-4 py-3">Items</th>
                                                <th className="px-4 py-3 text-right">Total</th>
                                                <th className="px-4 py-3 text-right">Refunded</th>
                                                <th className="px-4 py-3 text-right">Discount</th>
                                                <th className="px-4 py-3 text-right">Costs</th>
                                                <th className="px-4 py-3">Status</th>
                                                <th className="px-4 py-3">Notes</th>
                                            </>
                                        ) : (
                                            <>
                                                <th className="px-4 py-3">{periodLabel}</th>
                                                <th className="px-4 py-3 text-right">Gross</th>
                                                <th className="px-4 py-3 text-right">Refunded</th>
                                                <th className="px-4 py-3 text-right">Net</th>
                                                <th className="px-4 py-3 text-right">Txns</th>
                                                <th className="px-4 py-3 text-right">Refunded Txns</th>
                                                <th className="px-4 py-3 text-right">Items</th>
                                                <th className="px-4 py-3 text-right">Discount</th>
                                                <th className="px-4 py-3 text-right">Costs</th>
                                                <th className="px-4 py-3 text-right">Expenses</th>
                                                <th className="px-4 py-3 text-right">Profits</th>
                                                <th className="px-4 py-3 text-right">Bank</th>
                                                {tab === 'hourly' && (
                                                    <th className="px-4 py-3">Best Seller</th>
                                                )}
                                            </>
                                        )}
                                    </tr>
                                </thead>
                                <tbody>
                                    {tab === 'transactions'
                                        ? orderRows.map((row) => (
                                              <tr
                                                  key={row.id}
                                                  className="border-b border-border/40 hover:bg-muted/20"
                                              >
                                                  <td className="px-4 py-3">{row.date}</td>
                                                  <td className="px-4 py-3">{row.time}</td>
                                                  <td className="px-4 py-3 font-semibold">
                                                      {row.receipt_number}
                                                  </td>
                                                  <td className="px-4 py-3">{row.cashier_name}</td>
                                                  <td className="min-w-[10rem] px-4 py-3 align-top">
                                                      <TransactionPaymentSummary
                                                          row={row}
                                                          compact
                                                      />
                                                  </td>
                                                  <td className="max-w-xs px-4 py-3 align-top">
                                                      {row.items && row.items.length > 0 ? (
                                                          <TransactionLineItemsTable
                                                              items={row.items}
                                                              compact
                                                          />
                                                      ) : (
                                                          <span className="text-muted-foreground">
                                                              {row.items_summary ||
                                                                  '—'}
                                                          </span>
                                                      )}
                                                  </td>
                                                  <td
                                                      className={cn(
                                                          'px-4 py-3 text-right font-semibold tabular-nums',
                                                          row.status === 'refunded' &&
                                                              'text-muted-foreground',
                                                      )}
                                                  >
                                                      {formatReportMoney(row.total, row.status)}
                                                  </td>
                                                  <td className="px-4 py-3 text-right tabular-nums text-amber-700">
                                                      {formatRefundColumn(row.refunded_amount)}
                                                  </td>
                                                  <td className="px-4 py-3 text-right tabular-nums">
                                                      {row.discount > 0
                                                          ? `₱${formatMoney(row.discount)}`
                                                          : '—'}
                                                  </td>
                                                  <td
                                                      className={cn(
                                                          'px-4 py-3 text-right tabular-nums',
                                                          row.status === 'refunded'
                                                              ? 'text-muted-foreground'
                                                              : 'text-muted-foreground',
                                                      )}
                                                  >
                                                      {formatReportMoney(row.costs, row.status)}
                                                  </td>
                                                  <td className="px-4 py-3">
                                                      <span
                                                          className={cn(
                                                              'inline-flex rounded-full border px-2.5 py-0.5 text-xs font-semibold',
                                                              statusBadgeClass(row.status),
                                                          )}
                                                      >
                                                          {formatOrderStatus(row.status)}
                                                      </span>
                                                  </td>
                                                  <td className="max-w-[12rem] px-4 py-3 text-muted-foreground">
                                                      {row.notes || '—'}
                                                  </td>
                                              </tr>
                                          ))
                                        : periodRows.map((row) => (
                                              <tr
                                                  key={row.period_key}
                                                  className="border-b border-border/40 hover:bg-muted/20"
                                              >
                                                  <td className="px-4 py-3 font-semibold">
                                                      {row.label}
                                                  </td>
                                                  <td className="px-4 py-3 text-right tabular-nums">
                                                      ₱{formatMoney(row.gross_total)}
                                                  </td>
                                                  <td className="px-4 py-3 text-right tabular-nums text-amber-700">
                                                      {formatRefundColumn(row.refunded_amount)}
                                                  </td>
                                                  <td
                                                      className={cn(
                                                          'px-4 py-3 text-right font-semibold tabular-nums',
                                                          row.status === 'refunded' &&
                                                              'text-muted-foreground',
                                                      )}
                                                  >
                                                      {formatReportMoney(row.total, row.status)}
                                                  </td>
                                                  <td className="px-4 py-3 text-right tabular-nums">
                                                      {row.transactions}
                                                  </td>
                                                  <td className="px-4 py-3 text-right tabular-nums text-amber-700">
                                                      {row.refunded_transactions > 0
                                                          ? row.refunded_transactions
                                                          : '—'}
                                                  </td>
                                                  <td className="px-4 py-3 text-right tabular-nums">
                                                      {row.items.toFixed(1)}
                                                  </td>
                                                  <td className="px-4 py-3 text-right tabular-nums">
                                                      {formatReportMoney(
                                                          row.discount,
                                                          row.status,
                                                      )}
                                                  </td>
                                                  <td
                                                      className={cn(
                                                          'px-4 py-3 text-right tabular-nums',
                                                          row.status === 'refunded' &&
                                                              'text-muted-foreground',
                                                      )}
                                                  >
                                                      {formatReportMoney(row.costs, row.status)}
                                                  </td>
                                                  <td className="px-4 py-3 text-right tabular-nums">
                                                      {formatReportMoney(
                                                          row.expenses,
                                                          row.status,
                                                      )}
                                                  </td>
                                                  <td
                                                      className={cn(
                                                          'px-4 py-3 text-right font-semibold tabular-nums',
                                                          row.status === 'refunded'
                                                              ? 'text-muted-foreground'
                                                              : row.profits >= 0
                                                                ? 'text-primary'
                                                                : 'text-destructive',
                                                      )}
                                                  >
                                                      {formatReportMoney(row.profits, row.status)}
                                                  </td>
                                                  <td className="px-4 py-3 text-right tabular-nums">
                                                      {formatReportMoney(
                                                          row.bank_transfer,
                                                          row.status,
                                                      )}
                                                  </td>
                                                  {tab === 'hourly' && (
                                                      <td className="max-w-[200px] px-4 py-3 text-muted-foreground">
                                                          {row.best_seller || '—'}
                                                      </td>
                                                  )}
                                              </tr>
                                          ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            </div>

        </>
    );
}

PosTransactions.layout = {
    breadcrumbs: [
        { title: 'Dashboard', href: dashboard() },
        { title: 'Transactions', href: '/pos/transactions' },
    ],
};
