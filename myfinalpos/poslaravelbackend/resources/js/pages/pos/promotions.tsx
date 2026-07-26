import { Head } from '@inertiajs/react';
import {
    AlignLeft,
    Banknote,
    Calendar,
    Check,
    CheckCircle2,
    Loader2,
    PauseCircle,
    Pencil,
    Percent,
    PlayCircle,
    Plus,
    RefreshCw,
    Search,
    ShoppingCart,
    Tag,
    Ticket,
    type LucideIcon,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { PageHeader } from '@/components/page-header';
import { Button } from '@/components/ui/button';
import {
    Dialog,
    DialogContent,
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
    fetchCoupons,
    saveCoupon,
    toggleCoupon,
    type Coupon,
    type CouponDiscountType,
    type CouponFormInput,
} from '@/lib/promotions-api';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';

type StatusFilter = 'All' | 'Active' | 'Scheduled' | 'Expired' | 'Inactive';

function pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
}

function toIsoDate(date: Date): string {
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function formatShortDate(iso: string): string {
    const d = new Date(`${iso}T00:00:00`);
    if (Number.isNaN(d.getTime())) return iso;
    return d.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
    });
}

function formatMoney(value: number): string {
    return value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
}

function couponStatusLabel(coupon: Coupon): Exclude<StatusFilter, 'All'> {
    const isActive = coupon.status === 1;
    if (!isActive) return 'Inactive';

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const start = new Date(`${coupon.start_date}T00:00:00`);
    const end = new Date(`${coupon.end_date}T23:59:59`);

    if (today < start) return 'Scheduled';
    if (today > end) return 'Expired';
    if (coupon.max_uses != null && coupon.usage_count >= coupon.max_uses) {
        return 'Expired';
    }

    return 'Active';
}

function discountLabel(coupon: Coupon): string {
    if (coupon.discount_type === 'percentage') {
        const trimmed =
            coupon.discount_value % 1 === 0
                ? coupon.discount_value.toString()
                : coupon.discount_value.toFixed(1);
        return `${trimmed}% off`;
    }
    return `₱${formatMoney(coupon.discount_value)}`;
}

function statusTone(label: Exclude<StatusFilter, 'All'>): string {
    switch (label) {
        case 'Active':
            return 'bg-primary/10 text-primary';
        case 'Scheduled':
            return 'bg-blue-500/10 text-blue-600';
        case 'Expired':
            return 'bg-amber-500/10 text-amber-600';
        default:
            return 'bg-secondary text-muted-foreground';
    }
}

function StatCard({
    label,
    value,
    icon: Icon,
    tone = 'default',
}: {
    label: string;
    value: string;
    icon: LucideIcon;
    tone?: 'default' | 'amber' | 'primary';
}) {
    const toneClass =
        tone === 'amber'
            ? 'bg-amber-500/10 text-amber-600'
            : 'bg-primary/10 text-primary';

    return (
        <div className="agri-stat-card">
            <div className="mb-3 flex items-center justify-between">
                <span className="agri-stat-label">{label}</span>
                <div
                    className={cn(
                        'flex size-8 items-center justify-center rounded-lg',
                        toneClass,
                    )}
                >
                    <Icon className="size-4" />
                </div>
            </div>
            <p className="agri-stat-value">{value}</p>
        </div>
    );
}

function FilterChip({
    label,
    selected,
    onClick,
}: {
    label: string;
    selected: boolean;
    onClick: () => void;
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className={cn(
                'inline-flex shrink-0 items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm font-semibold transition-colors',
                selected
                    ? 'border-primary bg-primary/10 text-primary'
                    : 'border-border/60 bg-secondary/40 text-muted-foreground hover:bg-secondary/70',
            )}
        >
            {selected && <Check className="size-3.5" />}
            {label}
        </button>
    );
}

function CouponCard({
    coupon,
    toggling,
    onEdit,
    onToggle,
}: {
    coupon: Coupon;
    toggling: boolean;
    onEdit: () => void;
    onToggle: () => void;
}) {
    const status = couponStatusLabel(coupon);
    const isActive = coupon.status === 1;

    return (
        <div className="rounded-2xl border border-border/60 bg-card p-4 shadow-sm">
            <div className="flex items-start gap-3">
                <div className="flex size-12 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
                    <Tag className="size-5" />
                </div>
                <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                        <h3 className="text-lg font-bold text-foreground">
                            {coupon.code}
                        </h3>
                        <span
                            className={cn(
                                'rounded-full px-2 py-0.5 text-[11px] font-semibold',
                                statusTone(status),
                            )}
                        >
                            {status}
                        </span>
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">
                        {coupon.description?.trim() || 'No description'}
                    </p>
                </div>
                <p className="text-lg font-bold text-primary">
                    {discountLabel(coupon)}
                </p>
            </div>

            <div className="mt-4 flex flex-wrap gap-4 text-sm text-muted-foreground">
                <span className="inline-flex items-center gap-1.5">
                    <Calendar className="size-3.5" />
                    {formatShortDate(coupon.start_date)} –{' '}
                    {formatShortDate(coupon.end_date)}
                </span>
                {coupon.min_order_amount > 0 ? (
                    <span className="inline-flex items-center gap-1.5">
                        <ShoppingCart className="size-3.5" />
                        Min ₱{formatMoney(coupon.min_order_amount)}
                    </span>
                ) : null}
                {coupon.max_uses != null ? (
                    <span className="inline-flex items-center gap-1.5">
                        <Ticket className="size-3.5" />
                        {coupon.usage_count}/{coupon.max_uses} used
                    </span>
                ) : null}
            </div>

            <div className="mt-4 flex flex-wrap gap-2 border-t border-border/40 pt-3">
                <Button
                    variant="ghost"
                    size="sm"
                    className="h-8 text-primary"
                    onClick={onEdit}
                >
                    <Pencil className="size-4" />
                    Edit
                </Button>
                <Button
                    variant="ghost"
                    size="sm"
                    className="h-8 text-primary"
                    disabled={toggling}
                    onClick={onToggle}
                >
                    {toggling ? (
                        <Loader2 className="size-4 animate-spin" />
                    ) : isActive ? (
                        <PauseCircle className="size-4" />
                    ) : (
                        <PlayCircle className="size-4" />
                    )}
                    {isActive ? 'Deactivate' : 'Activate'}
                </Button>
            </div>
        </div>
    );
}

type FormState = {
    code: string;
    description: string;
    discount_type: CouponDiscountType;
    discount_value: string;
    min_order_amount: string;
    max_uses: string;
    start_date: string;
    end_date: string;
};

function emptyForm(): FormState {
    const today = new Date();
    const nextYear = new Date(today);
    nextYear.setFullYear(nextYear.getFullYear() + 1);
    return {
        code: '',
        description: '',
        discount_type: 'fixed',
        discount_value: '',
        min_order_amount: '',
        max_uses: '',
        start_date: toIsoDate(today),
        end_date: toIsoDate(nextYear),
    };
}

function formFromCoupon(coupon: Coupon): FormState {
    return {
        code: coupon.code,
        description: coupon.description ?? '',
        discount_type: coupon.discount_type,
        discount_value: String(coupon.discount_value),
        min_order_amount:
            coupon.min_order_amount > 0 ? String(coupon.min_order_amount) : '',
        max_uses: coupon.max_uses != null ? String(coupon.max_uses) : '',
        start_date: coupon.start_date,
        end_date: coupon.end_date,
    };
}

export default function PosPromotions() {
    const [loading, setLoading] = useState(true);
    const [refreshing, setRefreshing] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [coupons, setCoupons] = useState<Coupon[]>([]);
    const [query, setQuery] = useState('');
    const [statusFilter, setStatusFilter] = useState<StatusFilter>('All');

    const [dialogOpen, setDialogOpen] = useState(false);
    const [editing, setEditing] = useState<Coupon | null>(null);
    const [form, setForm] = useState<FormState>(emptyForm);
    const [saving, setSaving] = useState(false);
    const [togglingId, setTogglingId] = useState<number | null>(null);

    const load = useCallback(async (silent = false) => {
        if (silent) setRefreshing(true);
        else setLoading(true);
        setError(null);
        try {
            const res = await fetchCoupons(true);
            setCoupons(res.data ?? []);
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Failed to load coupons');
        } finally {
            setLoading(false);
            setRefreshing(false);
        }
    }, []);

    useEffect(() => {
        load();
    }, [load]);

    const filtered = useMemo(() => {
        const q = query.trim().toLowerCase();
        return coupons.filter((coupon) => {
            const status = couponStatusLabel(coupon);
            const matchesStatus =
                statusFilter === 'All' || status === statusFilter;
            const matchesSearch =
                q === '' ||
                coupon.code.toLowerCase().includes(q) ||
                (coupon.description ?? '').toLowerCase().includes(q);
            return matchesStatus && matchesSearch;
        });
    }, [coupons, query, statusFilter]);

    const activeCount = useMemo(
        () => coupons.filter((c) => couponStatusLabel(c) === 'Active').length,
        [coupons],
    );

    const percentageCount = useMemo(
        () => coupons.filter((c) => c.discount_type === 'percentage').length,
        [coupons],
    );

    const openCreate = () => {
        setEditing(null);
        setForm(emptyForm());
        setDialogOpen(true);
    };

    const openEdit = (coupon: Coupon) => {
        setEditing(coupon);
        setForm(formFromCoupon(coupon));
        setDialogOpen(true);
    };

    const handleSave = async () => {
        const code = form.code.trim().toUpperCase();
        const value = Number.parseFloat(form.discount_value.trim());
        const minOrder = form.min_order_amount.trim()
            ? Number.parseFloat(form.min_order_amount.trim())
            : 0;
        const maxUsesRaw = form.max_uses.trim();
        const maxUses = maxUsesRaw === '' ? null : Number.parseInt(maxUsesRaw, 10);

        if (!code) {
            toast.error('Enter a coupon code');
            return;
        }
        if (!Number.isFinite(value) || value <= 0) {
            toast.error('Enter a valid discount value');
            return;
        }
        if (form.discount_type === 'percentage' && value > 100) {
            toast.error('Percentage discount cannot exceed 100');
            return;
        }
        if (form.end_date < form.start_date) {
            toast.error('End date must be on or after start date');
            return;
        }

        const payload: CouponFormInput = {
            action: editing ? 'update' : 'create',
            id: editing?.id,
            code,
            description: form.description.trim() || undefined,
            discount_type: form.discount_type,
            discount_value: value,
            min_order_amount: Number.isFinite(minOrder) ? minOrder : 0,
            start_date: form.start_date,
            end_date: form.end_date,
            max_uses: maxUses,
        };

        setSaving(true);
        try {
            const res = await saveCoupon(payload);
            toast.success(res.message);
            setDialogOpen(false);
            await load(true);
        } catch (err) {
            toast.error(err instanceof Error ? err.message : 'Failed to save coupon');
        } finally {
            setSaving(false);
        }
    };

    const handleToggle = async (coupon: Coupon) => {
        setTogglingId(coupon.id);
        try {
            const res = await toggleCoupon(coupon.id);
            toast.success(res.message);
            await load(true);
        } catch (err) {
            toast.error(err instanceof Error ? err.message : 'Failed to update coupon');
        } finally {
            setTogglingId(null);
        }
    };

    const filters: StatusFilter[] = [
        'All',
        'Active',
        'Scheduled',
        'Expired',
        'Inactive',
    ];

    return (
        <>
            <Head title="Promotions" />
            <div className="agri-page-container">
                <PageHeader
                    badge="Promotions"
                    title="Promotions"
                    description="Create and manage coupon codes for the POS register."
                    actions={
                        <>
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={() => load(true)}
                                disabled={refreshing || loading}
                            >
                                {refreshing ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <RefreshCw className="size-4" />
                                )}
                                Refresh
                            </Button>
                            <Button size="sm" onClick={openCreate}>
                                <Plus className="size-4" />
                                Add Coupon
                            </Button>
                        </>
                    }
                />

                <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                    <StatCard
                        label="Total Coupons"
                        value={String(coupons.length)}
                        icon={Tag}
                    />
                    <StatCard
                        label="Active Now"
                        value={String(activeCount)}
                        icon={CheckCircle2}
                        tone="primary"
                    />
                    <StatCard
                        label="Percentage Deals"
                        value={String(percentageCount)}
                        icon={Percent}
                        tone="amber"
                    />
                </div>

                <div className="agri-card space-y-3 p-4">
                    <div className="relative">
                        <Search className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                        <Input
                            value={query}
                            onChange={(e) => setQuery(e.target.value)}
                            placeholder="Search by code or description..."
                            className="pl-9"
                        />
                    </div>
                    <div className="flex flex-wrap gap-2">
                        {filters.map((filter) => (
                            <FilterChip
                                key={filter}
                                label={filter}
                                selected={statusFilter === filter}
                                onClick={() => setStatusFilter(filter)}
                            />
                        ))}
                    </div>
                </div>

                <div className="flex flex-wrap items-center gap-2">
                    <h2 className="text-lg font-bold">Coupon Codes</h2>
                    <span className="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-bold text-primary">
                        {filtered.length} shown
                    </span>
                </div>

                {loading ? (
                    <div className="flex items-center justify-center py-16 text-muted-foreground">
                        <Loader2 className="size-6 animate-spin" />
                    </div>
                ) : error ? (
                    <div className="agri-card p-8 text-center text-destructive">
                        {error}
                    </div>
                ) : filtered.length === 0 ? (
                    <div className="agri-card flex flex-col items-center gap-3 p-10 text-muted-foreground">
                        <Tag className="size-10 opacity-40" />
                        <p>No coupons match your filters.</p>
                    </div>
                ) : (
                    <div className="space-y-3">
                        {filtered.map((coupon) => (
                            <CouponCard
                                key={coupon.id}
                                coupon={coupon}
                                toggling={togglingId === coupon.id}
                                onEdit={() => openEdit(coupon)}
                                onToggle={() => handleToggle(coupon)}
                            />
                        ))}
                    </div>
                )}
            </div>

            <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
                <DialogContent className="max-w-lg">
                    <DialogHeader>
                        <DialogTitle className="flex items-center gap-2">
                            <Tag className="size-5 text-primary" />
                            {editing ? 'Edit Coupon' : 'Add Coupon'}
                        </DialogTitle>
                    </DialogHeader>
                    <div className="grid gap-3 py-2">
                        <div>
                            <Label>
                                Coupon Code <span className="text-destructive">*</span>
                            </Label>
                            <div className="relative">
                                <Ticket className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                <Input
                                    value={form.code}
                                    onChange={(e) =>
                                        setForm((f) => ({
                                            ...f,
                                            code: e.target.value.toUpperCase(),
                                        }))
                                    }
                                    className="pl-9 uppercase"
                                    placeholder="FARM10"
                                />
                            </div>
                        </div>
                        <div>
                            <Label>Description</Label>
                            <div className="relative">
                                <AlignLeft className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                <Input
                                    value={form.description}
                                    onChange={(e) =>
                                        setForm((f) => ({
                                            ...f,
                                            description: e.target.value,
                                        }))
                                    }
                                    className="pl-9"
                                    placeholder="Seasonal farm supply promo"
                                />
                            </div>
                        </div>
                        <div>
                            <Label>
                                Discount Type <span className="text-destructive">*</span>
                            </Label>
                            <Select
                                value={form.discount_type}
                                onValueChange={(v: CouponDiscountType) =>
                                    setForm((f) => ({ ...f, discount_type: v }))
                                }
                            >
                                <SelectTrigger>
                                    <SelectValue />
                                </SelectTrigger>
                                <SelectContent>
                                    <SelectItem value="fixed">Fixed amount</SelectItem>
                                    <SelectItem value="percentage">Percentage</SelectItem>
                                </SelectContent>
                            </Select>
                        </div>
                        <div>
                            <Label>
                                Discount Value <span className="text-destructive">*</span>
                            </Label>
                            <div className="relative">
                                {form.discount_type === 'percentage' ? (
                                    <Percent className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                ) : (
                                    <Banknote className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                )}
                                <Input
                                    type="number"
                                    min={0}
                                    step={form.discount_type === 'percentage' ? 1 : 0.01}
                                    value={form.discount_value}
                                    onChange={(e) =>
                                        setForm((f) => ({
                                            ...f,
                                            discount_value: e.target.value,
                                        }))
                                    }
                                    className="pl-9"
                                    placeholder={
                                        form.discount_type === 'percentage' ? '10' : '10.00'
                                    }
                                />
                            </div>
                        </div>
                        <div>
                            <Label>Minimum Order</Label>
                            <div className="relative">
                                <ShoppingCart className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                <Input
                                    type="number"
                                    min={0}
                                    step={0.01}
                                    value={form.min_order_amount}
                                    onChange={(e) =>
                                        setForm((f) => ({
                                            ...f,
                                            min_order_amount: e.target.value,
                                        }))
                                    }
                                    className="pl-9"
                                    placeholder="Optional"
                                />
                            </div>
                        </div>
                        <div>
                            <Label>Max Uses</Label>
                            <div className="relative">
                                <Ticket className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                <Input
                                    type="number"
                                    min={1}
                                    step={1}
                                    value={form.max_uses}
                                    onChange={(e) =>
                                        setForm((f) => ({ ...f, max_uses: e.target.value }))
                                    }
                                    className="pl-9"
                                    placeholder="Unlimited"
                                />
                            </div>
                        </div>
                        <div className="grid gap-3 sm:grid-cols-2">
                            <div>
                                <Label>Start</Label>
                                <div className="relative">
                                    <Calendar className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                    <Input
                                        type="date"
                                        value={form.start_date}
                                        onChange={(e) =>
                                            setForm((f) => ({
                                                ...f,
                                                start_date: e.target.value,
                                                end_date:
                                                    f.end_date < e.target.value
                                                        ? e.target.value
                                                        : f.end_date,
                                            }))
                                        }
                                        className="pl-9"
                                    />
                                </div>
                            </div>
                            <div>
                                <Label>End</Label>
                                <div className="relative">
                                    <Calendar className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                    <Input
                                        type="date"
                                        value={form.end_date}
                                        min={form.start_date}
                                        onChange={(e) =>
                                            setForm((f) => ({
                                                ...f,
                                                end_date: e.target.value,
                                            }))
                                        }
                                        className="pl-9"
                                    />
                                </div>
                            </div>
                        </div>
                    </div>
                    <DialogFooter>
                        <Button variant="outline" onClick={() => setDialogOpen(false)}>
                            Cancel
                        </Button>
                        <Button onClick={handleSave} disabled={saving}>
                            {saving && <Loader2 className="size-4 animate-spin" />}
                            Save
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </>
    );
}

PosPromotions.layout = {
    breadcrumbs: [
        { title: 'Dashboard', href: dashboard() },
        { title: 'Promotions', href: '/pos/promotions' },
    ],
};
