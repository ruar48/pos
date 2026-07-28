import { Head } from '@inertiajs/react';
import {
    Banknote,
    CircleHelp,
    Loader2,
    RefreshCw,
    ShoppingBag,
    Wallet,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
    fetchDashboardData,
    type DashboardData,
    type DashboardGranularity,
    type DashboardSalesPoint,
} from '@/lib/dashboard-api';
import { cn } from '@/lib/utils';

type RangeKey = 'today' | 'yesterday' | 'week' | 'month' | 'custom';

function pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
}

function toIsoDate(date: Date): string {
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function rangeForKey(key: Exclude<RangeKey, 'custom'>): {
    start: string;
    end: string;
} {
    const today = new Date();
    if (key === 'today') {
        const t = toIsoDate(today);
        return { start: t, end: t };
    }
    if (key === 'yesterday') {
        const y = new Date(today);
        y.setDate(y.getDate() - 1);
        const t = toIsoDate(y);
        return { start: t, end: t };
    }
    if (key === 'week') {
        const day = today.getDay();
        const diff = (day + 6) % 7;
        const monday = new Date(today);
        monday.setDate(today.getDate() - diff);
        return { start: toIsoDate(monday), end: toIsoDate(today) };
    }
    const first = new Date(today.getFullYear(), today.getMonth(), 1);
    return { start: toIsoDate(first), end: toIsoDate(today) };
}

function formatMoney(value: number, withSymbol = true): string {
    const formatted = value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
    return withSymbol ? `₱${formatted}` : formatted;
}

function formatItems(value: number): string {
    return value.toLocaleString(undefined, {
        minimumFractionDigits: value % 1 === 0 ? 0 : 2,
        maximumFractionDigits: 2,
    });
}

function formatSyncedAt(iso: string | null): string {
    if (!iso) {
        return 'No transactions yet';
    }
    const d = new Date(iso);
    return d.toLocaleString(undefined, {
        weekday: 'long',
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
    });
}

function formatRangePickerLabel(start: string, end: string): string {
    const fmt = (iso: string, endOfDay: boolean) => {
        const d = new Date(`${iso}T12:00:00`);
        const date = d.toLocaleDateString(undefined, {
            month: 'short',
            day: 'numeric',
        });
        return endOfDay
            ? `${date}, 11:59pm`
            : `${date}, 12:00am`;
    };
    if (start === end) {
        return `${fmt(start, false)} - ${fmt(end, true)}`;
    }
    return `${fmt(start, false)} - ${fmt(end, true)}`;
}

function greetingForHour(): string {
    const hour = new Date().getHours();
    if (hour < 12) {
        return 'Good morning';
    }
    if (hour < 17) {
        return 'Good afternoon';
    }
    return 'Good evening';
}

const GRANULARITY_TABS: { key: DashboardGranularity; label: string }[] = [
    { key: 'hourly', label: 'Hourly' },
    { key: 'daily', label: 'Daily' },
    { key: 'monthly', label: 'Monthly' },
];

type KpiTone = 'orange' | 'teal' | 'green' | 'coral';

const KPI_STYLES: Record<KpiTone, string> = {
    orange: 'bg-gradient-to-br from-[#f5a962] to-[#e8924a] text-white',
    teal: 'bg-gradient-to-br from-[#5ec4b8] to-[#45b5a8] text-white',
    green: 'bg-gradient-to-br from-[#6fcf97] to-[#56c486] text-white',
    coral: 'bg-gradient-to-br from-[#f2847a] to-[#e86a5e] text-white',
};

type KpiCardProps = {
    label: string;
    value: string;
    tone: KpiTone;
};

function KpiCard({ label, value, tone }: KpiCardProps) {
    return (
        <div
            className={cn(
                'flex min-h-[88px] flex-col justify-center rounded-2xl px-4 py-3 shadow-sm sm:min-h-[96px] sm:px-5',
                KPI_STYLES[tone],
            )}
        >
            <p className="text-xs font-medium leading-tight opacity-95 sm:text-sm">
                {label}
            </p>
            <p className="mt-1.5 text-xl font-bold tracking-tight sm:text-2xl">
                {value}
            </p>
        </div>
    );
}

function PaymentIcon({ type }: { type: 'cash' | 'bank' | 'other' }) {
    if (type === 'cash') {
        return (
            <span className="flex size-8 items-center justify-center rounded-full bg-emerald-100 text-emerald-600">
                <Wallet className="size-4" />
            </span>
        );
    }
    if (type === 'bank') {
        return (
            <span className="flex size-8 items-center justify-center rounded-full bg-orange-100 text-orange-600">
                <Banknote className="size-4" />
            </span>
        );
    }
    return (
        <span className="flex size-8 items-center justify-center rounded-full bg-slate-100 text-slate-600">
            <ShoppingBag className="size-4" />
        </span>
    );
}

function AttendanceStatusPill({
    label,
    active,
    time,
    tone,
}: {
    label: string;
    active: boolean;
    time?: string | null;
    tone: 'teal' | 'orange';
}) {
    const toneClass = tone === 'teal' ? 'bg-teal-500' : 'bg-orange-500';
    return (
        <div className="text-right">
            <div className="flex items-center justify-end gap-1.5 text-[11px] font-semibold text-muted-foreground">
                <span
                    className={cn(
                        'size-2 rounded-full',
                        active ? toneClass : 'bg-border',
                    )}
                />
                {label}
            </div>
            <p
                className={cn(
                    'text-xs font-bold',
                    active ? 'text-foreground' : 'text-muted-foreground',
                )}
            >
                {active && time ? time : '—'}
            </p>
        </div>
    );
}

function SalesLineChart({
    series,
    maxSales,
}: {
    series: DashboardSalesPoint[];
    maxSales: number;
}) {
    const { path, areaPath } = useMemo(() => {
        if (series.length === 0) {
            return { path: '', areaPath: '' };
        }

        const width = 1000;
        const height = 220;
        const padding = 12;
        const innerW = width - padding * 2;
        const innerH = height - padding * 2;

        const coords = series.map((point, index) => {
            const x =
                padding +
                (series.length === 1
                    ? innerW / 2
                    : (index / (series.length - 1)) * innerW);
            const ratio = maxSales > 0 ? point.net_sales / maxSales : 0;
            const y = padding + innerH - ratio * innerH;
            return { x, y };
        });

        const line = coords.map((c) => `${c.x},${c.y}`).join(' ');
        const area = [
            `M ${coords[0].x},${height - padding}`,
            ...coords.map((c) => `L ${c.x},${c.y}`),
            `L ${coords[coords.length - 1].x},${height - padding}`,
            'Z',
        ].join(' ');

        return { path: line, areaPath: area };
    }, [series, maxSales]);

    if (series.length === 0) {
        return (
            <p className="py-20 text-center text-sm text-muted-foreground">
                No sales in this period.
            </p>
        );
    }

    return (
        <div className="relative h-52 w-full sm:h-56">
            <svg
                viewBox="0 0 1000 220"
                preserveAspectRatio="none"
                className="h-full w-full"
                aria-hidden
            >
                <defs>
                    <linearGradient id="salesArea" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="#f5a962" stopOpacity="0.35" />
                        <stop offset="100%" stopColor="#f5a962" stopOpacity="0.02" />
                    </linearGradient>
                </defs>
                {areaPath && (
                    <path d={areaPath} fill="url(#salesArea)" />
                )}
                <polyline
                    fill="none"
                    stroke="#e8924a"
                    strokeWidth="3"
                    strokeLinejoin="round"
                    strokeLinecap="round"
                    points={path}
                />
            </svg>
            <div className="pointer-events-none absolute inset-x-0 bottom-0 flex justify-between gap-1 overflow-hidden px-1">
                {series.map((point) => (
                    <span
                        key={point.key}
                        className="min-w-0 flex-1 truncate text-center text-[10px] text-muted-foreground"
                        title={`₱${formatMoney(point.net_sales, false)}`}
                    >
                        {point.label}
                    </span>
                ))}
            </div>
        </div>
    );
}

export default function Dashboard() {
    const [start, setStart] = useState(() => rangeForKey('week').start);
    const [end, setEnd] = useState(() => rangeForKey('week').end);
    const [granularity, setGranularity] =
        useState<DashboardGranularity>('hourly');
    const [data, setData] = useState<DashboardData | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [showDatePicker, setShowDatePicker] = useState(false);

    const load = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const payload = await fetchDashboardData(start, end, granularity);
            setData(payload);
        } catch (e) {
            const message =
                e instanceof Error ? e.message : 'Failed to load dashboard';
            setError(message);
            toast.error(message);
        } finally {
            setLoading(false);
        }
    }, [start, end, granularity]);

    useEffect(() => {
        void load();
    }, [load]);

    useEffect(() => {
        if (start !== end && granularity === 'hourly') {
            setGranularity('daily');
        }
    }, [start, end, granularity]);

    const maxSales = useMemo(
        () => Math.max(...(data?.sales_series ?? []).map((p) => p.net_sales), 1),
        [data],
    );

    const metrics = data?.metrics ?? {
        net_sales: 0,
        total_discounts: 0,
        order_count: 0,
        cogs: 0,
        items_sold: 0,
        profit: 0,
        refunded_amount: 0,
        unpaid_orders: 0,
        online_orders: 0,
        gross_sales: 0,
        average_order_value: 0,
        margin_percent: 0,
    };
    const isSingleDay = start === end;
    const storeName = data?.store_name ?? 'Agriculture POS';
    const showContent = !loading || data !== null;

    return (
        <>
            <Head title="Dashboard" />
            <div className="flex min-h-full flex-col bg-[#f4f6f5]">
                {/* Top bar — Dashboard title, last synced, date range */}
                <div className="border-b border-border/50 bg-background px-4 py-3 sm:px-6">
                    <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                        <div className="flex items-center gap-2">
                            <h1 className="text-lg font-semibold text-foreground">
                                Dashboard
                            </h1>
                            <CircleHelp
                                className="size-4 text-muted-foreground"
                                aria-label="Store overview for the selected date range"
                            />
                        </div>
                        <div className="flex flex-wrap items-center gap-3 lg:justify-end">
                            <p className="text-xs text-muted-foreground sm:text-sm">
                                <span className="font-medium text-foreground">
                                    Last synced:
                                </span>{' '}
                                {formatSyncedAt(data?.last_synced_at ?? null)}
                            </p>
                            <div className="relative">
                                <button
                                    type="button"
                                    onClick={() =>
                                        setShowDatePicker((open) => !open)
                                    }
                                    className="flex items-center gap-2 rounded-lg border border-border bg-background px-3 py-2 text-xs font-medium text-foreground shadow-sm hover:bg-secondary/50 sm:text-sm"
                                >
                                    {formatRangePickerLabel(start, end)}
                                </button>
                                {showDatePicker && (
                                    <div className="absolute right-0 z-20 mt-2 w-72 rounded-xl border border-border bg-background p-4 shadow-lg">
                                        <div className="space-y-3">
                                            <div>
                                                <label
                                                    htmlFor="dash-start"
                                                    className="text-xs text-muted-foreground"
                                                >
                                                    From
                                                </label>
                                                <Input
                                                    id="dash-start"
                                                    type="date"
                                                    value={start}
                                                    onChange={(e) =>
                                                        setStart(
                                                            e.target.value,
                                                        )
                                                    }
                                                    className="mt-1 h-9"
                                                />
                                            </div>
                                            <div>
                                                <label
                                                    htmlFor="dash-end"
                                                    className="text-xs text-muted-foreground"
                                                >
                                                    To
                                                </label>
                                                <Input
                                                    id="dash-end"
                                                    type="date"
                                                    value={end}
                                                    onChange={(e) =>
                                                        setEnd(e.target.value)
                                                    }
                                                    className="mt-1 h-9"
                                                />
                                            </div>
                                            <div className="flex flex-wrap gap-2">
                                                {(
                                                    [
                                                        'today',
                                                        'yesterday',
                                                        'week',
                                                        'month',
                                                    ] as const
                                                ).map((key) => (
                                                    <button
                                                        key={key}
                                                        type="button"
                                                        onClick={() => {
                                                            const r =
                                                                rangeForKey(
                                                                    key,
                                                                );
                                                            setStart(r.start);
                                                            setEnd(r.end);
                                                        }}
                                                        className="rounded-full border border-border px-2.5 py-1 text-xs capitalize hover:bg-secondary"
                                                    >
                                                        {key === 'week'
                                                            ? 'This week'
                                                            : key === 'month'
                                                              ? 'This month'
                                                              : key}
                                                    </button>
                                                ))}
                                            </div>
                                            <Button
                                                type="button"
                                                size="sm"
                                                className="w-full"
                                                onClick={() =>
                                                    setShowDatePicker(false)
                                                }
                                            >
                                                Apply
                                            </Button>
                                        </div>
                                    </div>
                                )}
                            </div>
                            <Button
                                type="button"
                                variant="ghost"
                                size="icon"
                                className="size-8 shrink-0"
                                onClick={() => void load()}
                                disabled={loading}
                                title="Refresh"
                            >
                                {loading ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <RefreshCw className="size-4" />
                                )}
                            </Button>
                        </div>
                    </div>
                </div>

                <div className="flex-1 space-y-5 px-4 py-5 sm:px-6">
                    {error && (
                        <div className="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800">
                            {error}
                        </div>
                    )}
                    {loading && !data ? (
                        <div className="flex min-h-[320px] items-center justify-center">
                            <Loader2 className="size-8 animate-spin text-primary" />
                        </div>
                    ) : showContent ? (
                        <>
                            {/* KPI row 1 — 5 cards */}
                            <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
                                <KpiCard
                                    label="Gross Sales"
                                    value={formatMoney(metrics.gross_sales)}
                                    tone="orange"
                                />
                                <KpiCard
                                    label="Net Sales After Refunds"
                                    value={formatMoney(metrics.net_sales)}
                                    tone="teal"
                                />
                                <KpiCard
                                    label="Total Discounts"
                                    value={formatMoney(metrics.total_discounts)}
                                    tone="green"
                                />
                                <KpiCard
                                    label="No. of Transactions"
                                    value={metrics.order_count.toLocaleString()}
                                    tone="orange"
                                />
                                <KpiCard
                                    label="Cost of Goods"
                                    value={formatMoney(metrics.cogs, false)}
                                    tone="teal"
                                />
                            </div>

                            {/* KPI row 2 — 5 cards */}
                            <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
                                <KpiCard
                                    label="No. of Items"
                                    value={formatItems(metrics.items_sold)}
                                    tone="green"
                                />
                                <KpiCard
                                    label="Profit"
                                    value={formatMoney(metrics.profit)}
                                    tone="orange"
                                />
                                <KpiCard
                                    label="Refunds Deducted"
                                    value={formatMoney(metrics.refunded_amount)}
                                    tone="coral"
                                />
                                <KpiCard
                                    label="Total Unpaid Orders"
                                    value={formatMoney(metrics.unpaid_orders)}
                                    tone="teal"
                                />
                                <KpiCard
                                    label="No. of Online Orders"
                                    value={metrics.online_orders.toLocaleString()}
                                    tone="green"
                                />
                            </div>

                            {/* Greeting */}
                            <p className="text-base font-medium text-foreground sm:text-lg">
                                {greetingForHour()},{' '}
                                <span className="font-semibold uppercase">
                                    {storeName}
                                </span>
                                !
                            </p>

                            {/* Sales chart + Payment types */}
                            <div className="grid gap-4 lg:grid-cols-[1fr_260px]">
                                <div className="rounded-2xl border border-border/60 bg-background p-4 sm:p-5">
                                    <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                                        <h2 className="text-base font-semibold text-foreground">
                                            Sales by Date
                                        </h2>
                                        <div className="flex rounded-lg border border-border bg-secondary/30 p-0.5">
                                            {GRANULARITY_TABS.map((tab) => {
                                                const disabled =
                                                    tab.key === 'hourly' &&
                                                    !isSingleDay;
                                                return (
                                                    <button
                                                        key={tab.key}
                                                        type="button"
                                                        disabled={disabled}
                                                        onClick={() =>
                                                            setGranularity(
                                                                tab.key,
                                                            )
                                                        }
                                                        className={cn(
                                                            'rounded-md px-3 py-1.5 text-xs font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-40 sm:text-sm',
                                                            granularity ===
                                                                tab.key
                                                                ? 'bg-background text-foreground shadow-sm'
                                                                : 'text-muted-foreground hover:text-foreground',
                                                        )}
                                                    >
                                                        {tab.label}
                                                    </button>
                                                );
                                            })}
                                        </div>
                                    </div>
                                    <SalesLineChart
                                        series={data?.sales_series ?? []}
                                        maxSales={maxSales}
                                    />
                                </div>

                                <div className="rounded-2xl border border-border/60 bg-background p-4 sm:p-5">
                                    <h2 className="mb-4 text-base font-semibold text-foreground">
                                        Payment Types
                                    </h2>
                                    {(data?.payment_types ?? []).length ===
                                    0 ? (
                                        <p className="text-sm text-muted-foreground">
                                            No payments recorded.
                                        </p>
                                    ) : (
                                        <ul className="space-y-4">
                                            {(data?.payment_types ?? []).map(
                                                (payment) => (
                                                    <li
                                                        key={payment.label}
                                                        className="flex items-center justify-between gap-2"
                                                    >
                                                        <div className="flex items-center gap-3">
                                                            <PaymentIcon
                                                                type={
                                                                    payment.type
                                                                }
                                                            />
                                                            <span className="text-sm font-medium text-foreground">
                                                                {payment.label}
                                                            </span>
                                                        </div>
                                                        <span className="text-sm font-bold tabular-nums text-foreground">
                                                            {formatMoney(
                                                                payment.amount,
                                                            )}
                                                        </span>
                                                    </li>
                                                ),
                                            )}
                                        </ul>
                                    )}
                                </div>
                            </div>

                            <div className="mt-4 rounded-2xl border border-border/60 bg-background p-4 sm:p-5">
                                <h2 className="mb-4 text-base font-semibold text-foreground">
                                    Attendance Today
                                </h2>
                                {(data?.attendance_today ?? []).length ===
                                0 ? (
                                    <p className="text-sm text-muted-foreground">
                                        No staff scheduled today.
                                    </p>
                                ) : (
                                    <ul className="divide-y divide-border/50">
                                        {(data?.attendance_today ?? []).map(
                                            (row) => (
                                                <li
                                                    key={row.user_id}
                                                    className="flex flex-wrap items-center justify-between gap-3 py-3 first:pt-0 last:pb-0"
                                                >
                                                    <div>
                                                        <p className="text-sm font-semibold text-foreground">
                                                            {row.full_name}
                                                        </p>
                                                        <p className="text-xs text-muted-foreground">
                                                            {row.role} ·{' '}
                                                            {row.branch_name}
                                                        </p>
                                                    </div>
                                                    <div className="flex items-center gap-5">
                                                        <AttendanceStatusPill
                                                            label="Sign In"
                                                            active={Boolean(
                                                                row.morning_in_at,
                                                            )}
                                                            time={
                                                                row.morning_in_display
                                                            }
                                                            tone="teal"
                                                        />
                                                        <AttendanceStatusPill
                                                            label="Sign Out"
                                                            active={Boolean(
                                                                row.day_out_at,
                                                            )}
                                                            time={
                                                                row.day_out_display
                                                            }
                                                            tone="orange"
                                                        />
                                                    </div>
                                                </li>
                                            ),
                                        )}
                                    </ul>
                                )}
                            </div>
                        </>
                    ) : null}
                    {showContent && metrics.order_count === 0 && !loading && (
                        <p className="text-center text-sm text-muted-foreground">
                            No sales in this date range. Try{' '}
                            <button
                                type="button"
                                className="font-medium text-primary underline"
                                onClick={() => {
                                    const r = rangeForKey('week');
                                    setStart(r.start);
                                    setEnd(r.end);
                                }}
                            >
                                This week
                            </button>{' '}
                            or run{' '}
                            <code className="rounded bg-secondary px-1.5 py-0.5 text-xs">
                                php artisan db:seed --class=ReportAccuracySeeder
                            </code>
                        </p>
                    )}
                </div>
            </div>
        </>
    );
}

Dashboard.layout = {
    breadcrumbs: [],
};
