import { Head } from '@inertiajs/react';
import {
    AlertTriangle,
    Loader2,
    Lock,
    Play,
    Printer,
    ReceiptText,
    RefreshCw,
} from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
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
import { cn } from '@/lib/utils';

type MachineIdentity = {
    store_name: string;
    address_line1: string;
    address_line2: string;
    tin: string;
    tax_status: string;
    min_no: string;
    machine_serial_no: string;
    ptu_no: string;
    atp_no: string;
    series_range: string;
};

type Reading = {
    id: number;
    terminal_id: string;
    type: string;
    z_counter: number | null;
    reset_counter: number;
    business_date: string;
    beginning_or: string | null;
    ending_or: string | null;
    beginning_grand_total: number | string;
    ending_grand_total: number | string;
    gross_sales: number | string;
    net_sales: number | string;
    vatable_sales: number | string;
    vat_amount: number | string;
    vat_exempt_sales: number | string;
    zero_rated_sales: number | string;
    sc_discount: number | string;
    pwd_discount: number | string;
    naac_discount: number | string;
    solo_parent_discount: number | string;
    other_discount: number | string;
    discount_total: number | string;
    refund_amount: number | string;
    refund_count: number;
    void_amount: number | string;
    void_count: number;
    transaction_count: number;
    payment_breakdown: Record<string, number>;
    uncaptured_fields: string[];
    created_at?: string;
};

type Session = {
    id: number;
    terminal_id: string;
    opened_at: string;
    business_date: string;
} | null;

type Counters = {
    grand_total_accumulated: number | string;
    z_counter: number;
    reset_counter: number;
};

type PageProps = {
    terminals: string[];
    machineIdentity: MachineIdentity;
    missingIdentityFields: string[];
    uncapturedBirFields: string[];
    hasCashDrawerPin: boolean;
};

function peso(value: number | string): string {
    const n = typeof value === 'number' ? value : Number(value ?? 0);
    return `₱${n.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    })}`;
}

const IDENTITY_LABELS: Record<string, string> = {
    store_name: 'Registered name',
    tin: 'TIN',
    min_no: 'MIN (Machine Identification Number)',
    machine_serial_no: 'Machine serial number',
    ptu_no: 'Permit to Use number',
};

export default function Readings({
    terminals,
    machineIdentity,
    missingIdentityFields,
    uncapturedBirFields,
    hasCashDrawerPin,
}: PageProps) {
    const [terminalId, setTerminalId] = useState(terminals[0] ?? '');
    const [session, setSession] = useState<Session>(null);
    const [counters, setCounters] = useState<Counters | null>(null);
    const [history, setHistory] = useState<Reading[]>([]);
    const [reading, setReading] = useState<Reading | null>(null);
    const [loading, setLoading] = useState(false);
    const [busy, setBusy] = useState(false);
    const [pinOpen, setPinOpen] = useState(false);
    const [pin, setPin] = useState('');

    const loadStatus = useCallback(async () => {
        if (!terminalId) return;
        setLoading(true);
        try {
            const res = await fetch(
                `/pos/readings/status?terminal_id=${encodeURIComponent(terminalId)}`,
                { headers: { Accept: 'application/json' } },
            );
            const body = await res.json();
            if (!res.ok || !body.success) {
                throw new Error(body.message ?? 'Failed to load status');
            }
            setSession(body.session ?? null);
            setCounters(body.counters ?? null);
            setHistory(body.history ?? []);
        } catch (e) {
            toast.error(e instanceof Error ? e.message : 'Failed to load status');
        } finally {
            setLoading(false);
        }
    }, [terminalId]);

    useEffect(() => {
        void loadStatus();
    }, [loadStatus]);

    const post = async (url: string, payload: Record<string, string>) => {
        const token =
            document
                .querySelector('meta[name="csrf-token"]')
                ?.getAttribute('content') ?? '';

        const res = await fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Accept: 'application/json',
                'X-CSRF-TOKEN': token,
                'X-Requested-With': 'XMLHttpRequest',
            },
            body: JSON.stringify({ terminal_id: terminalId, ...payload }),
        });
        const body = await res.json();
        if (!res.ok || !body.success) {
            throw new Error(body.message ?? 'Request failed');
        }
        return body;
    };

    const openShift = async () => {
        setBusy(true);
        try {
            await post('/pos/readings/open', {});
            toast.success(`Shift opened on ${terminalId}`);
            await loadStatus();
        } catch (e) {
            toast.error(e instanceof Error ? e.message : 'Could not open shift');
        } finally {
            setBusy(false);
        }
    };

    const takeX = async () => {
        setBusy(true);
        try {
            const body = await post('/pos/readings/x', {});
            setReading(body.reading);
            toast.success('X reading taken');
            await loadStatus();
        } catch (e) {
            toast.error(e instanceof Error ? e.message : 'Could not take X reading');
        } finally {
            setBusy(false);
        }
    };

    const takeZ = async () => {
        setBusy(true);
        try {
            const body = await post('/pos/readings/z', { cash_drawer_pin: pin });
            setReading(body.reading);
            setPinOpen(false);
            setPin('');
            toast.success(`Z reading #${body.reading.z_counter} — shift closed`);
            await loadStatus();
        } catch (e) {
            toast.error(e instanceof Error ? e.message : 'Could not take Z reading');
        } finally {
            setBusy(false);
        }
    };

    const isOpen = session !== null;

    return (
        <>
            <Head title="X / Z Reading" />
            <div className="agri-page-container">
                <PageHeader
                    title="X / Z Reading"
                    description="Shift totals per register, in the BIR reading format."
                />

                {missingIdentityFields.length > 0 && (
                    <div className="rounded-xl border border-caramel/50 bg-caramel/10 p-4">
                        <div className="flex items-start gap-3">
                            <AlertTriangle className="mt-0.5 size-5 shrink-0 text-caramel-deep" />
                            <div className="text-sm">
                                <p className="font-bold text-caramel-deep">
                                    Machine registration is incomplete
                                </p>
                                <p className="mt-1 text-muted-foreground">
                                    A BIR reading must carry these. Fill them in
                                    under Settings before filing anything printed
                                    here:
                                </p>
                                <ul className="mt-2 list-inside list-disc text-muted-foreground">
                                    {missingIdentityFields.map((field) => (
                                        <li key={field}>
                                            {IDENTITY_LABELS[field] ?? field}
                                        </li>
                                    ))}
                                </ul>
                            </div>
                        </div>
                    </div>
                )}

                {uncapturedBirFields.length > 0 && (
                    <div className="rounded-xl border border-destructive/40 bg-destructive/8 p-4 text-sm">
                        <p className="font-bold text-destructive">
                            {uncapturedBirFields.length} BIR field(s) are not
                            captured at the point of sale
                        </p>
                        <p className="mt-1 text-muted-foreground">
                            Run <code>php artisan migrate</code> so checkout can
                            record them. Until then these print as “not captured”
                            rather than as zero.
                        </p>
                    </div>
                )}

                <div className="agri-card p-5">
                    <div className="flex flex-wrap items-end gap-3">
                        <div className="min-w-48">
                            <Label htmlFor="terminal">Terminal</Label>
                            <select
                                id="terminal"
                                value={terminalId}
                                onChange={(e) => setTerminalId(e.target.value)}
                                className="mt-1 h-10 w-full rounded-lg border border-border bg-card px-3 text-sm"
                            >
                                {terminals.length === 0 && (
                                    <option value="">No terminals yet</option>
                                )}
                                {terminals.map((id) => (
                                    <option key={id} value={id}>
                                        {id}
                                    </option>
                                ))}
                            </select>
                        </div>

                        <Button
                            variant="outline"
                            onClick={() => void loadStatus()}
                            disabled={loading || !terminalId}
                        >
                            {loading ? (
                                <Loader2 className="size-4 animate-spin" />
                            ) : (
                                <RefreshCw className="size-4" />
                            )}
                            Refresh
                        </Button>

                        {!isOpen ? (
                            <Button
                                onClick={() => void openShift()}
                                disabled={busy || !terminalId}
                            >
                                <Play className="size-4" />
                                Open shift
                            </Button>
                        ) : (
                            <>
                                <Button
                                    variant="outline"
                                    onClick={() => void takeX()}
                                    disabled={busy}
                                >
                                    <ReceiptText className="size-4" />
                                    X reading
                                </Button>
                                <Button
                                    onClick={() => setPinOpen(true)}
                                    disabled={busy || !hasCashDrawerPin}
                                    title={
                                        hasCashDrawerPin
                                            ? undefined
                                            : 'Set a cash drawer PIN in Settings first'
                                    }
                                    className="bg-destructive text-white hover:bg-destructive/90"
                                >
                                    <Lock className="size-4" />
                                    Z reading (close shift)
                                </Button>
                            </>
                        )}
                    </div>

                    {counters && (
                        <div className="mt-5 grid gap-3 sm:grid-cols-3">
                            <Stat
                                label="Accumulated grand total"
                                value={peso(counters.grand_total_accumulated)}
                            />
                            <Stat label="Z counter" value={`${counters.z_counter}`} />
                            <Stat
                                label="Reset counter"
                                value={`${counters.reset_counter}`}
                            />
                        </div>
                    )}

                    <p className="mt-4 text-xs text-muted-foreground">
                        {isOpen
                            ? `Shift open since ${session?.opened_at ?? '—'}.`
                            : 'No shift is open on this terminal.'}
                    </p>
                </div>

                {reading && (
                    <ReadingSheet
                        reading={reading}
                        identity={machineIdentity}
                    />
                )}

                {history.length > 0 && (
                    <div className="agri-card p-5">
                        <h2 className="agri-card-title mb-3">Recent readings</h2>
                        <div className="overflow-x-auto">
                            <table className="w-full text-sm">
                                <thead>
                                    <tr className="border-b border-border text-left text-xs text-muted-foreground uppercase">
                                        <th className="py-2">Type</th>
                                        <th className="py-2">Date</th>
                                        <th className="py-2">OR range</th>
                                        <th className="py-2 text-right">Net sales</th>
                                        <th className="py-2 text-right">Txns</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {history.map((row) => (
                                        <tr
                                            key={row.id}
                                            className="cursor-pointer border-b border-border/60 hover:bg-secondary/50"
                                            onClick={() => setReading(row)}
                                        >
                                            <td className="py-2 font-bold">
                                                {row.type === 'z'
                                                    ? `Z #${row.z_counter}`
                                                    : 'X'}
                                            </td>
                                            <td className="py-2">
                                                {row.business_date}
                                            </td>
                                            <td className="py-2 text-xs text-muted-foreground">
                                                {row.beginning_or ?? '—'} →{' '}
                                                {row.ending_or ?? '—'}
                                            </td>
                                            <td className="py-2 text-right tabular-nums">
                                                {peso(row.net_sales)}
                                            </td>
                                            <td className="py-2 text-right tabular-nums">
                                                {row.transaction_count}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </div>
                )}
            </div>

            <Dialog open={pinOpen} onOpenChange={setPinOpen}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Close shift with a Z reading?</DialogTitle>
                    </DialogHeader>
                    <p className="text-sm text-muted-foreground">
                        This closes the shift, increases the Z counter and adds
                        the shift to the accumulated grand total. It cannot be
                        undone.
                    </p>
                    <div>
                        <Label htmlFor="zpin">Cash drawer PIN</Label>
                        <Input
                            id="zpin"
                            type="password"
                            value={pin}
                            onChange={(e) => setPin(e.target.value)}
                            className="mt-1"
                            autoFocus
                        />
                    </div>
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setPinOpen(false)}
                        >
                            Cancel
                        </Button>
                        <Button
                            onClick={() => void takeZ()}
                            disabled={busy || pin.length === 0}
                            className="bg-destructive text-white hover:bg-destructive/90"
                        >
                            Confirm Z reading
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </>
    );
}

function Stat({ label, value }: { label: string; value: string }) {
    return (
        <div className="rounded-xl border border-border bg-secondary/40 p-3">
            <p className="agri-stat-label">{label}</p>
            <p className="mt-1 text-lg font-extrabold tabular-nums text-foreground">
                {value}
            </p>
        </div>
    );
}

/** The reading itself, laid out in the order BIR expects it printed. */
function ReadingSheet({
    reading,
    identity,
}: {
    reading: Reading;
    identity: MachineIdentity;
}) {
    const isZ = reading.type === 'z';
    const uncaptured = (field: string) =>
        reading.uncaptured_fields.includes(field);

    return (
        <div className="agri-card p-5 print:border-0 print:shadow-none">
            <div className="mb-4 flex items-start justify-between gap-3">
                <div>
                    <h2 className="text-lg font-extrabold text-foreground">
                        {isZ ? `Z READING #${reading.z_counter}` : 'X READING'}
                    </h2>
                    <p className="text-xs text-muted-foreground">
                        {reading.terminal_id} · {reading.business_date}
                    </p>
                </div>
                <Button
                    variant="outline"
                    size="sm"
                    onClick={() => window.print()}
                    className="print:hidden"
                >
                    <Printer className="size-4" />
                    Print
                </Button>
            </div>

            <div className="mb-4 rounded-lg bg-secondary/40 p-3 text-xs leading-relaxed">
                <p className="font-bold text-foreground">
                    {identity.store_name || '(registered name not set)'}
                </p>
                <p className="text-muted-foreground">{identity.address_line1}</p>
                <p className="text-muted-foreground">{identity.address_line2}</p>
                <p className="mt-1 text-muted-foreground">
                    TIN {identity.tin || '—'} · {identity.tax_status}
                </p>
                <p className="text-muted-foreground">
                    MIN {identity.min_no || '(not set)'} · SN{' '}
                    {identity.machine_serial_no || '(not set)'}
                </p>
                <p className="text-muted-foreground">
                    PTU {identity.ptu_no || '—'}
                </p>
            </div>

            <Section>
                <Line label="Beginning OR" value={reading.beginning_or ?? '—'} />
                <Line label="Ending OR" value={reading.ending_or ?? '—'} />
                <Line
                    label="Transactions"
                    value={`${reading.transaction_count}`}
                />
                <Line label="Reset counter" value={`${reading.reset_counter}`} />
            </Section>

            <Section>
                <Line label="Gross sales" value={peso(reading.gross_sales)} />
                <Line
                    label="Discounts"
                    value={`-${peso(reading.discount_total)}`}
                />
                <Line
                    label="Refunds"
                    value={`-${peso(reading.refund_amount)} (${reading.refund_count})`}
                />
                <Line
                    label="Voids"
                    value={`${peso(reading.void_amount)} (${reading.void_count})`}
                />
                <Line label="NET SALES" value={peso(reading.net_sales)} bold />
            </Section>

            <Section title="VAT">
                <Line label="VATable sales" value={peso(reading.vatable_sales)} />
                <Line label="VAT amount" value={peso(reading.vat_amount)} />
                <Line
                    label="VAT-exempt sales"
                    value={peso(reading.vat_exempt_sales)}
                    uncaptured={uncaptured('vat_exempt_sales')}
                />
                <Line
                    label="Zero-rated sales"
                    value={peso(reading.zero_rated_sales)}
                    uncaptured={uncaptured('zero_rated_sales')}
                />
            </Section>

            <Section title="Statutory discounts">
                <Line
                    label="Senior citizen"
                    value={peso(reading.sc_discount)}
                    uncaptured={uncaptured('sc_discount')}
                />
                <Line
                    label="PWD"
                    value={peso(reading.pwd_discount)}
                    uncaptured={uncaptured('pwd_discount')}
                />
                <Line
                    label="NAAC"
                    value={peso(reading.naac_discount)}
                    uncaptured={uncaptured('naac_discount')}
                />
                <Line
                    label="Solo parent"
                    value={peso(reading.solo_parent_discount)}
                    uncaptured={uncaptured('solo_parent_discount')}
                />
                <Line
                    label="Other discounts"
                    value={peso(reading.other_discount)}
                />
            </Section>

            <Section title="Accumulated">
                <Line
                    label="Old grand total"
                    value={peso(reading.beginning_grand_total)}
                />
                <Line
                    label="New grand total"
                    value={peso(reading.ending_grand_total)}
                    bold
                />
            </Section>

            {Object.keys(reading.payment_breakdown ?? {}).length > 0 && (
                <Section title="Payments">
                    {Object.entries(reading.payment_breakdown).map(
                        ([method, amount]) => (
                            <Line
                                key={method}
                                label={method}
                                value={peso(amount)}
                            />
                        ),
                    )}
                </Section>
            )}
        </div>
    );
}

function Section({
    title,
    children,
}: {
    title?: string;
    children: React.ReactNode;
}) {
    return (
        <div className="border-t border-border py-3 first:border-t-0">
            {title && (
                <p className="agri-stat-label mb-1.5">{title}</p>
            )}
            {children}
        </div>
    );
}

function Line({
    label,
    value,
    bold = false,
    uncaptured = false,
}: {
    label: string;
    value: string;
    bold?: boolean;
    uncaptured?: boolean;
}) {
    return (
        <div className="flex items-center justify-between py-0.5 text-sm">
            <span className={cn(bold ? 'font-bold text-foreground' : 'text-muted-foreground')}>
                {label}
            </span>
            {uncaptured ? (
                <span className="text-xs font-bold text-caramel-deep italic">
                    not captured
                </span>
            ) : (
                <span
                    className={cn(
                        'tabular-nums',
                        bold
                            ? 'text-base font-extrabold text-foreground'
                            : 'font-semibold text-foreground',
                    )}
                >
                    {value}
                </span>
            )}
        </div>
    );
}
