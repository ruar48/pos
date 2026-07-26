import { Head } from '@inertiajs/react';
import {
    AlertTriangle,
    ArrowDownRight,
    ArrowUpRight,
    Boxes,
    ChevronDown,
    ChevronRight,
    Coins,
    Download,
    Layers,
    Loader2,
    Package,
    PackageX,
    RefreshCw,
    Search,
    SlidersHorizontal,
    TrendingUp,
    Warehouse,
    type LucideIcon,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { PageHeader } from '@/components/page-header';
import { Button } from '@/components/ui/button';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from '@/components/ui/select';
import {
    adjustInventoryStock,
    getInventoryReportCache,
    loadInventoryReport,
    type InventoryReport,
    type InventoryRow,
    type InventoryVarietyRow,
} from '@/lib/inventory-api';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';

const ALL = '__all__';

type RangeKey = 'today' | 'yesterday' | 'week' | 'month' | 'custom';
type StatusFilter = 'all' | 'low' | 'out';

type StockAdjustTarget = {
    product_id: number;
    product_name: string;
    unit?: string | null;
    live_stock: number;
    variety_id?: number;
    variety_name?: string;
};

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
        const diff = (day + 6) % 7; // days since Monday
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

function StockValueCell({
    valueRetail,
    valueCost,
    align = 'right',
}: {
    valueRetail: number;
    valueCost: number;
    align?: 'left' | 'right';
}) {
    const tubo = valueRetail - valueCost;

    return (
        <div className={align === 'right' ? 'text-right' : 'text-left'}>
            <p className="font-semibold tabular-nums text-foreground">
                ₱{formatMoney(valueRetail)}
            </p>
            <p className="text-xs text-muted-foreground tabular-nums">
                cost ₱{formatMoney(valueCost)}
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

function resolveImageSrc(imageUrl: string | null | undefined): string | null {
    const url = (imageUrl ?? '').trim();
    if (url === '') return null;
    if (/^https?:\/\//i.test(url) || url.startsWith('data:')) return url;
    const origin = window.location.origin.replace(/\/$/, '');
    return `${origin}/${url.replace(/^\//, '')}`;
}

function ItemThumbnail({
    imageUrl,
    alt,
    size = 'md',
}: {
    imageUrl?: string | null;
    alt: string;
    size?: 'sm' | 'md';
}) {
    const src = resolveImageSrc(imageUrl);
    const sizeClass = size === 'sm' ? 'size-8' : 'size-10';

    return (
        <div
            className={cn(
                'flex shrink-0 items-center justify-center overflow-hidden rounded-lg border border-border/60 bg-secondary/40',
                sizeClass,
            )}
        >
            {src ? (
                <img src={src} alt={alt} className="size-full object-cover" />
            ) : (
                <Package
                    className={cn(
                        'text-muted-foreground',
                        size === 'sm' ? 'size-3.5' : 'size-4',
                    )}
                />
            )}
        </div>
    );
}

const RANGE_CHIPS: { key: Exclude<RangeKey, 'custom'>; label: string }[] = [
    { key: 'today', label: 'Today' },
    { key: 'yesterday', label: 'Yesterday' },
    { key: 'week', label: 'This Week' },
    { key: 'month', label: 'This Month' },
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

export default function PosInventory() {

    const [rangeKey, setRangeKey] = useState<RangeKey>('today');
    const initial = rangeForKey('today');
    const [start, setStart] = useState(initial.start);
    const [end, setEnd] = useState(initial.end);

    const cachedReport = getInventoryReportCache(initial.start, initial.end);
    const [report, setReport] = useState<InventoryReport | null>(
        () => cachedReport,
    );
    const [loading, setLoading] = useState(() => cachedReport == null);
    const [refreshing, setRefreshing] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const [query, setQuery] = useState('');
    const [category, setCategory] = useState<string>(ALL);
    const [status, setStatus] = useState<StatusFilter>('all');

    const [adjustTarget, setAdjustTarget] = useState<StockAdjustTarget | null>(
        null,
    );

    const load = useCallback(() => {
        const hasLocalData = getInventoryReportCache(start, end) != null;
        if (!hasLocalData) {
            setLoading(true);
        } else {
            setRefreshing(true);
        }
        setError(null);

        loadInventoryReport(start, end, { force: true })
            .then((res) => {
                setReport(res);
                setError(null);
            })
            .catch((err: Error) => {
                if (!getInventoryReportCache(start, end)) {
                    setError(err.message);
                    setReport(null);
                }
            })
            .finally(() => {
                setLoading(false);
                setRefreshing(false);
            });
    }, [start, end]);

    useEffect(() => {
        const cached = getInventoryReportCache(start, end);
        if (cached) {
            setReport(cached);
            setLoading(false);
            setRefreshing(true);
        } else {
            setLoading(true);
            setRefreshing(false);
        }
        setError(null);

        let cancelled = false;
        loadInventoryReport(start, end, { force: true })
            .then((res) => {
                if (cancelled) return;
                setReport(res);
                setError(null);
            })
            .catch((err: Error) => {
                if (cancelled) return;
                if (!getInventoryReportCache(start, end)) {
                    setError(err.message);
                    setReport(null);
                }
            })
            .finally(() => {
                if (cancelled) return;
                setLoading(false);
                setRefreshing(false);
            });

        return () => {
            cancelled = true;
        };
    }, [start, end]);

    const selectRange = (key: Exclude<RangeKey, 'custom'>) => {
        const r = rangeForKey(key);
        setRangeKey(key);
        setStart(r.start);
        setEnd(r.end);
    };

    const rows = report?.rows ?? [];

    const categories = useMemo(() => {
        const set = new Set<string>();
        rows.forEach((r) => set.add(r.category));
        return Array.from(set).sort((a, b) => a.localeCompare(b));
    }, [rows]);

    const filteredRows = useMemo(() => {
        const q = query.trim().toLowerCase();
        return rows.filter((r) => {
            if (category !== ALL && r.category !== category) return false;
            const varietyLow =
                (r.low_varieties_count ?? 0) > 0 ||
                (r.varieties?.some((v) => v.is_low_stock) ?? false);
            const varietyOut =
                (r.out_varieties_count ?? 0) > 0 ||
                (r.varieties?.some((v) => v.is_out_of_stock) ?? false);
            if (status === 'low' && !r.is_low_stock && !varietyLow) return false;
            if (
                status === 'out' &&
                !r.is_out_of_stock &&
                !varietyOut
            ) {
                return false;
            }
            if (q === '') return true;
            const varietyMatch =
                r.varieties?.some(
                    (v) => v.name.toLowerCase().includes(q),
                ) ?? false;
            return (
                r.name.toLowerCase().includes(q) ||
                r.category.toLowerCase().includes(q) ||
                varietyMatch
            );
        });
    }, [rows, query, category, status]);

    const filteredTotals = useMemo(() => {
        return filteredRows.reduce(
            (acc, r) => {
                acc.beginning += r.beginning;
                acc.added += r.added;
                acc.deducted += r.deducted;
                acc.sold += r.sold;
                acc.ending += r.ending;
                acc.value_cost += r.value_cost;
                acc.value_retail += r.value_retail;
                return acc;
            },
            {
                beginning: 0,
                added: 0,
                deducted: 0,
                sold: 0,
                ending: 0,
                value_cost: 0,
                value_retail: 0,
            },
        );
    }, [filteredRows]);

    const totals = report?.totals;
    const potentialMargin =
        totals?.value_margin ??
        (totals ? totals.value_retail - totals.value_cost : 0);

    const exportCsv = () => {
        if (filteredRows.length === 0) {
            toast.error('Nothing to export');
            return;
        }
        const header = [
            'Item',
            'Category',
            'Unit',
            'Beginning',
            'Added',
            'Deducted',
            'Sold',
            'Current',
            'Reorder Level',
            'Cost Price',
            'Retail Price',
            'Stock Value (Cost)',
            'Stock Value (Retail)',
        ];
        const escape = (v: string | number) => {
            const s = String(v);
            return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
        };
        const lines = [header.join(',')];
        filteredRows.forEach((r) => {
            lines.push(
                [
                    escape(r.name),
                    escape(r.category),
                    escape(r.unit ?? ''),
                    r.beginning,
                    r.added,
                    r.deducted,
                    r.sold,
                    r.ending,
                    r.reorder_level,
                    r.cost_price,
                    r.price,
                    r.value_cost,
                    r.value_retail,
                ].join(','),
            );
        });
        const blob = new Blob([lines.join('\n')], {
            type: 'text/csv;charset=utf-8;',
        });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `inventory_${start}_to_${end}.csv`;
        a.click();
        URL.revokeObjectURL(url);
        toast.success('Inventory exported');
    };

    const isSingleDay = start === end;

    return (
        <>
            <Head title="Inventory" />
            <div className="agri-page-container">
                <PageHeader
                    badge="Inventory"
                    title="Inventory Control"
                    description="Track beginning, added, deducted and current stock for any day — with live valuation, low-stock alerts and category roll-ups. One ledger across tablet and web."
                    actions={
                        <>
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={load}
                                disabled={loading}
                            >
                                {loading ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <RefreshCw className="size-4" />
                                )}
                                Refresh
                            </Button>
                            <Button size="sm" onClick={exportCsv}>
                                <Download className="size-4" />
                                Export
                            </Button>
                        </>
                    }
                />

                {/* Range selector */}
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
                            <Label
                                htmlFor="inv-start"
                                className="text-xs text-muted-foreground"
                            >
                                From
                            </Label>
                            <Input
                                id="inv-start"
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
                            <Label
                                htmlFor="inv-end"
                                className="text-xs text-muted-foreground"
                            >
                                To
                            </Label>
                            <Input
                                id="inv-end"
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

                {/* KPI cards */}
                <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
                    <StatCard
                        label="Inventory Value"
                        value={`₱${formatMoney(totals?.value_retail ?? 0)}`}
                        hint={
                            report?.valuation_as_of
                                ? `Prices as of ${report.valuation_as_of} · cost ₱${formatMoney(totals?.value_cost ?? 0)}`
                                : `At cost: ₱${formatMoney(totals?.value_cost ?? 0)}`
                        }
                        icon={Warehouse}
                        tone="positive"
                    />
                    <StatCard
                        label="Potential Margin"
                        value={`₱${formatMoney(potentialMargin)}`}
                        hint="Retail value minus cost"
                        icon={TrendingUp}
                        tone="positive"
                    />
                    <StatCard
                        label="Units Sold"
                        value={formatInt(totals?.sold ?? 0)}
                        hint={
                            isSingleDay
                                ? 'On selected day'
                                : 'In selected range'
                        }
                        icon={Coins}
                    />
                    <StatCard
                        label="Stock Alerts"
                        value={formatInt(
                            (totals?.low_stock ?? 0) +
                                (totals?.out_of_stock ?? 0),
                        )}
                        hint={`${formatInt(totals?.low_stock ?? 0)} low varieties/items · ${formatInt(
                            totals?.out_of_stock ?? 0,
                        )} out`}
                        icon={AlertTriangle}
                        tone={
                            (totals?.out_of_stock ?? 0) > 0
                                ? 'danger'
                                : (totals?.low_stock ?? 0) > 0
                                  ? 'warning'
                                  : 'default'
                        }
                    />
                </div>

                {/* Filters */}
                <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                    <div className="relative flex-1">
                        <Search className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                        <Input
                            placeholder="Search items or category..."
                            value={query}
                            onChange={(e) => setQuery(e.target.value)}
                            className="pl-9"
                        />
                    </div>
                    <Select value={category} onValueChange={setCategory}>
                        <SelectTrigger className="w-full sm:w-52">
                            <SelectValue placeholder="Category" />
                        </SelectTrigger>
                        <SelectContent>
                            <SelectItem value={ALL}>All categories</SelectItem>
                            {categories.map((c) => (
                                <SelectItem key={c} value={c}>
                                    {c}
                                </SelectItem>
                            ))}
                        </SelectContent>
                    </Select>
                    <Select
                        value={status}
                        onValueChange={(v) => setStatus(v as StatusFilter)}
                    >
                        <SelectTrigger className="w-full sm:w-44">
                            <SlidersHorizontal className="size-4" />
                            <SelectValue placeholder="Status" />
                        </SelectTrigger>
                        <SelectContent>
                            <SelectItem value="all">All stock</SelectItem>
                            <SelectItem value="low">Low stock</SelectItem>
                            <SelectItem value="out">Out of stock</SelectItem>
                        </SelectContent>
                    </Select>
                </div>

                {/* Table */}
                <div className="agri-card overflow-hidden">
                    {loading ? (
                        <div className="flex items-center justify-center gap-2 py-20 text-muted-foreground">
                            <Loader2 className="size-5 animate-spin" />
                            Loading inventory...
                        </div>
                    ) : error ? (
                        <div className="flex flex-col items-center justify-center gap-3 py-20 text-center">
                            <PackageX className="size-8 text-destructive" />
                            <p className="text-sm font-medium text-destructive">
                                {error}
                            </p>
                            <Button variant="outline" size="sm" onClick={load}>
                                Try again
                            </Button>
                        </div>
                    ) : (
                        <>
                            {refreshing && (
                                <div className="flex items-center gap-2 border-b border-border/60 px-4 py-2 text-xs text-muted-foreground">
                                    <Loader2 className="size-3.5 animate-spin" />
                                    Updating inventory…
                                </div>
                            )}
                            {filteredRows.length === 0 ? (
                        <div className="flex flex-col items-center justify-center gap-3 py-20 text-center">
                            <Package className="size-8 text-muted-foreground" />
                            <p className="text-sm font-medium text-foreground">
                                No items match your filters
                            </p>
                            <p className="text-xs text-muted-foreground">
                                Try a different date range, category or search.
                            </p>
                        </div>
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full min-w-[60rem] text-sm">
                                <thead>
                                    <tr className="border-b border-border/60 bg-secondary/40 text-left">
                                        <th className="px-4 py-3 font-semibold text-muted-foreground">
                                            Item
                                        </th>
                                        <th className="px-3 py-3 text-right font-semibold text-muted-foreground">
                                            Beginning
                                        </th>
                                        <th className="px-3 py-3 text-right font-semibold text-muted-foreground">
                                            Added
                                        </th>
                                        <th className="px-3 py-3 text-right font-semibold text-muted-foreground">
                                            Deducted
                                        </th>
                                        <th className="px-3 py-3 text-right font-semibold text-muted-foreground">
                                            Current
                                        </th>
                                        <th className="px-4 py-3 text-right font-semibold text-muted-foreground">
                                            Stock Value
                                        </th>
                                        <th className="px-3 py-3 text-right font-semibold text-muted-foreground">
                                            <span className="sr-only">
                                                Actions
                                            </span>
                                        </th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {filteredRows.map((r) => (
                                        <InventoryTableRowGroup
                                            key={r.product_id}
                                            row={r}
                                            onAdjust={() =>
                                                setAdjustTarget({
                                                    product_id: r.product_id,
                                                    product_name: r.name,
                                                    unit: r.unit,
                                                    live_stock: r.live_stock,
                                                })
                                            }
                                            onAdjustVariety={(variety) =>
                                                setAdjustTarget({
                                                    product_id: r.product_id,
                                                    product_name: r.name,
                                                    unit: variety.unit ?? r.unit,
                                                    live_stock: variety.live_stock,
                                                    variety_id: variety.variety_id,
                                                    variety_name: variety.name,
                                                })
                                            }
                                        />
                                    ))}
                                </tbody>
                                <tfoot>
                                    <tr className="border-t-2 border-border bg-secondary/30 font-semibold">
                                        <td className="px-4 py-3 text-foreground">
                                            {filteredRows.length} item
                                            {filteredRows.length === 1
                                                ? ''
                                                : 's'}
                                        </td>
                                        <td className="px-3 py-3 text-right tabular-nums">
                                            {formatInt(
                                                filteredTotals.beginning,
                                            )}
                                        </td>
                                        <td className="px-3 py-3 text-right tabular-nums text-primary">
                                            {formatInt(filteredTotals.added)}
                                        </td>
                                        <td className="px-3 py-3 text-right tabular-nums text-amber-600">
                                            {formatInt(filteredTotals.deducted)}
                                        </td>
                                        <td className="px-3 py-3 text-right tabular-nums">
                                            {formatInt(filteredTotals.ending)}
                                        </td>
                                        <td className="px-4 py-3">
                                            <StockValueCell
                                                valueRetail={
                                                    filteredTotals.value_retail
                                                }
                                                valueCost={
                                                    filteredTotals.value_cost
                                                }
                                            />
                                        </td>
                                        <td />
                                    </tr>
                                </tfoot>
                            </table>
                        </div>
                            )}
                        </>
                    )}
                </div>

                {/* Category roll-up */}
                {!loading && !error && (report?.categories.length ?? 0) > 0 && (
                    <div className="agri-card p-5">
                        <div className="mb-4 flex items-center gap-2">
                            <div className="agri-icon-box size-8">
                                <Layers className="size-4" />
                            </div>
                            <h3 className="agri-card-title">
                                Category Valuation
                            </h3>
                        </div>
                        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                            {report?.categories.map((c) => (
                                <div
                                    key={c.category}
                                    className="rounded-xl border border-border/60 bg-secondary/20 p-4"
                                >
                                    <div className="flex items-center justify-between">
                                        <p className="font-semibold text-foreground">
                                            {c.category}
                                        </p>
                                        <span className="rounded-full bg-secondary px-2 py-0.5 text-[11px] font-semibold text-muted-foreground">
                                            {c.items} item
                                            {c.items === 1 ? '' : 's'}
                                        </span>
                                    </div>
                                    <div className="mt-2">
                                        <StockValueCell
                                            valueRetail={c.value_retail}
                                            valueCost={c.value_cost}
                                            align="left"
                                        />
                                    </div>
                                    <div className="mt-2 flex items-center gap-3 text-xs text-muted-foreground">
                                        <span className="inline-flex items-center gap-1">
                                            <Boxes className="size-3" />
                                            {formatInt(c.ending)} in stock
                                        </span>
                                        <span className="inline-flex items-center gap-1 text-primary">
                                            <ArrowUpRight className="size-3" />
                                            {formatInt(c.added)}
                                        </span>
                                        <span className="inline-flex items-center gap-1 text-amber-600">
                                            <ArrowDownRight className="size-3" />
                                            {formatInt(c.deducted)}
                                        </span>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </div>
                )}
            </div>

            <StockAdjustDialog
                target={adjustTarget}
                onClose={() => setAdjustTarget(null)}
                onSaved={() => {
                    setAdjustTarget(null);
                    load();
                }}
            />
        </>
    );
}

function varietyStockLabel(row: InventoryRow): string | null {
    if (!row.has_varieties) return null;
    const min = row.min_variety_stock;
    const max = row.max_variety_stock;
    if (min == null || max == null) return null;
    if (min === max) return `${formatInt(min)} each`;
    return `${formatInt(min)}–${formatInt(max)}`;
}

function StockStatusBadges({
    isOut,
    isLow,
    lowCount,
    outCount,
    hasVarieties,
}: {
    isOut: boolean;
    isLow: boolean;
    lowCount?: number;
    outCount?: number;
    hasVarieties?: boolean;
}) {
    if (isOut) {
        return (
            <span className="inline-flex shrink-0 items-center rounded-full bg-destructive/10 px-1.5 py-0.5 text-[10px] font-semibold text-destructive">
                {hasVarieties && (outCount ?? 0) > 0 ? `${outCount} Out` : 'Out'}
            </span>
        );
    }
    if (isLow) {
        return (
            <span className="inline-flex shrink-0 items-center rounded-full bg-amber-500/10 px-1.5 py-0.5 text-[10px] font-semibold text-amber-600">
                {hasVarieties && (lowCount ?? 0) > 0 ? `${lowCount} Low` : 'Low'}
            </span>
        );
    }
    return null;
}

function MovementCells({
    beginning,
    added,
    deducted,
    compact = false,
}: {
    beginning: number;
    added: number;
    deducted: number;
    compact?: boolean;
}) {
    const cellClass = compact ? 'px-3 py-2' : 'px-3 py-3';

    return (
        <>
            <td
                className={cn(
                    cellClass,
                    'text-right tabular-nums text-muted-foreground',
                )}
            >
                {formatInt(beginning)}
            </td>
            <td className={cn(cellClass, 'text-right tabular-nums')}>
                {added > 0 ? (
                    <span className="font-semibold text-primary">
                        +{formatInt(added)}
                    </span>
                ) : (
                    <span className="text-muted-foreground">0</span>
                )}
            </td>
            <td className={cn(cellClass, 'text-right tabular-nums')}>
                {deducted > 0 ? (
                    <span className="font-semibold text-amber-600">
                        −{formatInt(deducted)}
                    </span>
                ) : (
                    <span className="text-muted-foreground">0</span>
                )}
            </td>
        </>
    );
}

function CurrentStockCell({
    ending,
    unit,
    isOut,
    isLow,
    compact = false,
    subtitle,
}: {
    ending: number;
    unit?: string | null;
    isOut: boolean;
    isLow: boolean;
    compact?: boolean;
    subtitle?: string;
}) {
    return (
        <td className={cn(compact ? 'px-3 py-2' : 'px-3 py-3', 'text-right')}>
            <span
                className={cn(
                    'font-bold tabular-nums',
                    isOut
                        ? 'text-destructive'
                        : isLow
                          ? 'text-amber-600'
                          : 'text-foreground',
                )}
            >
                {formatInt(ending)}
            </span>
            <span className="ml-1 text-xs text-muted-foreground">{unit}</span>
            {subtitle ? (
                <p className="mt-0.5 text-[11px] text-muted-foreground">{subtitle}</p>
            ) : null}
        </td>
    );
}

function InventoryTableRowGroup({
    row,
    onAdjust,
    onAdjustVariety,
}: {
    row: InventoryRow;
    onAdjust: () => void;
    onAdjustVariety: (variety: InventoryVarietyRow) => void;
}) {
    const [expanded, setExpanded] = useState(true);
    const lowCount = row.low_varieties_count ?? 0;
    const outCount = row.out_varieties_count ?? 0;
    const varieties = row.varieties ?? [];

    if (!row.has_varieties) {
        return (
            <tr className="border-b border-border/40 transition-colors last:border-0 hover:bg-secondary/30">
                <td className="px-4 py-3">
                    <div className="flex items-center gap-3">
                        <ItemThumbnail imageUrl={row.image_url} alt={row.name} />
                        <div className="min-w-0">
                            <div className="flex items-center gap-2">
                                <p className="truncate font-semibold text-foreground">
                                    {row.name}
                                </p>
                                <StockStatusBadges
                                    isOut={row.is_out_of_stock}
                                    isLow={row.is_low_stock}
                                />
                            </div>
                            <p className="truncate text-xs text-muted-foreground">
                                {row.category}
                            </p>
                        </div>
                    </div>
                </td>
                <MovementCells
                    beginning={row.beginning}
                    added={row.added}
                    deducted={row.deducted}
                />
                <CurrentStockCell
                    ending={row.ending}
                    unit={row.unit}
                    isOut={row.is_out_of_stock}
                    isLow={row.is_low_stock}
                />
                <td className="px-4 py-3">
                    <StockValueCell
                        valueRetail={row.value_retail}
                        valueCost={row.value_cost}
                    />
                </td>
                <td className="px-3 py-3 text-right">
                    <Button
                        variant="outline"
                        size="sm"
                        className="h-8"
                        onClick={onAdjust}
                    >
                        Adjust
                    </Button>
                </td>
            </tr>
        );
    }

    return (
        <>
            <tr className="border-b border-border/40 bg-secondary/25 transition-colors hover:bg-secondary/35">
                <td className="px-4 py-3">
                    <div className="flex items-center gap-3">
                        <button
                            type="button"
                            onClick={() => setExpanded((v) => !v)}
                            className="flex size-8 shrink-0 items-center justify-center rounded-lg border border-border/60 bg-card text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
                            aria-expanded={expanded}
                            aria-label={
                                expanded
                                    ? `Collapse varieties for ${row.name}`
                                    : `Expand varieties for ${row.name}`
                            }
                        >
                            {expanded ? (
                                <ChevronDown className="size-4" />
                            ) : (
                                <ChevronRight className="size-4" />
                            )}
                        </button>
                        <ItemThumbnail imageUrl={row.image_url} alt={row.name} />
                        <div className="min-w-0">
                            <div className="flex flex-wrap items-center gap-2">
                                <p className="truncate font-semibold text-foreground">
                                    {row.name}
                                </p>
                                <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-semibold text-primary">
                                    <Layers className="size-2.5" />
                                    {row.variety_count} varieties
                                </span>
                                <StockStatusBadges
                                    isOut={row.is_out_of_stock}
                                    isLow={row.is_low_stock}
                                    lowCount={lowCount}
                                    outCount={outCount}
                                    hasVarieties
                                />
                            </div>
                            <p className="truncate text-xs text-muted-foreground">
                                {row.category} · Total{' '}
                                {formatInt(row.ending)} {row.unit}
                            </p>
                        </div>
                    </div>
                </td>
                <MovementCells
                    beginning={row.beginning}
                    added={row.added}
                    deducted={row.deducted}
                />
                <CurrentStockCell
                    ending={row.ending}
                    unit={row.unit}
                    isOut={row.is_out_of_stock}
                    isLow={row.is_low_stock}
                    subtitle={`${varietyStockLabel(row) ?? formatInt(row.ending)} range`}
                />
                <td className="px-4 py-3">
                    <StockValueCell
                        valueRetail={row.value_retail}
                        valueCost={row.value_cost}
                    />
                </td>
                <td className="px-3 py-3 text-right">
                    <span className="text-xs font-medium text-muted-foreground">
                        {expanded ? 'Expanded' : 'Collapsed'}
                    </span>
                </td>
            </tr>

            {expanded &&
                varieties.map((variety, index) => (
                    <tr
                        key={variety.variety_id}
                        className={cn(
                            'border-b border-border/30 bg-secondary/10 transition-colors hover:bg-secondary/20',
                            index === varieties.length - 1 && 'border-b-border/50',
                        )}
                    >
                        <td className="px-4 py-2.5">
                            <div className="flex items-start gap-3 pl-11">
                                <div
                                    className="mt-1 h-full min-h-[2rem] w-px shrink-0 bg-primary/25"
                                    aria-hidden
                                />
                                <ItemThumbnail
                                    imageUrl={variety.image_url}
                                    alt={variety.name}
                                    size="sm"
                                />
                                <div className="min-w-0">
                                    <div className="flex flex-wrap items-center gap-2">
                                        <p className="font-medium text-foreground">
                                            {variety.name}
                                        </p>
                                        <StockStatusBadges
                                            isOut={variety.is_out_of_stock}
                                            isLow={variety.is_low_stock}
                                        />
                                    </div>
                                </div>
                            </div>
                        </td>
                        <MovementCells
                            beginning={variety.beginning}
                            added={variety.added}
                            deducted={variety.deducted}
                            compact
                        />
                        <CurrentStockCell
                            ending={variety.ending}
                            unit={variety.unit ?? row.unit}
                            isOut={variety.is_out_of_stock}
                            isLow={variety.is_low_stock}
                            compact
                        />
                        <td className="px-4 py-2">
                            <StockValueCell
                                valueRetail={variety.value_retail}
                                valueCost={variety.value_cost}
                            />
                        </td>
                        <td className="px-3 py-2 text-right">
                            <Button
                                variant="outline"
                                size="sm"
                                className="h-8"
                                onClick={() => onAdjustVariety(variety)}
                            >
                                Adjust
                            </Button>
                        </td>
                    </tr>
                ))}
        </>
    );
}

function StockAdjustDialog({
    target,
    onClose,
    onSaved,
}: {
    target: StockAdjustTarget | null;
    onClose: () => void;
    onSaved: () => void;
}) {
    const [mode, setMode] = useState<'set' | 'add' | 'remove'>('add');
    const [amount, setAmount] = useState('');
    const [saving, setSaving] = useState(false);

    useEffect(() => {
        if (target) {
            setMode('add');
            setAmount('');
        }
    }, [target]);

    if (!target) return null;

    const parsed = parseInt(amount, 10);
    const valid = Number.isFinite(parsed) && parsed >= 0 && amount.trim() !== '';
    const projected =
        mode === 'set'
            ? parsed
            : mode === 'add'
              ? target.live_stock + parsed
              : target.live_stock - parsed;

    const save = async () => {
        if (!valid) {
            toast.error('Enter a valid quantity');
            return;
        }
        if (mode !== 'set' && projected < 0) {
            toast.error('Stock cannot go below zero');
            return;
        }
        setSaving(true);
        try {
            const base = {
                product_id: target.product_id,
                ...(target.variety_id
                    ? { variety_id: target.variety_id }
                    : {}),
            };
            const payload =
                mode === 'set'
                    ? { ...base, stock: parsed }
                    : {
                          ...base,
                          delta: mode === 'add' ? parsed : -parsed,
                      };
            await adjustInventoryStock(payload);
            const label = target.variety_name
                ? `${target.product_name} · ${target.variety_name}`
                : target.product_name;
            toast.success(`Stock updated for ${label}`);
            onSaved();
        } catch (err) {
            toast.error(
                err instanceof Error ? err.message : 'Failed to update stock',
            );
        } finally {
            setSaving(false);
        }
    };

    return (
        <Dialog open={!!target} onOpenChange={(o) => !o && onClose()}>
            <DialogContent className="sm:max-w-md">
                <DialogHeader>
                    <DialogTitle>Adjust Stock</DialogTitle>
                    <DialogDescription>
                        {target.variety_name
                            ? `${target.product_name} · ${target.variety_name}`
                            : target.product_name}{' '}
                        · current {formatInt(target.live_stock)} {target.unit}
                    </DialogDescription>
                </DialogHeader>

                <div className="space-y-4 py-2">
                    <div className="grid grid-cols-3 gap-2">
                        {(
                            [
                                { key: 'add', label: 'Add' },
                                { key: 'remove', label: 'Remove' },
                                { key: 'set', label: 'Set to' },
                            ] as const
                        ).map((m) => (
                            <button
                                key={m.key}
                                type="button"
                                onClick={() => setMode(m.key)}
                                className={cn(
                                    'rounded-lg border px-3 py-2 text-sm font-semibold transition-colors',
                                    mode === m.key
                                        ? 'border-primary bg-primary/10 text-primary'
                                        : 'border-border bg-card text-muted-foreground hover:bg-secondary/50',
                                )}
                            >
                                {m.label}
                            </button>
                        ))}
                    </div>

                    <div className="space-y-1.5">
                        <Label htmlFor="adjust-amount">Quantity</Label>
                        <Input
                            id="adjust-amount"
                            type="number"
                            min={0}
                            inputMode="numeric"
                            autoFocus
                            value={amount}
                            onChange={(e) => setAmount(e.target.value)}
                            placeholder="0"
                        />
                    </div>

                    {valid && (
                        <div className="rounded-lg bg-secondary/40 px-3 py-2 text-sm">
                            New stock level:{' '}
                            <span
                                className={cn(
                                    'font-bold',
                                    projected < 0
                                        ? 'text-destructive'
                                        : 'text-foreground',
                                )}
                            >
                                {formatInt(projected)} {target.unit}
                            </span>
                        </div>
                    )}
                </div>

                <DialogFooter>
                    <Button variant="outline" onClick={onClose} disabled={saving}>
                        Cancel
                    </Button>
                    <Button onClick={save} disabled={saving || !valid}>
                        {saving && (
                            <Loader2 className="size-4 animate-spin" />
                        )}
                        Save
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
}

PosInventory.layout = {
    breadcrumbs: [
        { title: 'Dashboard', href: dashboard() },
        { title: 'Inventory', href: '/pos/inventory' },
    ],
};
