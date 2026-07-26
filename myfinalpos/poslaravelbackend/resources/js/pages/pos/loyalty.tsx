import { Head } from '@inertiajs/react';
import {
    Award,
    Check,
    Gift,
    Loader2,
    Pencil,
    RefreshCw,
    Search,
    Sparkles,
    Star,
    Store,
    UserPlus,
    Users,
    Wallet,
    type LucideIcon,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { toast } from 'sonner';
import { LoyaltyNfcOverlay } from '@/components/pos/loyalty-nfc-overlay';
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
    fetchLoyaltyCards,
    fetchLoyaltyOverview,
    fetchPointsCustomers,
    saveLoyaltySettings,
    savePointsCustomer,
    type LoyaltyCard,
    type LoyaltyOverview,
    type LoyaltySettings,
    type PointsCustomer,
} from '@/lib/loyalty-api';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';

type TabKey = 'customers' | 'program';
type CustomerFilter = 'All' | 'With card' | 'No card' | 'Active';

function formatInt(value: number): string {
    return value.toLocaleString();
}

function formatMoney(value: number): string {
    return value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
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
            : tone === 'primary'
              ? 'bg-primary/10 text-primary'
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

function CustomerLoyaltyCard({
    row,
    onLinkRfid,
}: {
    row: PointsCustomer;
    onLinkRfid: () => void;
}) {
    const statusLabel = row.has_loyalty_card
        ? row.card_status ?? 'Active'
        : 'No card';
    const statusTone =
        statusLabel === 'Active'
            ? 'bg-primary/10 text-primary'
            : statusLabel === 'No card'
              ? 'bg-secondary text-muted-foreground'
              : 'bg-amber-500/10 text-amber-600';

    return (
        <div className="rounded-2xl border border-border/60 bg-card p-4 shadow-sm">
            <div className="flex items-start gap-3">
                <div className="flex size-12 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
                    <Gift className="size-5" />
                </div>
                <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                        <h3 className="text-lg font-bold text-foreground">
                            {row.customer_name}
                        </h3>
                        <span
                            className={cn(
                                'rounded-full px-2 py-0.5 text-[11px] font-semibold',
                                statusTone,
                            )}
                        >
                            {statusLabel}
                        </span>
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">
                        {row.order_type}
                        {row.table_name ? ` · ${row.table_name}` : ''}
                    </p>
                </div>
                <div className="text-right">
                    <p className="text-lg font-bold tabular-nums text-primary">
                        {formatInt(row.points)} pts
                    </p>
                    {row.tier ? (
                        <p className="text-xs font-semibold text-muted-foreground">
                            {row.tier}
                        </p>
                    ) : null}
                </div>
            </div>

            <div className="mt-4 flex flex-wrap gap-4 text-sm text-muted-foreground">
                <span className="inline-flex items-center gap-1.5">
                    <Store className="size-3.5" />
                    {formatInt(row.order_count)} orders
                </span>
                <span className="inline-flex items-center gap-1.5">
                    <Wallet className="size-3.5" />
                    ₱{formatMoney(row.total_spent)} spent
                </span>
                {row.card_number ? (
                    <span className="font-mono text-xs">{row.card_number}</span>
                ) : null}
                {row.nfc_uid ? (
                    <span className="font-mono text-xs text-primary">
                        RFID {row.nfc_uid}
                    </span>
                ) : null}
            </div>

            <div className="mt-4 flex flex-wrap items-center gap-2 border-t border-border/40 pt-3">
                <Button
                    variant="outline"
                    size="sm"
                    className="h-8 text-primary"
                    onClick={onLinkRfid}
                >
                    <Gift className="size-4" />
                    {row.nfc_uid ? 'Update RFID card' : 'Link RFID card'}
                </Button>
                {row.has_loyalty_card ? (
                    <span className="inline-flex items-center gap-1 text-xs font-semibold text-primary">
                        <Sparkles className="size-3.5" />
                        Loyalty member
                    </span>
                ) : null}
            </div>
        </div>
    );
}

export default function PosLoyalty() {
    const [tab, setTab] = useState<TabKey>('customers');
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    const [overview, setOverview] = useState<LoyaltyOverview | null>(null);
    const [settings, setSettings] = useState<LoyaltySettings | null>(null);
    const [cards, setCards] = useState<LoyaltyCard[]>([]);
    const [rows, setRows] = useState<PointsCustomer[]>([]);
    const [query, setQuery] = useState('');
    const [customerFilter, setCustomerFilter] = useState<CustomerFilter>('All');

    const [dialogOpen, setDialogOpen] = useState(false);
    const [saving, setSaving] = useState(false);
    const [savingSettings, setSavingSettings] = useState(false);
    const [nfcLinkTarget, setNfcLinkTarget] = useState<{
        customerId: number;
        customerName: string;
        currentRfidUid?: string | null;
    } | null>(null);
    const nfcLinkedRef = useRef(false);

    const [form, setForm] = useState({
        customer_name: '',
        table_name: '',
        order_type: 'Retail',
        create_loyalty_card: true,
    });

    const [settingsForm, setSettingsForm] = useState<LoyaltySettings>({
        loyalty_enabled: true,
        loyalty_points_per_unit: 50,
        loyalty_spend_unit: 1000,
        loyalty_redeem_points_per_peso: 10,
    });

    const load = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const [summary, cardRes, customerRes] = await Promise.all([
                fetchLoyaltyOverview(),
                fetchLoyaltyCards(),
                fetchPointsCustomers(query),
            ]);
            setOverview(summary.overview);
            setSettings(summary.settings);
            setSettingsForm(summary.settings);
            setCards(cardRes.data ?? []);
            setRows(customerRes.data ?? []);
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Failed to load loyalty data');
        } finally {
            setLoading(false);
        }
    }, [query]);

    useEffect(() => {
        const timer = setTimeout(() => load(), query.trim() === '' ? 0 : 250);
        return () => clearTimeout(timer);
    }, [load, query]);

    const filteredRows = useMemo(() => {
        return rows.filter((row) => {
            switch (customerFilter) {
                case 'With card':
                    return row.has_loyalty_card;
                case 'No card':
                    return !row.has_loyalty_card;
                case 'Active':
                    return row.card_status === 'Active';
                default:
                    return true;
            }
        });
    }, [rows, customerFilter]);

    const memberCount = useMemo(
        () => rows.filter((r) => r.has_loyalty_card).length,
        [rows],
    );

    const retailCount = useMemo(
        () => rows.filter((r) => r.order_type.toLowerCase() === 'retail').length,
        [rows],
    );

    const earnPreview = useMemo(() => {
        const pts = settingsForm.loyalty_points_per_unit || 0;
        const spend = settingsForm.loyalty_spend_unit || 0;
        return `${pts} points when a customer spends ₱${formatMoney(spend)}`;
    }, [settingsForm]);

    const redeemPreview = useMemo(() => {
        const pts = settingsForm.loyalty_redeem_points_per_peso || 0;
        return `${pts} points = ₱1.00 off at checkout`;
    }, [settingsForm]);

    const createCustomer = async () => {
        if (!form.customer_name.trim()) {
            toast.error('Customer name is required');
            return;
        }

        const wantsLoyaltyCard = form.create_loyalty_card;
        const customerName = form.customer_name.trim();

        setSaving(true);
        try {
            const res = await savePointsCustomer({
                customer_name: customerName,
                table_name: form.table_name.trim(),
                order_type: form.order_type,
                create_loyalty_card: false,
            });

            const customerId = res.data?.id ?? res.id;
            setDialogOpen(false);
            setForm({
                customer_name: '',
                table_name: '',
                order_type: 'Retail',
                create_loyalty_card: true,
            });

            if (wantsLoyaltyCard) {
                setNfcLinkTarget({ customerId, customerName });
            } else {
                toast.success('Customer saved');
                load();
            }
        } catch (err) {
            toast.error(err instanceof Error ? err.message : 'Failed to save customer');
        } finally {
            setSaving(false);
        }
    };

    const startNfcLink = (
        customerId: number,
        customerName: string,
        currentRfidUid?: string | null,
    ) => {
        nfcLinkedRef.current = false;
        setNfcLinkTarget({ customerId, customerName, currentRfidUid });
    };

    const closeNfcLink = () => {
        if (!nfcLinkedRef.current) {
            toast.message(
                'RFID card was not linked yet. Open this customer again and choose Link RFID card when you have the physical card ready.',
            );
        }
        nfcLinkedRef.current = false;
        setNfcLinkTarget(null);
        load();
    };

    const handleNfcLinked = useCallback(() => {
        if (nfcLinkedRef.current) {
            return;
        }
        nfcLinkedRef.current = true;
        toast.success('RFID card linked successfully');
        void load();
    }, [load]);

    const saveProgramSettings = async () => {
        if (settingsForm.loyalty_spend_unit <= 0) {
            toast.error('Spend amount must be greater than zero');
            return;
        }
        setSavingSettings(true);
        try {
            const res = await saveLoyaltySettings(settingsForm);
            setSettings(res.settings);
            setSettingsForm(res.settings);
            toast.success('Loyalty program settings saved');
            load();
        } catch (err) {
            toast.error(err instanceof Error ? err.message : 'Failed to save settings');
        } finally {
            setSavingSettings(false);
        }
    };

    const tabs: { key: TabKey; label: string; icon: LucideIcon }[] = [
        { key: 'customers', label: 'Customers & Points', icon: Users },
        { key: 'program', label: 'Program Settings', icon: Award },
    ];

    const customerFilters: CustomerFilter[] = ['All', 'With card', 'No card', 'Active'];

    return (
        <>
            <Head title="Loyalty & Customers" />
            <div className="agri-page-container">
                <PageHeader
                    badge="Loyalty"
                    title="Customers & Loyalty"
                    description="Farmer accounts and loyalty members synced from the server — same rules as the tablet app."
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
                            <Button size="sm" onClick={() => setDialogOpen(true)}>
                                <UserPlus className="size-4" />
                                Add Customer
                            </Button>
                        </>
                    }
                />

                <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
                    <StatCard
                        label="Customers"
                        value={formatInt(rows.length)}
                        icon={Users}
                    />
                    <StatCard
                        label="Loyalty Members"
                        value={formatInt(memberCount)}
                        icon={Gift}
                        tone="amber"
                    />
                    <StatCard
                        label="Retail Accounts"
                        value={formatInt(retailCount)}
                        icon={Store}
                    />
                    <StatCard
                        label="Points on File"
                        value={formatInt(overview?.total_points ?? 0)}
                        icon={Sparkles}
                        tone="primary"
                    />
                </div>

                <div className="agri-card flex flex-wrap gap-2 p-4">
                    {tabs.map((t) => {
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

                {loading ? (
                    <div className="agri-card flex items-center justify-center gap-2 py-20 text-muted-foreground">
                        <Loader2 className="size-5 animate-spin" />
                        Loading...
                    </div>
                ) : error ? (
                    <div className="agri-card py-20 text-center text-sm text-destructive">{error}</div>
                ) : tab === 'customers' ? (
                    <>
                        <div className="agri-card space-y-3 p-4">
                            <div className="relative">
                                <Search className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                <Input
                                    placeholder="Search by name, reference, or card number..."
                                    value={query}
                                    onChange={(e) => setQuery(e.target.value)}
                                    className="border-0 bg-secondary/40 pl-9"
                                />
                            </div>
                            <div className="flex flex-wrap gap-2">
                                {customerFilters.map((filter) => (
                                    <FilterChip
                                        key={filter}
                                        label={filter}
                                        selected={customerFilter === filter}
                                        onClick={() => setCustomerFilter(filter)}
                                    />
                                ))}
                            </div>
                        </div>

                        <div className="flex flex-wrap items-center gap-3">
                            <h2 className="text-lg font-bold text-foreground">Loyalty Members</h2>
                            <span className="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-bold text-primary">
                                {filteredRows.length} shown
                            </span>
                        </div>

                        {filteredRows.length === 0 ? (
                            <div className="agri-card flex flex-col items-center justify-center gap-3 py-16 text-center">
                                <Gift className="size-10 text-muted-foreground" />
                                <p className="text-sm font-medium text-foreground">
                                    No customers match your filters
                                </p>
                                <p className="text-xs text-muted-foreground">
                                    Add a customer or issue a loyalty card to get started.
                                </p>
                            </div>
                        ) : (
                            <div className="grid gap-3">
                                {filteredRows.map((row) => (
                                    <CustomerLoyaltyCard
                                        key={row.customer_id}
                                        row={row}
                                        onLinkRfid={() =>
                                            startNfcLink(
                                                row.customer_id,
                                                row.customer_name,
                                                row.nfc_uid,
                                            )
                                        }
                                    />
                                ))}
                            </div>
                        )}
                    </>
                ) : (
                    <>
                        <div className="agri-card p-5">
                            <div className="mb-1 flex items-center gap-2">
                                <Gift className="size-5 text-primary" />
                                <h3 className="text-lg font-bold text-foreground">
                                    Loyalty Program
                                </h3>
                            </div>
                            <p className="mb-5 text-sm text-muted-foreground">
                                Control earn and redeem rates — matches POS Settings on the tablet
                                app.
                            </p>

                            <label className="mb-5 flex cursor-pointer items-center justify-between rounded-xl border border-border/60 bg-secondary/20 px-4 py-3">
                                <div>
                                    <p className="font-semibold text-foreground">
                                        Loyalty Program
                                    </p>
                                    <p className="text-sm text-muted-foreground">
                                        Let registered customers earn and redeem points
                                    </p>
                                </div>
                                <input
                                    type="checkbox"
                                    checked={settingsForm.loyalty_enabled}
                                    onChange={(e) =>
                                        setSettingsForm((f) => ({
                                            ...f,
                                            loyalty_enabled: e.target.checked,
                                        }))
                                    }
                                    className="size-5 accent-primary"
                                />
                            </label>

                            {settingsForm.loyalty_enabled && (
                                <div className="grid gap-4 md:grid-cols-3">
                                    <div>
                                        <Label htmlFor="loyalty-points">Points earned</Label>
                                        <div className="relative mt-1.5">
                                            <Star className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                            <Input
                                                id="loyalty-points"
                                                type="number"
                                                min={0}
                                                className="pl-9"
                                                value={settingsForm.loyalty_points_per_unit}
                                                onChange={(e) =>
                                                    setSettingsForm((f) => ({
                                                        ...f,
                                                        loyalty_points_per_unit: Math.max(
                                                            0,
                                                            parseInt(e.target.value, 10) || 0,
                                                        ),
                                                    }))
                                                }
                                            />
                                        </div>
                                        <p className="mt-1.5 text-xs text-muted-foreground">
                                            Example: {earnPreview}
                                        </p>
                                    </div>
                                    <div>
                                        <Label htmlFor="loyalty-spend">
                                            Spend amount for points
                                        </Label>
                                        <div className="relative mt-1.5">
                                            <Wallet className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                            <Input
                                                id="loyalty-spend"
                                                type="number"
                                                min={0.01}
                                                step={0.01}
                                                className="pl-9"
                                                value={settingsForm.loyalty_spend_unit}
                                                onChange={(e) =>
                                                    setSettingsForm((f) => ({
                                                        ...f,
                                                        loyalty_spend_unit: Math.max(
                                                            0.01,
                                                            parseFloat(e.target.value) || 0,
                                                        ),
                                                    }))
                                                }
                                            />
                                        </div>
                                    </div>
                                    <div>
                                        <Label htmlFor="loyalty-redeem">
                                            Points needed for ₱1 discount
                                        </Label>
                                        <div className="relative mt-1.5">
                                            <Sparkles className="absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                                            <Input
                                                id="loyalty-redeem"
                                                type="number"
                                                min={1}
                                                className="pl-9"
                                                value={settingsForm.loyalty_redeem_points_per_peso}
                                                onChange={(e) =>
                                                    setSettingsForm((f) => ({
                                                        ...f,
                                                        loyalty_redeem_points_per_peso: Math.max(
                                                            1,
                                                            parseInt(e.target.value, 10) || 1,
                                                        ),
                                                    }))
                                                }
                                            />
                                        </div>
                                        <p className="mt-1.5 text-xs text-muted-foreground">
                                            {redeemPreview}
                                        </p>
                                    </div>
                                </div>
                            )}

                            <div className="mt-5 flex flex-wrap gap-2">
                                <Button onClick={saveProgramSettings} disabled={savingSettings}>
                                    {savingSettings ? (
                                        <Loader2 className="size-4 animate-spin" />
                                    ) : (
                                        <Pencil className="size-4" />
                                    )}
                                    Save program settings
                                </Button>
                                {settings && (
                                    <p className="self-center text-xs text-muted-foreground">
                                        Current: {settings.loyalty_points_per_unit} pts / ₱
                                        {formatMoney(settings.loyalty_spend_unit)} · redeem{' '}
                                        {settings.loyalty_redeem_points_per_peso} pts = ₱1
                                    </p>
                                )}
                            </div>
                        </div>

                        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
                            <div className="agri-card p-5">
                                <h3 className="font-semibold text-foreground">Tier breakdown</h3>
                                <div className="mt-4 grid gap-3 sm:grid-cols-2">
                                    {(overview?.tiers ?? []).length === 0 ? (
                                        <p className="text-sm text-muted-foreground sm:col-span-2">
                                            No tiers yet.
                                        </p>
                                    ) : (
                                        overview?.tiers.map((tier) => (
                                            <div
                                                key={tier.tier}
                                                className="rounded-xl border border-border/60 bg-secondary/20 p-4"
                                            >
                                                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                                                    {tier.tier}
                                                </p>
                                                <p className="mt-2 text-2xl font-semibold tabular-nums">
                                                    {formatInt(tier.members)}
                                                </p>
                                                <p className="text-xs text-muted-foreground">
                                                    {formatInt(tier.points)} pts total
                                                </p>
                                            </div>
                                        ))
                                    )}
                                </div>
                            </div>

                            <div className="agri-card overflow-hidden">
                                <div className="border-b border-border/60 bg-secondary/30 px-4 py-3">
                                    <h3 className="font-semibold text-foreground">
                                        Active loyalty cards
                                    </h3>
                                    <p className="text-xs text-muted-foreground">
                                        {formatInt(overview?.active_cards ?? 0)} active ·{' '}
                                        {formatInt(cards.length)} total
                                    </p>
                                </div>
                                <div className="max-h-80 divide-y divide-border/40 overflow-y-auto">
                                    {cards.length === 0 ? (
                                        <p className="px-4 py-10 text-center text-sm text-muted-foreground">
                                            No cards issued yet.
                                        </p>
                                    ) : (
                                        cards.map((card) => (
                                            <div
                                                key={`${card.customer_id}-${card.card_number}`}
                                                className="flex items-center justify-between gap-3 px-4 py-3"
                                            >
                                                <div className="min-w-0">
                                                    <p className="truncate font-medium">
                                                        {card.customer_name}
                                                    </p>
                                                    <p className="font-mono text-xs text-muted-foreground">
                                                        {card.card_number}
                                                    </p>
                                                </div>
                                                <div className="text-right">
                                                    <p className="font-bold tabular-nums text-primary">
                                                        {formatInt(card.points)} pts
                                                    </p>
                                                    <span
                                                        className={cn(
                                                            'text-xs font-semibold',
                                                            card.status === 'Active'
                                                                ? 'text-primary'
                                                                : 'text-muted-foreground',
                                                        )}
                                                    >
                                                        {card.status}
                                                    </span>
                                                </div>
                                            </div>
                                        ))
                                    )}
                                </div>
                            </div>
                        </div>
                    </>
                )}
            </div>

            <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Add customer</DialogTitle>
                    </DialogHeader>
                    <div className="grid gap-3 py-2">
                        <div>
                            <Label>Customer name</Label>
                            <Input
                                value={form.customer_name}
                                onChange={(e) =>
                                    setForm((f) => ({ ...f, customer_name: e.target.value }))
                                }
                            />
                        </div>
                        <div>
                            <Label>Note / reference</Label>
                            <Input
                                value={form.table_name}
                                onChange={(e) =>
                                    setForm((f) => ({ ...f, table_name: e.target.value }))
                                }
                            />
                        </div>
                        <label className="flex items-center gap-2 text-sm">
                            <input
                                type="checkbox"
                                checked={form.create_loyalty_card}
                                onChange={(e) =>
                                    setForm((f) => ({
                                        ...f,
                                        create_loyalty_card: e.target.checked,
                                    }))
                                }
                                className="accent-primary"
                            />
                            Create loyalty card immediately (scan NFC card after save)
                        </label>
                    </div>
                    <DialogFooter>
                        <Button variant="outline" onClick={() => setDialogOpen(false)}>
                            Cancel
                        </Button>
                        <Button onClick={createCustomer} disabled={saving}>
                            {saving && <Loader2 className="size-4 animate-spin" />}
                            Save
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            <LoyaltyNfcOverlay
                open={nfcLinkTarget !== null}
                customerId={nfcLinkTarget?.customerId ?? 0}
                customerName={nfcLinkTarget?.customerName ?? ''}
                currentRfidUid={nfcLinkTarget?.currentRfidUid}
                onLinked={handleNfcLinked}
                onCancel={closeNfcLink}
            />
        </>
    );
}

PosLoyalty.layout = {
    breadcrumbs: [
        { title: 'Dashboard', href: dashboard() },
        { title: 'Loyalty & Customers', href: '/pos/loyalty' },
    ],
};
