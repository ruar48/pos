import { Head } from '@inertiajs/react';
import {
    AlertTriangle,
    BarChart3,
    CalendarRange,
    Clock,
    Coins,
    Download,
    FileText,
    Layers,
    Loader2,
    PieChart,
    RefreshCw,
    Search,
    ShoppingBag,
    TrendingUp,
    Users,
    type LucideIcon,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { toast } from 'sonner';
import { PageHeader } from '@/components/page-header';
import { ReportDonutChart } from '@/components/pos/report-donut-chart';
import { ReportHourlyHeatmap } from '@/components/pos/report-hourly-heatmap';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
    fetchAttendancePunctuality,
    fetchAuditTrail,
    fetchCustomerReport,
    fetchProductMix,
    fetchProfitCharts,
    fetchReportSummary,
    fetchSalesVisuals,
    type AttendancePunctualityRow,
    type AttendanceSchedule,
    type AuditRow,
    type CustomerRow,
    type ProductMixCategory,
    type ProfitItem,
    type ReportSummary,
    type SalesVisualsReport,
} from '@/lib/reports-api';
import { formatServerDateTime } from '@/lib/datetime';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';

type RangeKey = 'today' | 'yesterday' | 'week' | 'month' | 'custom';
type TabKey =
    | 'overview'
    | 'charts'
    | 'product-mix'
    | 'customers'
    | 'attendance'
    | 'audit';

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

function formatMoney(value: number): string {
    return value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
}

function formatInt(value: number): string {
    return value.toLocaleString();
}

function formatDateLabel(iso: string): string {
    const d = new Date(`${iso}T12:00:00`);
    return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
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
    const blob = new Blob([lines.join('\n')], {
        type: 'text/csv;charset=utf-8;',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
}

const RANGE_CHIPS: { key: Exclude<RangeKey, 'custom'>; label: string }[] = [
    { key: 'today', label: 'Today' },
    { key: 'yesterday', label: 'Yesterday' },
    { key: 'week', label: 'This Week' },
    { key: 'month', label: 'This Month' },
];

const TABS: { key: TabKey; label: string; icon: LucideIcon }[] = [
    { key: 'overview', label: 'Overview', icon: TrendingUp },
    { key: 'charts', label: 'Profit & COGS', icon: BarChart3 },
    { key: 'product-mix', label: 'Product Mix', icon: PieChart },
    { key: 'customers', label: 'Customers', icon: Users },
    { key: 'attendance', label: 'Attendance', icon: Clock },
    { key: 'audit', label: 'Audit Trail', icon: FileText },
];

type StatCardProps = {
    label: string;
    value: string;
    hint?: string;
    icon: LucideIcon;
    tone?: 'default' | 'positive' | 'warning' | 'danger';
};

function StatCard({ label, value, hint, icon: Icon, tone = 'default' }: StatCardProps) {
    const toneClass =
        tone === 'positive'
            ? 'bg-primary/10 text-primary'
            : tone === 'warning'
              ? 'bg-amber-500/10 text-amber-600'
              : tone === 'danger'
                ? 'bg-destructive/10 text-destructive'
                : 'bg-primary/10 text-primary';

    return (
        <div className="agri-stat-card">
            <div className="mb-3 flex items-center justify-between">
                <span className="agri-stat-label">{label}</span>
                <div
                    className={cn(
                        'flex size-8 shrink-0 items-center justify-center rounded-lg',
                        toneClass,
                    )}
                >
                    <Icon className="size-4" />
                </div>
            </div>
            <div className="mt-auto">
                <p className="agri-stat-value">{value}</p>
                {hint && (
                    <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
                )}
            </div>
        </div>
    );
}

function TuboCell({
    revenue,
    cost,
    align = 'right',
}: {
    revenue: number;
    cost: number;
    align?: 'left' | 'right';
}) {
    const tubo = revenue - cost;

    return (
        <div className={align === 'right' ? 'text-right' : 'text-left'}>
            <p className="font-semibold tabular-nums text-foreground">
                ₱{formatMoney(revenue)}
            </p>
            <p className="text-xs text-muted-foreground tabular-nums">
                cost ₱{formatMoney(cost)}
            </p>
            <p
                className={cn(
                    'text-xs font-medium tabular-nums',
                    tubo >= 0 ? 'text-primary' : 'text-destructive',
                )}
            >
                tubo ₱{formatMoney(tubo)}
            </p>
        </div>
    );
}

function SectionHeader({
    icon: Icon,
    title,
    description,
}: {
    icon: LucideIcon;
    title: string;
    description?: string;
}) {
    return (
        <div className="mb-4 flex items-start gap-3">
            <div className="agri-icon-box size-9 shrink-0">
                <Icon className="size-4" />
            </div>
            <div>
                <h3 className="agri-card-title">{title}</h3>
                {description && (
                    <p className="mt-1 text-sm text-muted-foreground">{description}</p>
                )}
            </div>
        </div>
    );
}

function ReportShell({
    loading,
    error,
    onRetry,
    emptyIcon: EmptyIcon,
    emptyTitle,
    emptyHint,
    isEmpty,
    children,
}: {
    loading: boolean;
    error: string | null;
    onRetry: () => void;
    emptyIcon: LucideIcon;
    emptyTitle: string;
    emptyHint?: string;
    isEmpty: boolean;
    children: ReactNode;
}) {
    if (loading) {
        return (
            <div className="agri-card overflow-hidden">
                <div className="flex items-center justify-center gap-2 py-20 text-muted-foreground">
                    <Loader2 className="size-5 animate-spin" />
                    Loading report...
                </div>
            </div>
        );
    }

    if (error) {
        return (
            <div className="agri-card overflow-hidden">
                <div className="flex flex-col items-center justify-center gap-3 py-20 text-center">
                    <AlertTriangle className="size-8 text-destructive" />
                    <p className="max-w-md text-sm font-medium text-destructive">{error}</p>
                    <Button variant="outline" size="sm" onClick={onRetry}>
                        Try again
                    </Button>
                </div>
            </div>
        );
    }

    if (isEmpty) {
        return (
            <div className="agri-card overflow-hidden">
                <div className="flex flex-col items-center justify-center gap-3 py-20 text-center">
                    <EmptyIcon className="size-8 text-muted-foreground" />
                    <p className="text-sm font-medium text-foreground">{emptyTitle}</p>
                    {emptyHint && (
                        <p className="max-w-sm text-xs text-muted-foreground">{emptyHint}</p>
                    )}
                </div>
            </div>
        );
    }

    return <>{children}</>;
}

function formatClockTime(value: string): string {
    const [hourRaw, minute] = value.split(':');
    const hour = Number(hourRaw);
    if (Number.isNaN(hour)) return value;
    const suffix = hour >= 12 ? 'PM' : 'AM';
    const display = hour % 12 === 0 ? 12 : hour % 12;
    return `${display}:${minute} ${suffix}`;
}

function PunctualityBar({
    row,
    maxAbs,
}: {
    row: AttendancePunctualityRow;
    maxAbs: number;
}) {
    const avg = row.avg_minutes_from_start ?? 0;
    const width =
        maxAbs > 0 ? Math.min(100, (Math.abs(avg) / maxAbs) * 100) : 0;
    const isLateSide = avg > 0;

    return (
        <div className="grid grid-cols-[minmax(0,1.2fr)_minmax(0,2fr)_auto] items-center gap-3 border-b border-border/50 px-1 py-3 last:border-0">
            <div className="min-w-0">
                <p className="truncate text-sm font-medium text-foreground">
                    #{row.rank} {row.full_name}
                </p>
                <p className="truncate text-xs capitalize text-muted-foreground">
                    {row.role.replace(/_/g, ' ')}
                </p>
            </div>
            <div className="relative h-8 overflow-hidden rounded-lg bg-secondary/60">
                <div
                    className={cn(
                        'absolute top-0 h-full w-px bg-border',
                        'left-1/2',
                    )}
                />
                <div
                    className={cn(
                        'absolute top-0 h-full rounded-lg transition-all',
                        isLateSide ? 'bg-destructive/80' : 'bg-primary/80',
                    )}
                    style={{
                        width: `${width / 2}%`,
                        left: isLateSide ? '50%' : `${50 - width / 2}%`,
                        minWidth: avg !== 0 ? '0.5rem' : 0,
                    }}
                />
            </div>
            <div className="text-right text-xs tabular-nums text-muted-foreground">
                <p>
                    {avg === 0
                        ? 'On start'
                        : avg < 0
                          ? `${Math.abs(avg)}m early`
                          : `${avg}m after start`}
                </p>
                <p className="font-medium text-foreground">
                    {row.days_present} day{row.days_present === 1 ? '' : 's'}{' '}
                    present
                </p>
            </div>
        </div>
    );
}

function ProfitBar({ item, max }: { item: ProfitItem; max: number }) {
    const width = max > 0 ? Math.max((item.profit / max) * 100, 2) : 0;

    return (
        <div className="grid grid-cols-[minmax(0,1.4fr)_minmax(0,2fr)_auto] items-center gap-3 border-b border-border/50 px-1 py-3 last:border-0">
            <div className="min-w-0">
                <p className="truncate text-sm font-medium text-foreground">{item.name}</p>
                <p className="truncate text-xs text-muted-foreground">{item.category}</p>
            </div>
            <div className="h-8 overflow-hidden rounded-lg bg-secondary/60">
                <div
                    className="flex h-full items-center rounded-lg bg-primary px-2 text-[10px] font-semibold text-primary-foreground transition-all"
                    style={{ width: `${width}%`, minWidth: item.profit > 0 ? '2.75rem' : 0 }}
                >
                    {item.profit > 0 && `₱${formatMoney(item.profit)}`}
                </div>
            </div>
            <div className="text-right text-xs tabular-nums text-muted-foreground">
                <p>qty {formatInt(item.quantity_sold)}</p>
                <p className="font-medium text-primary">tubo {item.margin_percent}%</p>
            </div>
        </div>
    );
}

export default function PosReports() {
    const [rangeKey, setRangeKey] = useState<RangeKey>('week');
    const initial = rangeForKey('week');
    const [start, setStart] = useState(initial.start);
    const [end, setEnd] = useState(initial.end);
    const [tab, setTab] = useState<TabKey>('overview');

    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    const [summary, setSummary] = useState<ReportSummary | null>(null);
    const [salesVisuals, setSalesVisuals] = useState<SalesVisualsReport | null>(
        null,
    );
    const [chartItems, setChartItems] = useState<ProfitItem[]>([]);
    const [topItem, setTopItem] = useState<ProfitItem | null>(null);
    const [mix, setMix] = useState<ProductMixCategory[]>([]);
    const [customers, setCustomers] = useState<CustomerRow[]>([]);
    const [audit, setAudit] = useState<AuditRow[]>([]);
    const [attendanceRows, setAttendanceRows] = useState<
        AttendancePunctualityRow[]
    >([]);
    const [attendanceSchedule, setAttendanceSchedule] =
        useState<AttendanceSchedule | null>(null);

    const [customerSearch, setCustomerSearch] = useState('');
    const [auditSearch, setAuditSearch] = useState('');

    const load = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            if (tab === 'overview') {
                const summaryRes = await fetchReportSummary(start, end);
                setSummary(summaryRes);

                try {
                    const visualsRes = await fetchSalesVisuals(start, end);
                    setSalesVisuals(visualsRes);
                } catch (visualErr) {
                    setSalesVisuals(null);
                    toast.error(
                        visualErr instanceof Error
                            ? visualErr.message
                            : 'Could not load sales charts',
                    );
                }
            } else if (tab === 'charts') {
                const res = await fetchProfitCharts(start, end);
                setChartItems(res.items ?? []);
                setTopItem(res.top_profit_item ?? null);
            } else if (tab === 'product-mix') {
                const res = await fetchProductMix(start, end);
                setMix(res.categories ?? []);
            } else if (tab === 'customers') {
                const res = await fetchCustomerReport(start, end, customerSearch);
                setCustomers(res.rows ?? []);
            } else if (tab === 'attendance') {
                const res = await fetchAttendancePunctuality(start, end);
                setAttendanceRows(res.rows ?? []);
                setAttendanceSchedule(res.schedule ?? null);
            } else {
                const res = await fetchAuditTrail(start, end, auditSearch);
                setAudit(res.rows ?? []);
            }
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Failed to load report');
        } finally {
            setLoading(false);
        }
    }, [start, end, tab, customerSearch, auditSearch]);

    useEffect(() => {
        load();
    }, [load]);

    const selectRange = (key: Exclude<RangeKey, 'custom'>) => {
        const r = rangeForKey(key);
        setRangeKey(key);
        setStart(r.start);
        setEnd(r.end);
    };

    const maxProfit = useMemo(
        () => Math.max(...chartItems.map((i) => i.profit), 1),
        [chartItems],
    );

    const maxTrend = useMemo(
        () => Math.max(...(summary?.daily_trend ?? []).map((d) => d.net_sales), 1),
        [summary],
    );

    const maxAttendanceOffset = useMemo(
        () =>
            Math.max(
                ...attendanceRows.map((r) =>
                    Math.abs(r.avg_minutes_from_start ?? 0),
                ),
                1,
            ),
        [attendanceRows],
    );

    const exportCurrentTab = () => {
        if (tab === 'overview' && summary) {
            downloadCsv(
                `sales_overview_${start}_to_${end}.csv`,
                ['Date', 'Net Sales', 'Orders'],
                summary.daily_trend.map((d) => [d.date, d.net_sales, d.order_count]),
            );
            toast.success('Overview exported');
            return;
        }
        if (tab === 'charts' && chartItems.length > 0) {
            downloadCsv(
                `profit_cogs_${start}_to_${end}.csv`,
                ['Item', 'Category', 'Qty', 'Revenue', 'COGS', 'Profit', 'Margin %'],
                chartItems.map((i) => [
                    i.name,
                    i.category,
                    i.quantity_sold,
                    i.revenue,
                    i.cogs,
                    i.profit,
                    i.margin_percent,
                ]),
            );
            toast.success('Profit report exported');
            return;
        }
        if (tab === 'product-mix' && mix.length > 0) {
            const rows: (string | number)[][] = [];
            mix.forEach((cat) => {
                cat.items.forEach((item) => {
                    rows.push([
                        cat.category,
                        item.name,
                        item.quantity_sold,
                        item.revenue,
                        item.cogs,
                        item.profit,
                    ]);
                });
            });
            downloadCsv(
                `product_mix_${start}_to_${end}.csv`,
                ['Category', 'Item', 'Qty', 'Revenue', 'COGS', 'Profit'],
                rows,
            );
            toast.success('Product mix exported');
            return;
        }
        if (tab === 'customers' && customers.length > 0) {
            downloadCsv(
                `customers_${start}_to_${end}.csv`,
                ['Customer', 'Note', 'Type', 'Orders', 'Total Spent', 'Avg Transaction'],
                customers.map((c) => [
                    c.customer_name,
                    c.note,
                    c.order_type,
                    c.order_count,
                    c.total_spent,
                    c.avg_transaction,
                ]),
            );
            toast.success('Customer report exported');
            return;
        }
        if (tab === 'attendance' && attendanceRows.length > 0) {
            downloadCsv(
                `attendance_punctuality_${start}_to_${end}.csv`,
                [
                    'Rank',
                    'Staff',
                    'Role',
                    'Days Present',
                    'Early',
                    'On Time',
                    'Almost Late',
                    'Late',
                    'Absent',
                    'Avg Minutes From Start',
                ],
                attendanceRows.map((r) => [
                    r.rank,
                    r.full_name,
                    r.role,
                    r.days_present,
                    r.days_early,
                    r.days_on_time,
                    r.days_almost_late,
                    r.days_late,
                    r.days_absent,
                    r.avg_minutes_from_start ?? '',
                ]),
            );
            toast.success('Attendance report exported');
            return;
        }
        if (tab === 'audit' && audit.length > 0) {
            downloadCsv(
                `audit_trail_${start}_to_${end}.csv`,
                ['Date', 'User', 'Title', 'Message'],
                audit.map((a) => [a.created_at, a.user_name, a.title, a.message]),
            );
            toast.success('Audit trail exported');
            return;
        }
        toast.error('Nothing to export for this tab');
    };

    const heatmapRangeLabel = useMemo(() => {
        const startLabel = formatDateLabel(start);
        const endLabel = formatDateLabel(end);
        return `${startLabel}, 12:00am – ${endLabel}, 11:59pm`;
    }, [start, end]);

    const rangeLabel =
        start === end
            ? formatDateLabel(start)
            : `${formatDateLabel(start)} – ${formatDateLabel(end)}`;

    const isSingleDay = start === end;

    return (
        <>
            <Head title="Reports" />
            <div className="agri-page-container">
                <PageHeader
                    badge="Reports"
                    title="Business Intelligence"
                    description="Sales, profit (tubo), product mix, loyal customers and audit trail — locked to prices at checkout so past days never change when you update items today."
                    actions={
                        <>
                            <Button variant="outline" size="sm" onClick={load} disabled={loading}>
                                {loading ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <RefreshCw className="size-4" />
                                )}
                                Refresh
                            </Button>
                            <Button size="sm" onClick={exportCurrentTab}>
                                <Download className="size-4" />
                                Export
                            </Button>
                        </>
                    }
                />

                <div className="agri-card flex flex-col gap-4 p-4 lg:flex-row lg:items-center lg:justify-between">
                    <div className="flex flex-wrap items-center gap-2">
                        {RANGE_CHIPS.map((chip) => (
                            <button
                                key={chip.key}
                                type="button"
                                onClick={() => selectRange(chip.key)}
                                className={cn(
                                    'rounded-full px-3.5 py-1.5 text-sm font-semibold transition-colors',
                                    rangeKey === chip.key
                                        ? 'bg-primary text-primary-foreground shadow-sm'
                                        : 'bg-secondary text-secondary-foreground hover:bg-secondary/70',
                                )}
                            >
                                {chip.label}
                            </button>
                        ))}
                    </div>
                    <div className="flex flex-wrap items-center gap-2">
                        <div className="flex items-center gap-2">
                            <Label htmlFor="rpt-start" className="text-xs text-muted-foreground">
                                From
                            </Label>
                            <Input
                                id="rpt-start"
                                type="date"
                                value={start}
                                max={end}
                                className="h-9 w-[9.5rem]"
                                onChange={(e) => {
                                    setStart(e.target.value);
                                    setRangeKey('custom');
                                }}
                            />
                        </div>
                        <div className="flex items-center gap-2">
                            <Label htmlFor="rpt-end" className="text-xs text-muted-foreground">
                                To
                            </Label>
                            <Input
                                id="rpt-end"
                                type="date"
                                value={end}
                                min={start}
                                max={toIsoDate(new Date())}
                                className="h-9 w-[9.5rem]"
                                onChange={(e) => {
                                    setEnd(e.target.value);
                                    setRangeKey('custom');
                                }}
                            />
                        </div>
                    </div>
                </div>

                <div className="agri-card flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
                    <div className="flex flex-wrap gap-2">
                        {TABS.map((t) => {
                            const Icon = t.icon;
                            return (
                                <button
                                    key={t.key}
                                    type="button"
                                    onClick={() => setTab(t.key)}
                                    className={cn(
                                        'inline-flex items-center gap-2 rounded-full px-3.5 py-1.5 text-sm font-semibold transition-colors',
                                        tab === t.key
                                            ? 'bg-primary text-primary-foreground shadow-sm'
                                            : 'bg-secondary text-secondary-foreground hover:bg-secondary/70',
                                    )}
                                >
                                    <Icon className="size-4" />
                                    {t.label}
                                </button>
                            );
                        })}
                    </div>
                    <p className="inline-flex items-center gap-2 text-xs text-muted-foreground">
                        <CalendarRange className="size-3.5 shrink-0" />
                        <span>
                            <span className="font-medium text-foreground">{rangeLabel}</span>
                            {isSingleDay ? ' · single day' : ' · date range'}
                        </span>
                    </p>
                </div>

                {tab === 'overview' && (
                    <ReportShell
                        loading={loading}
                        error={error}
                        onRetry={load}
                        emptyIcon={ShoppingBag}
                        emptyTitle="No sales in this period"
                        emptyHint="Complete orders on the POS tablet or run: php artisan db:seed --class=ReportAccuracySeeder"
                        isEmpty={!summary || summary.order_count === 0}
                    >
                        {summary && (
                            <div className="space-y-4">
                                <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
                                    <StatCard
                                        label="Net Sales"
                                        value={`₱${formatMoney(summary.net_sales)}`}
                                        hint={
                                            (summary.tax_rate ?? 0) > 0
                                                ? `${formatInt(summary.order_count)} orders · incl. VAT, after refunds`
                                                : `${formatInt(summary.order_count)} orders · VAT 0%, after refunds`
                                        }
                                        icon={ShoppingBag}
                                    />
                                    <StatCard
                                        label="Gross Profit (Tubo)"
                                        value={`₱${formatMoney(summary.gross_profit)}`}
                                        hint={`${summary.margin_percent}% on net merchandise (ex-VAT)`}
                                        icon={Coins}
                                        tone="positive"
                                    />
                                    <StatCard
                                        label="Avg. Ticket"
                                        value={`₱${formatMoney(summary.average_order_value)}`}
                                        hint={isSingleDay ? 'On selected day' : 'In selected range'}
                                        icon={TrendingUp}
                                        tone="positive"
                                    />
                                    <StatCard
                                        label="Refunds"
                                        value={`₱${formatMoney(summary.refunded_amount)}`}
                                        hint={
                                            summary.total_discounts > 0
                                                ? `₱${formatMoney(summary.total_discounts)} discounts`
                                                : 'After refunds'
                                        }
                                        icon={BarChart3}
                                        tone={summary.refunded_amount > 0 ? 'warning' : 'default'}
                                    />
                                </div>

                                {salesVisuals && (
                                    <>
                                        <div className="grid gap-4 xl:grid-cols-3">
                                            <ReportDonutChart
                                                title="Sales by Cashier"
                                                subtitle={rangeLabel}
                                                slices={salesVisuals.cashiers.map(
                                                    (row) => ({
                                                        label: row.label,
                                                        value: row.net_total,
                                                        hint: `${formatInt(row.order_count)} orders`,
                                                    }),
                                                )}
                                            />
                                            <ReportDonutChart
                                                title="Sales by Payment"
                                                subtitle={rangeLabel}
                                                slices={salesVisuals.payments.map(
                                                    (row) => ({
                                                        label: row.label,
                                                        value: row.net_total,
                                                        hint: `${formatInt(row.order_count)} payments`,
                                                    }),
                                                )}
                                            />
                                            <ReportDonutChart
                                                title="Sales by Customer Activity"
                                                subtitle={rangeLabel}
                                                slices={salesVisuals.customer_activity.map(
                                                    (row) => ({
                                                        label: row.label,
                                                        value: row.net_total,
                                                        hint: `${row.share_percent ?? 0}% of sales`,
                                                    }),
                                                )}
                                            />
                                        </div>

                                        <ReportHourlyHeatmap
                                            data={salesVisuals.hourly}
                                            rangeLabel={heatmapRangeLabel}
                                        />
                                    </>
                                )}

                                <div className="grid gap-4 lg:grid-cols-2">
                                    <div className="agri-card p-5">
                                        <SectionHeader
                                            icon={TrendingUp}
                                            title="Daily Sales Trend"
                                            description="Net sales per day in the selected range"
                                        />
                                        {summary.daily_trend.length === 0 ? (
                                            <p className="text-sm text-muted-foreground">
                                                No daily breakdown available.
                                            </p>
                                        ) : (
                                            <div className="flex h-44 items-end gap-2 pt-2">
                                                {summary.daily_trend.map((day) => {
                                                    const h =
                                                        maxTrend > 0
                                                            ? (day.net_sales / maxTrend) * 100
                                                            : 0;
                                                    return (
                                                        <div
                                                            key={day.date}
                                                            className="flex min-w-0 flex-1 flex-col items-center gap-2"
                                                            title={`₱${formatMoney(day.net_sales)} · ${day.order_count} orders`}
                                                        >
                                                            <div
                                                                className="w-full rounded-t-md bg-primary transition-all"
                                                                style={{
                                                                    height: `${Math.max(h, 6)}%`,
                                                                }}
                                                            />
                                                            <span className="truncate text-[10px] font-medium text-muted-foreground">
                                                                {formatDateLabel(day.date)}
                                                            </span>
                                                        </div>
                                                    );
                                                })}
                                            </div>
                                        )}
                                    </div>

                                    <div className="agri-card p-5">
                                        <SectionHeader
                                            icon={Coins}
                                            title="Payment Methods"
                                            description="Net totals after refunds"
                                        />
                                        {summary.payment_methods.length === 0 ? (
                                            <p className="text-sm text-muted-foreground">
                                                No payments recorded.
                                            </p>
                                        ) : (
                                            <ul className="divide-y divide-border/60">
                                                {summary.payment_methods.map((p) => (
                                                    <li
                                                        key={p.payment_method}
                                                        className="flex items-center justify-between py-3 text-sm"
                                                    >
                                                        <div>
                                                            <p className="font-semibold text-foreground">
                                                                {p.payment_method}
                                                            </p>
                                                            <p className="text-xs text-muted-foreground">
                                                                {formatInt(p.order_count)} orders
                                                            </p>
                                                        </div>
                                                        <p className="font-semibold tabular-nums text-foreground">
                                                            ₱{formatMoney(p.net_total)}
                                                        </p>
                                                    </li>
                                                ))}
                                            </ul>
                                        )}
                                    </div>
                                </div>

                                <div className="agri-card p-5">
                                    <SectionHeader
                                        icon={Layers}
                                        title="Merchandise vs COGS"
                                        description={
                                            (summary.tax_rate ?? 0) > 0
                                                ? 'Tubo uses net merchandise after refunds (ex-VAT). Net Sales = merchandise + VAT still kept after refunds.'
                                                : 'VAT is 0% in settings. Net Sales equals net merchandise kept after refunds.'
                                        }
                                    />
                                    <div className="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
                                        <div className="rounded-xl border border-border/60 bg-secondary/20 p-3">
                                            <p className="text-xs text-muted-foreground">Line items (net qty)</p>
                                            <p className="mt-1 font-semibold tabular-nums">
                                                ₱{formatMoney(summary.item_subtotal ?? summary.revenue)}
                                            </p>
                                        </div>
                                        <div className="rounded-xl border border-border/60 bg-secondary/20 p-3">
                                            <p className="text-xs text-muted-foreground">Discounts (at sale)</p>
                                            <p className="mt-1 font-semibold tabular-nums text-amber-600">
                                                −₱{formatMoney(summary.total_discounts)}
                                            </p>
                                        </div>
                                        <div className="rounded-xl border border-border/60 bg-secondary/20 p-3">
                                            <p className="text-xs text-muted-foreground">
                                                VAT kept
                                                {(summary.tax_rate ?? 0) <= 0 ? ' (0%)' : ''}
                                            </p>
                                            <p className="mt-1 font-semibold tabular-nums">
                                                +₱{formatMoney(summary.vat_collected)}
                                            </p>
                                        </div>
                                        <div className="rounded-xl border border-border/60 bg-secondary/20 p-3">
                                            <p className="text-xs text-muted-foreground">Refunds</p>
                                            <p className="mt-1 font-semibold tabular-nums text-rose-600">
                                                −₱{formatMoney(summary.refunded_amount)}
                                            </p>
                                        </div>
                                        <div className="rounded-xl border border-border/60 bg-secondary/20 p-3">
                                            <p className="text-xs text-muted-foreground">Net sales check</p>
                                            <p className="mt-1 text-xs tabular-nums text-muted-foreground">
                                                {formatMoney(summary.net_merchandise ?? summary.revenue)} +{' '}
                                                {formatMoney(summary.vat_collected)} ={' '}
                                                <span className="font-semibold text-foreground">
                                                    ₱{formatMoney(summary.sales_reconcile ?? summary.net_sales)}
                                                </span>
                                            </p>
                                            <p className="mt-1 text-[10px] text-muted-foreground">
                                                Should match Net Sales ₱{formatMoney(summary.net_sales)}
                                            </p>
                                        </div>
                                    </div>
                                    <div className="grid gap-4 sm:grid-cols-3">
                                        <div className="rounded-xl border border-border/60 bg-secondary/20 p-4">
                                            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                                                Net merchandise
                                            </p>
                                            <p className="mt-2 text-2xl font-semibold tabular-nums">
                                                ₱{formatMoney(summary.net_merchandise ?? summary.revenue)}
                                            </p>
                                        </div>
                                        <div className="rounded-xl border border-border/60 bg-secondary/20 p-4">
                                            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                                                COGS
                                            </p>
                                            <p className="mt-2 text-2xl font-semibold tabular-nums">
                                                ₱{formatMoney(summary.cogs)}
                                            </p>
                                        </div>
                                        <div className="rounded-xl border border-primary/20 bg-primary/5 p-4">
                                            <p className="text-xs font-semibold uppercase tracking-wide text-primary">
                                                Tubo
                                            </p>
                                            <p className="mt-2 text-2xl font-semibold tabular-nums text-primary">
                                                ₱{formatMoney(summary.gross_profit)}
                                            </p>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        )}
                    </ReportShell>
                )}

                {tab === 'charts' && (
                    <ReportShell
                        loading={loading}
                        error={error}
                        onRetry={load}
                        emptyIcon={BarChart3}
                        emptyTitle="No item sales in this period"
                        emptyHint="Sell items from the POS tablet to populate profit rankings."
                        isEmpty={chartItems.length === 0}
                    >
                        <div className="agri-card p-5">
                            <SectionHeader
                                icon={BarChart3}
                                title="Profit & COGS by Item"
                                description={
                                    topItem
                                        ? `Top earner: ${topItem.name} with ₱${formatMoney(topItem.profit)} tubo`
                                        : undefined
                                }
                            />
                            <div className="rounded-xl border border-border/60 bg-secondary/10 px-3">
                                {chartItems.map((item) => (
                                    <ProfitBar
                                        key={`${item.product_id}-${item.name}`}
                                        item={item}
                                        max={maxProfit}
                                    />
                                ))}
                            </div>
                        </div>
                    </ReportShell>
                )}

                {tab === 'product-mix' && (
                    <ReportShell
                        loading={loading}
                        error={error}
                        onRetry={load}
                        emptyIcon={PieChart}
                        emptyTitle="No product mix data"
                        emptyHint="Sales by category will appear once orders exist in this range."
                        isEmpty={mix.length === 0}
                    >
                        <div className="agri-card p-5">
                            <SectionHeader
                                icon={PieChart}
                                title="Product Mix by Category"
                                description="Quantity and revenue grouped by item category"
                            />
                            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                                {mix.map((cat) => (
                                    <div
                                        key={cat.category}
                                        className="rounded-xl border border-border/60 bg-secondary/20 p-4"
                                    >
                                        <div className="flex items-center justify-between gap-2">
                                            <p className="font-semibold text-foreground">
                                                {cat.category}
                                            </p>
                                            <span className="rounded-full bg-secondary px-2 py-0.5 text-[11px] font-semibold text-muted-foreground">
                                                {formatInt(cat.quantity_sold)} sold
                                            </span>
                                        </div>
                                        <div className="mt-2">
                                            <TuboCell
                                                revenue={cat.revenue}
                                                cost={cat.cogs}
                                                align="left"
                                            />
                                        </div>
                                        <p className="mt-2 text-xs text-muted-foreground">
                                            {cat.margin_percent}% margin
                                        </p>
                                        <ul className="mt-3 max-h-52 space-y-2 overflow-y-auto border-t border-border/50 pt-3 text-sm">
                                            {cat.items.map((item) => (
                                                <li
                                                    key={item.name}
                                                    className="flex items-start justify-between gap-2"
                                                >
                                                    <div className="min-w-0">
                                                        <p className="truncate font-medium">
                                                            {item.name}
                                                        </p>
                                                        <p className="text-xs text-muted-foreground">
                                                            qty {formatInt(item.quantity_sold)}
                                                        </p>
                                                    </div>
                                                    <div className="shrink-0 text-right tabular-nums">
                                                        <p className="font-medium">
                                                            ₱{formatMoney(item.revenue)}
                                                        </p>
                                                        <p className="text-xs text-primary">
                                                            +₱{formatMoney(item.profit)}
                                                        </p>
                                                    </div>
                                                </li>
                                            ))}
                                        </ul>
                                    </div>
                                ))}
                            </div>
                        </div>
                    </ReportShell>
                )}

                {tab === 'customers' && (
                    <div className="space-y-4">
                        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                            <div className="relative flex-1">
                                <Search className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                <Input
                                    placeholder="Search customer or note..."
                                    value={customerSearch}
                                    onChange={(e) => setCustomerSearch(e.target.value)}
                                    onKeyDown={(e) => {
                                        if (e.key === 'Enter') load();
                                    }}
                                    className="pl-9"
                                />
                            </div>
                            <Button variant="outline" size="sm" onClick={load} disabled={loading}>
                                <Search className="size-4" />
                                Search
                            </Button>
                        </div>

                        <ReportShell
                            loading={loading}
                            error={error}
                            onRetry={load}
                            emptyIcon={Users}
                            emptyTitle="No customer activity"
                            emptyHint="Named customers and walk-ins appear here once orders are recorded."
                            isEmpty={customers.length === 0}
                        >
                            <div className="agri-card overflow-hidden">
                                <div className="overflow-x-auto">
                                    <table className="w-full min-w-[52rem] text-sm">
                                        <thead>
                                            <tr className="border-b border-border/60 bg-secondary/40 text-left">
                                                <th className="px-4 py-3 font-semibold text-muted-foreground">
                                                    Customer
                                                </th>
                                                <th className="px-3 py-3 font-semibold text-muted-foreground">
                                                    Note
                                                </th>
                                                <th className="px-3 py-3 font-semibold text-muted-foreground">
                                                    Type
                                                </th>
                                                <th className="px-3 py-3 text-right font-semibold text-muted-foreground">
                                                    Orders
                                                </th>
                                                <th className="px-4 py-3 text-right font-semibold text-muted-foreground">
                                                    Total Spent
                                                </th>
                                                <th className="px-4 py-3 text-right font-semibold text-muted-foreground">
                                                    Avg. Ticket
                                                </th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {customers.map((c) => (
                                                <tr
                                                    key={`${c.customer_id}-${c.customer_name}`}
                                                    className="border-b border-border/40 last:border-0"
                                                >
                                                    <td className="px-4 py-3 font-medium text-foreground">
                                                        {c.customer_name}
                                                    </td>
                                                    <td className="px-3 py-3 text-muted-foreground">
                                                        {c.note || '—'}
                                                    </td>
                                                    <td className="px-3 py-3">{c.order_type}</td>
                                                    <td className="px-3 py-3 text-right tabular-nums">
                                                        {formatInt(c.order_count)}
                                                    </td>
                                                    <td className="px-4 py-3 text-right font-semibold tabular-nums">
                                                        ₱{formatMoney(c.total_spent)}
                                                    </td>
                                                    <td className="px-4 py-3 text-right tabular-nums text-muted-foreground">
                                                        ₱{formatMoney(c.avg_transaction)}
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            </div>
                        </ReportShell>
                    </div>
                )}

                {tab === 'attendance' && (
                    <div className="space-y-4">
                        {attendanceSchedule && (
                            <div className="grid gap-4 sm:grid-cols-3">
                                <StatCard
                                    label="Expected start"
                                    value={formatClockTime(
                                        attendanceSchedule.start_time,
                                    )}
                                    icon={Clock}
                                />
                                <StatCard
                                    label="Grace period"
                                    value={`${attendanceSchedule.grace_minutes} min`}
                                    hint="Still on time inside this window"
                                    icon={CalendarRange}
                                />
                                <StatCard
                                    label="Marked late after"
                                    value={formatClockTime(
                                        attendanceSchedule.late_after_time,
                                    )}
                                    tone="warning"
                                    icon={AlertTriangle}
                                />
                            </div>
                        )}

                        <ReportShell
                            loading={loading}
                            error={error}
                            onRetry={load}
                            emptyIcon={Clock}
                            emptyTitle="No attendance data"
                            emptyHint="Staff clock-ins from the tablet will appear here."
                            isEmpty={attendanceRows.length === 0}
                        >
                            <div className="agri-card overflow-hidden p-4">
                                <SectionHeader
                                    icon={Clock}
                                    title="Punctuality ranking"
                                    description="Ranked by score (early/on-time best). Bars show average minutes before (−) or after (+) expected start."
                                />
                                {attendanceRows.map((row) => (
                                    <PunctualityBar
                                        key={row.user_id}
                                        row={row}
                                        maxAbs={maxAttendanceOffset}
                                    />
                                ))}
                            </div>

                            <div className="agri-card mt-4 overflow-hidden">
                                <div className="overflow-x-auto">
                                    <table className="w-full min-w-[52rem] text-sm">
                                        <thead>
                                            <tr className="border-b border-border/60 bg-secondary/40 text-left">
                                                <th className="px-4 py-3 font-semibold text-muted-foreground">
                                                    Rank
                                                </th>
                                                <th className="px-3 py-3 font-semibold text-muted-foreground">
                                                    Staff
                                                </th>
                                                <th className="px-3 py-3 text-center font-semibold text-muted-foreground">
                                                    Early
                                                </th>
                                                <th className="px-3 py-3 text-center font-semibold text-muted-foreground">
                                                    On time
                                                </th>
                                                <th className="px-3 py-3 text-center font-semibold text-muted-foreground">
                                                    Almost late
                                                </th>
                                                <th className="px-3 py-3 text-center font-semibold text-muted-foreground">
                                                    Late
                                                </th>
                                                <th className="px-3 py-3 text-center font-semibold text-muted-foreground">
                                                    Absent
                                                </th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {attendanceRows.map((row) => (
                                                <tr
                                                    key={row.user_id}
                                                    className="border-b border-border/40 last:border-0"
                                                >
                                                    <td className="px-4 py-3 font-semibold tabular-nums">
                                                        #{row.rank}
                                                    </td>
                                                    <td className="px-3 py-3">
                                                        <p className="font-medium">
                                                            {row.full_name}
                                                        </p>
                                                        <p className="text-xs capitalize text-muted-foreground">
                                                            {row.role.replace(
                                                                /_/g,
                                                                ' ',
                                                            )}
                                                        </p>
                                                    </td>
                                                    <td className="px-3 py-3 text-center tabular-nums">
                                                        {row.days_early}
                                                    </td>
                                                    <td className="px-3 py-3 text-center tabular-nums text-emerald-700">
                                                        {row.days_on_time}
                                                    </td>
                                                    <td className="px-3 py-3 text-center tabular-nums text-amber-700">
                                                        {row.days_almost_late}
                                                    </td>
                                                    <td className="px-3 py-3 text-center tabular-nums text-destructive">
                                                        {row.days_late}
                                                    </td>
                                                    <td className="px-3 py-3 text-center tabular-nums text-muted-foreground">
                                                        {row.days_absent}
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            </div>
                        </ReportShell>
                    </div>
                )}

                {tab === 'audit' && (
                    <div className="space-y-4">
                        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                            <div className="relative flex-1">
                                <Search className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                <Input
                                    placeholder="Search audit logs..."
                                    value={auditSearch}
                                    onChange={(e) => setAuditSearch(e.target.value)}
                                    onKeyDown={(e) => {
                                        if (e.key === 'Enter') load();
                                    }}
                                    className="pl-9"
                                />
                            </div>
                            <Button variant="outline" size="sm" onClick={load} disabled={loading}>
                                <Search className="size-4" />
                                Search
                            </Button>
                        </div>

                        <ReportShell
                            loading={loading}
                            error={error}
                            onRetry={load}
                            emptyIcon={FileText}
                            emptyTitle="No audit entries"
                            emptyHint="Stock adjustments and admin actions will appear here."
                            isEmpty={audit.length === 0}
                        >
                            <div className="agri-card overflow-hidden">
                                <div className="overflow-x-auto">
                                    <table className="w-full min-w-[56rem] text-sm">
                                        <thead>
                                            <tr className="border-b border-border/60 bg-secondary/40 text-left">
                                                <th className="px-4 py-3 font-semibold text-muted-foreground">
                                                    Date & time
                                                </th>
                                                <th className="px-3 py-3 font-semibold text-muted-foreground">
                                                    User
                                                </th>
                                                <th className="px-3 py-3 font-semibold text-muted-foreground">
                                                    Title
                                                </th>
                                                <th className="px-4 py-3 font-semibold text-muted-foreground">
                                                    Message
                                                </th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {audit.map((row) => (
                                                <tr
                                                    key={row.id}
                                                    className="border-b border-border/40 last:border-0"
                                                >
                                                    <td className="px-4 py-3 whitespace-nowrap text-muted-foreground">
                                                        {formatServerDateTime(row.created_at)}
                                                    </td>
                                                    <td className="px-3 py-3 font-medium">
                                                        {row.user_name}
                                                    </td>
                                                    <td className="px-3 py-3 font-medium text-foreground">
                                                        {row.title}
                                                    </td>
                                                    <td className="max-w-md px-4 py-3 text-muted-foreground">
                                                        {row.message}
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            </div>
                        </ReportShell>
                    </div>
                )}
            </div>
        </>
    );
}

PosReports.layout = {
    breadcrumbs: [
        { title: 'Dashboard', href: dashboard() },
        { title: 'Reports', href: '/pos/reports' },
    ],
};
