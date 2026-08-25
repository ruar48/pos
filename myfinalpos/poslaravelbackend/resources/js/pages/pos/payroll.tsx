import { Head } from '@inertiajs/react';
import {
    AlertTriangle,
    Download,
    Loader2,
    RefreshCw,
    Wallet,
} from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
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
    fetchPayrollReport,
    savePayrollRate,
    type PayrollRow,
} from '@/lib/payroll-api';
import {
    downloadAttendanceExport,
    manualClockOutStaffAttendance,
} from '@/lib/staff-api';
import { dashboard } from '@/routes';

function pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
}

function toIsoDate(date: Date): string {
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function firstOfMonth(): string {
    const now = new Date();
    return toIsoDate(new Date(now.getFullYear(), now.getMonth(), 1));
}

function today(): string {
    return toIsoDate(new Date());
}

function formatMoney(amount: number): string {
    return `₱${amount.toLocaleString('en-PH', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    })}`;
}

export default function PosPayroll() {
    const [start, setStart] = useState(firstOfMonth());
    const [end, setEnd] = useState(today());
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [rows, setRows] = useState<PayrollRow[]>([]);
    const [rateDrafts, setRateDrafts] = useState<Record<number, string>>({});
    const [savingUserId, setSavingUserId] = useState<number | null>(null);
    const [fixTarget, setFixTarget] = useState<PayrollRow | null>(null);
    const [fixDate, setFixDate] = useState('');
    const [fixTime, setFixTime] = useState('');
    const [fixing, setFixing] = useState(false);
    const [exporting, setExporting] = useState(false);

    const load = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const res = await fetchPayrollReport(start, end);
            setRows(res.rows);
            setRateDrafts(
                Object.fromEntries(
                    res.rows.map((row) => [row.user_id, String(row.hourly_rate)]),
                ),
            );
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Failed to load payroll');
        } finally {
            setLoading(false);
        }
    }, [start, end]);

    useEffect(() => {
        void load();
    }, [load]);

    // Exports the same Start/End range the table above is showing, so what
    // downloads always matches what's on screen. The workbook's Payroll
    // sheet lists every staff member per day across the range, day after
    // day - a 1st-to-20th range continues each following date underneath
    // the previous one.
    const exportRange = async () => {
        setExporting(true);
        try {
            await downloadAttendanceExport(start, end);
        } catch (err) {
            toast.error(err instanceof Error ? err.message : 'Export failed');
        } finally {
            setExporting(false);
        }
    };

    const saveRate = async (row: PayrollRow) => {
        const draft = rateDrafts[row.user_id] ?? '0';
        const rate = Number(draft);
        if (!Number.isFinite(rate) || rate < 0) {
            toast.error('Enter a valid hourly rate.');
            return;
        }

        setSavingUserId(row.user_id);
        try {
            await savePayrollRate({ user_id: row.user_id, hourly_rate: rate });
            toast.success(`Hourly rate updated · ${row.full_name}`);
            await load();
        } catch (err) {
            toast.error(
                err instanceof Error ? err.message : 'Could not save hourly rate',
            );
        } finally {
            setSavingUserId(null);
        }
    };

    const openFixTimeOut = (row: PayrollRow) => {
        setFixTarget(row);
        setFixDate(row.missing_time_out_dates[0] ?? '');
        setFixTime('');
    };

    const closeFixTimeOut = () => {
        setFixTarget(null);
        setFixDate('');
        setFixTime('');
    };

    const saveFixTimeOut = async () => {
        if (!fixTarget || fixDate === '' || fixTime === '') {
            toast.error('Pick a date and time');
            return;
        }

        setFixing(true);
        try {
            await manualClockOutStaffAttendance({
                user_id: fixTarget.user_id,
                date: fixDate,
                time: fixTime,
            });
            toast.success(`Time-out recorded · ${fixTarget.full_name}`);
            closeFixTimeOut();
            await load();
        } catch (err) {
            toast.error(
                err instanceof Error ? err.message : 'Could not record time-out',
            );
        } finally {
            setFixing(false);
        }
    };

    return (
        <>
            <Head title="Payroll" />
            <div className="agri-page-container">
                <PageHeader
                    badge="Staff"
                    title="Payroll"
                    description="Break hours, total hours, and pay per staff member — set an hourly rate to compute Total Pay."
                    actions={
                        <div className="flex flex-wrap items-center gap-2">
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={() => void exportRange()}
                                disabled={exporting || loading}
                            >
                                {exporting ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <Download className="size-4" />
                                )}
                                Export Excel
                            </Button>
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
                        </div>
                    }
                />

                <div className="agri-card flex flex-wrap items-end gap-4 p-4">
                    <div className="grid gap-1.5">
                        <Label htmlFor="payroll-start">Start</Label>
                        <Input
                            id="payroll-start"
                            type="date"
                            value={start}
                            max={end}
                            onChange={(e) => setStart(e.target.value)}
                        />
                    </div>
                    <div className="grid gap-1.5">
                        <Label htmlFor="payroll-end">End</Label>
                        <Input
                            id="payroll-end"
                            type="date"
                            value={end}
                            min={start}
                            max={today()}
                            onChange={(e) => setEnd(e.target.value)}
                        />
                    </div>
                </div>

                <div className="agri-card overflow-hidden p-0">
                    <div className="border-b border-border/60 px-4 py-3">
                        <h3 className="flex items-center gap-2 font-semibold text-foreground">
                            <Wallet className="size-4" />
                            Staff Payroll
                        </h3>
                        <p className="text-xs text-muted-foreground">
                            {start === end ? start : `${start} – ${end}`}
                        </p>
                    </div>

                    {loading ? (
                        <div className="flex items-center justify-center py-16">
                            <Loader2 className="size-6 animate-spin text-muted-foreground" />
                        </div>
                    ) : error ? (
                        <p className="px-4 py-8 text-center text-sm text-destructive">
                            {error}
                        </p>
                    ) : rows.length === 0 ? (
                        <p className="px-4 py-8 text-center text-sm text-muted-foreground">
                            No attendance activity in this range.
                        </p>
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full text-sm">
                                <thead>
                                    <tr className="border-b border-border/60 text-left text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                                        <th className="px-4 py-2">Staff Name</th>
                                        <th className="px-4 py-2">Break Hours</th>
                                        <th className="px-4 py-2">Total Hours Mins</th>
                                        <th className="px-4 py-2">Hourly Pay</th>
                                        <th className="px-4 py-2 text-right">Total Pay</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-border/50">
                                    {rows.map((row) => (
                                        <tr key={row.user_id}>
                                            <td className="px-4 py-3 font-semibold text-foreground">
                                                <div className="flex items-center gap-1.5">
                                                    {row.full_name}
                                                    {row.has_missing_time_out && (
                                                        <button
                                                            type="button"
                                                            title={`Incomplete attendance on ${row.missing_time_out_dates.join(', ')} — click to record the time-out. Hours/pay for that day stay at zero until it's recorded.`}
                                                            onClick={() => openFixTimeOut(row)}
                                                            className="rounded-full p-0.5 hover:bg-amber-500/10"
                                                        >
                                                            <AlertTriangle className="size-3.5 text-amber-500" />
                                                        </button>
                                                    )}
                                                </div>
                                            </td>
                                            <td className="px-4 py-3 text-muted-foreground">
                                                {row.break_hours_label}
                                            </td>
                                            <td className="px-4 py-3 text-muted-foreground">
                                                {row.total_hours_label}
                                            </td>
                                            <td className="px-4 py-3">
                                                <div className="flex items-center gap-2">
                                                    <Input
                                                        type="number"
                                                        min={0}
                                                        step="0.01"
                                                        className="h-8 w-24"
                                                        value={
                                                            rateDrafts[row.user_id] ??
                                                            String(row.hourly_rate)
                                                        }
                                                        onChange={(e) =>
                                                            setRateDrafts((prev) => ({
                                                                ...prev,
                                                                [row.user_id]: e.target.value,
                                                            }))
                                                        }
                                                        onBlur={() => void saveRate(row)}
                                                        onKeyDown={(e) => {
                                                            if (e.key === 'Enter') {
                                                                (e.target as HTMLInputElement).blur();
                                                            }
                                                        }}
                                                    />
                                                    {savingUserId === row.user_id && (
                                                        <Loader2 className="size-3.5 animate-spin text-muted-foreground" />
                                                    )}
                                                </div>
                                            </td>
                                            <td className="px-4 py-3 text-right font-semibold text-foreground">
                                                {formatMoney(row.total_pay)}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            </div>

            <Dialog
                open={fixTarget !== null}
                onOpenChange={(open) => !open && closeFixTimeOut()}
            >
                <DialogContent className="sm:max-w-sm">
                    <DialogHeader>
                        <DialogTitle>Record Time-Out</DialogTitle>
                        <DialogDescription>
                            {fixTarget?.full_name} forgot to time out. Pick the
                            date and the actual time they left.
                        </DialogDescription>
                    </DialogHeader>

                    <div className="space-y-4 py-2">
                        <div className="grid gap-1.5">
                            <Label htmlFor="fix-date">Date</Label>
                            {fixTarget && fixTarget.missing_time_out_dates.length > 1 ? (
                                <Select value={fixDate} onValueChange={setFixDate}>
                                    <SelectTrigger id="fix-date">
                                        <SelectValue placeholder="Select a date" />
                                    </SelectTrigger>
                                    <SelectContent>
                                        {fixTarget.missing_time_out_dates.map((d) => (
                                            <SelectItem key={d} value={d}>
                                                {d}
                                            </SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            ) : (
                                <Input
                                    id="fix-date"
                                    type="date"
                                    value={fixDate}
                                    max={today()}
                                    onChange={(e) => setFixDate(e.target.value)}
                                />
                            )}
                        </div>

                        <div className="grid gap-1.5">
                            <Label htmlFor="fix-time">Time out</Label>
                            <Input
                                id="fix-time"
                                type="time"
                                value={fixTime}
                                onChange={(e) => setFixTime(e.target.value)}
                            />
                        </div>
                    </div>

                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={closeFixTimeOut}
                            disabled={fixing}
                        >
                            Cancel
                        </Button>
                        <Button onClick={() => void saveFixTimeOut()} disabled={fixing}>
                            {fixing ? (
                                <Loader2 className="size-4 animate-spin" />
                            ) : null}
                            Save
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </>
    );
}

PosPayroll.layout = {
    breadcrumbs: [
        { title: 'Dashboard', href: dashboard() },
        { title: 'Payroll', href: '/pos/payroll' },
    ],
};
