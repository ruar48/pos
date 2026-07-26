import { Head } from '@inertiajs/react';
import {
    AlertTriangle,
    BarChart3,
    Clock,
    Download,
    HardDrive,
    Loader2,
    RefreshCw,
    Trash2,
    UserCheck,
    UserPlus,
    Users,
    type LucideIcon,
} from 'lucide-react';
import { AttendanceManualBoard } from '@/components/pos/attendance-manual-board';
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
    fetchAttendanceBoard,
    fetchAttendanceEventLog,
    fetchAttendancePunctualityReport,
    downloadAttendanceExport,
    fetchAttendancePhotoStats,
    purgeAttendancePhotos,
    fetchStaffUsers,
    saveStaffUser,
    type AttendanceEventRow,
    type AttendancePhotoStats,
    type AttendancePunctualityRow,
    type AttendanceRow,
    type AttendanceSchedule,
    type StaffUser,
} from '@/lib/staff-api';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';

type TabKey = 'attendance' | 'staff';
type AttendanceView = 'board' | 'report';

function weekRange(): { start: string; end: string } {
    const today = new Date();
    const day = today.getDay();
    const diff = (day + 6) % 7;
    const monday = new Date(today);
    monday.setDate(today.getDate() - diff);
    return { start: toIsoDate(monday), end: toIsoDate(today) };
}

const ROLES = [
    { value: 'admin', label: 'Admin' },
    { value: 'cashier', label: 'Cashier' },
    { value: 'labor', label: 'Labor (no login)' },
];

function roleLabel(role: string): string {
    const match = ROLES.find((r) => r.value === role);
    if (match) return match.label;
    return role.replace(/_/g, ' ');
}

function pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
}

function toIsoDate(date: Date): string {
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function formatClockTime(value: string): string {
    const [hourRaw, minute] = value.split(':');
    const hour = Number(hourRaw);
    if (Number.isNaN(hour)) return value;
    const suffix = hour >= 12 ? 'PM' : 'AM';
    const display = hour % 12 === 0 ? 12 : hour % 12;
    return `${display}:${minute} ${suffix}`;
}

export default function PosStaff() {
    const [tab, setTab] = useState<TabKey>('attendance');
    const [date, setDate] = useState(toIsoDate(new Date()));
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [attendance, setAttendance] = useState<AttendanceRow[]>([]);
    const [schedule, setSchedule] = useState<AttendanceSchedule | null>(null);
    const [attendanceView, setAttendanceView] = useState<AttendanceView>('board');
    const initialWeek = weekRange();
    const [reportStart, setReportStart] = useState(initialWeek.start);
    const [reportEnd, setReportEnd] = useState(initialWeek.end);
    const [reportRows, setReportRows] = useState<AttendancePunctualityRow[]>([]);
    const [eventRows, setEventRows] = useState<AttendanceEventRow[]>([]);
    const [reportSchedule, setReportSchedule] = useState<AttendanceSchedule | null>(
        null,
    );
    const [exportingAttendance, setExportingAttendance] = useState(false);
    const [users, setUsers] = useState<StaffUser[]>([]);
    const [dialogOpen, setDialogOpen] = useState(false);
    const [saving, setSaving] = useState(false);
    const [photoStats, setPhotoStats] = useState<AttendancePhotoStats | null>(
        null,
    );
    const [purgingPhotos, setPurgingPhotos] = useState(false);
    const [form, setForm] = useState({
        full_name: '',
        username: '',
        email: '',
        password: '',
        role: 'cashier',
        branch_id: '1',
    });

    const loadPhotoStats = useCallback(async () => {
        try {
            const res = await fetchAttendancePhotoStats();
            setPhotoStats(res.data ?? null);
        } catch {
            setPhotoStats(null);
        }
    }, []);

    const load = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            if (tab === 'attendance') {
                if (attendanceView === 'board') {
                    const res = await fetchAttendanceBoard(date);
                    setAttendance(res.rows ?? []);
                    setSchedule(res.schedule ?? null);
                } else {
                    const [punctuality, events] = await Promise.all([
                        fetchAttendancePunctualityReport(reportStart, reportEnd),
                        fetchAttendanceEventLog(reportStart, reportEnd),
                    ]);
                    setReportRows(punctuality.rows ?? []);
                    setReportSchedule(punctuality.schedule ?? null);
                    setEventRows(events.rows ?? []);
                }
                void loadPhotoStats();
            } else {
                const res = await fetchStaffUsers();
                setUsers(res.data ?? []);
            }
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Failed to load staff data');
        } finally {
            setLoading(false);
        }
    }, [tab, date, attendanceView, reportStart, reportEnd, loadPhotoStats]);

    async function handlePurgePhotos(all: boolean) {
        const confirmMsg = all
            ? 'Delete ALL attendance selfies from disk and clear photo links? Punch times stay.'
            : 'Delete attendance selfies older than 30 days? Punch times stay.';
        if (!window.confirm(confirmMsg)) return;

        setPurgingPhotos(true);
        try {
            const res = await purgeAttendancePhotos(
                all ? { all: true } : { older_than_days: 30 },
            );
            toast.success(
                `${res.message} Removed ${res.data?.deleted_files ?? 0} files (${res.data?.freed_mb ?? 0} MB).`,
            );
            await Promise.all([loadPhotoStats(), load()]);
        } catch (err) {
            toast.error(
                err instanceof Error ? err.message : 'Could not clear photos',
            );
        } finally {
            setPurgingPhotos(false);
        }
    }

    async function handleExportAttendance() {
        setExportingAttendance(true);
        try {
            await downloadAttendanceExport(reportStart, reportEnd);
            toast.success('Attendance exported to Excel');
        } catch (error) {
            toast.error(
                error instanceof Error ? error.message : 'Export failed',
            );
        } finally {
            setExportingAttendance(false);
        }
    }

    const isToday = date === toIsoDate(new Date());

    useEffect(() => {
        load();
    }, [load]);

    const onDutyCount = useMemo(
        () => attendance.filter((r) => r.is_clocked_in).length,
        [attendance],
    );

    const lateCount = useMemo(
        () =>
            attendance.filter(
                (r) =>
                    r.morning_session_status === 'late' ||
                    r.afternoon_session_status === 'late',
            ).length,
        [attendance],
    );

    const morningAbsentCount = useMemo(
        () =>
            attendance.filter((r) => r.morning_session_status === 'absent')
                .length,
        [attendance],
    );

    const absentTodayCount = useMemo(
        () =>
            attendance.filter((r) => r.daily_status === 'absent').length,
        [attendance],
    );

    const createStaff = async () => {
        setSaving(true);
        try {
            const payload: Parameters<typeof saveStaffUser>[0] = {
                action: 'create',
                full_name: form.full_name,
                role: form.role,
                branch_id: Number(form.branch_id),
            };

            if (form.role !== 'labor') {
                payload.username = form.username;
                payload.email = form.email;
                payload.password = form.password;
            }

            await saveStaffUser(payload);
            toast.success('Staff member created');
            setDialogOpen(false);
            setForm({
                full_name: '',
                username: '',
                email: '',
                password: '',
                role: 'cashier',
                branch_id: '1',
            });
            if (tab === 'staff') load();
        } catch (err) {
            toast.error(err instanceof Error ? err.message : 'Failed to create staff');
        } finally {
            setSaving(false);
        }
    };

    const toggleStaff = async (user: StaffUser) => {
        try {
            await saveStaffUser({ action: 'toggle', id: user.id });
            toast.success(user.status === 1 ? 'Staff deactivated' : 'Staff activated');
            load();
        } catch (err) {
            toast.error(err instanceof Error ? err.message : 'Failed to update staff');
        }
    };

    const tabs: { key: TabKey; label: string; icon: LucideIcon }[] = [
        { key: 'attendance', label: 'Attendance', icon: Clock },
        { key: 'staff', label: 'Staff', icon: Users },
    ];

    return (
        <>
            <Head title="Staff" />
            <div className="agri-page-container">
                <PageHeader
                    badge="Staff"
                    title="Staff & Attendance"
                    description="Tap IN / OUT on a staff member, then take a selfie. No face recognition. Morning only = half day."
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
                            {tab === 'staff' && (
                                <Button size="sm" onClick={() => setDialogOpen(true)}>
                                    <UserPlus className="size-4" />
                                    Add Staff
                                </Button>
                            )}
                        </>
                    }
                />

                <div className="agri-card flex flex-col gap-4 p-4 lg:flex-row lg:items-center lg:justify-between">
                    <div className="flex flex-wrap gap-2">
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
                    {tab === 'attendance' && (
                        <div className="flex flex-wrap items-center gap-2">
                            <div className="flex rounded-full bg-secondary p-1">
                                {(
                                    [
                                        { key: 'board', label: 'Daily board' },
                                        { key: 'report', label: 'Report' },
                                    ] as const
                                ).map((view) => (
                                    <button
                                        key={view.key}
                                        type="button"
                                        onClick={() => setAttendanceView(view.key)}
                                        className={cn(
                                            'rounded-full px-3 py-1 text-xs font-semibold transition-colors',
                                            attendanceView === view.key
                                                ? 'bg-primary text-primary-foreground shadow-sm'
                                                : 'text-muted-foreground hover:text-foreground',
                                        )}
                                    >
                                        {view.label}
                                    </button>
                                ))}
                            </div>
                            {attendanceView === 'board' ? (
                                <>
                                    <Label
                                        htmlFor="staff-date"
                                        className="text-xs text-muted-foreground"
                                    >
                                        Date
                                    </Label>
                                    <Input
                                        id="staff-date"
                                        type="date"
                                        value={date}
                                        max={toIsoDate(new Date())}
                                        className="h-9 w-[9.5rem]"
                                        onChange={(e) => setDate(e.target.value)}
                                    />
                                </>
                            ) : (
                                <>
                                    <Input
                                        type="date"
                                        value={reportStart}
                                        max={reportEnd}
                                        className="h-9 w-[9.5rem]"
                                        onChange={(e) =>
                                            setReportStart(e.target.value)
                                        }
                                    />
                                    <span className="text-xs text-muted-foreground">
                                        to
                                    </span>
                                    <Input
                                        type="date"
                                        value={reportEnd}
                                        min={reportStart}
                                        max={toIsoDate(new Date())}
                                        className="h-9 w-[9.5rem]"
                                        onChange={(e) => setReportEnd(e.target.value)}
                                    />
                                    <Button
                                        type="button"
                                        variant="outline"
                                        size="sm"
                                        className="h-9"
                                        disabled={exportingAttendance}
                                        onClick={() => void handleExportAttendance()}
                                    >
                                        {exportingAttendance ? (
                                            <Loader2 className="size-4 animate-spin" />
                                        ) : (
                                            <Download className="size-4" />
                                        )}
                                        Export Excel
                                    </Button>
                                </>
                            )}
                        </div>
                    )}
                </div>

                {tab === 'attendance' &&
                    attendanceView === 'board' &&
                    !loading &&
                    !error && (
                    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
                        <div className="agri-stat-card">
                            <p className="agri-stat-label">On duty now</p>
                            <p className="agri-stat-value">{onDutyCount}</p>
                        </div>
                        <div className="agri-stat-card">
                            <p className="agri-stat-label">Late today</p>
                            <p className="agri-stat-value">{lateCount}</p>
                        </div>
                        <div className="agri-stat-card">
                            <p className="agri-stat-label">Morning absent</p>
                            <p className="agri-stat-value">{morningAbsentCount}</p>
                        </div>
                        <div className="agri-stat-card">
                            <p className="agri-stat-label">Absent today</p>
                            <p className="agri-stat-value">{absentTodayCount}</p>
                        </div>
                        <div className="agri-stat-card">
                            <p className="agri-stat-label">Start + grace</p>
                            <p className="agri-stat-value text-lg">
                                {schedule
                                    ? `${formatClockTime(schedule.start_time)} · ${schedule.grace_minutes}m`
                                    : '—'}
                            </p>
                            {schedule && (
                                <p className="mt-1 text-xs text-muted-foreground">
                                    Absent after{' '}
                                    {formatClockTime(
                                        schedule.morning_absent_after_time,
                                    )}
                                </p>
                            )}
                        </div>
                    </div>
                )}

                {tab === 'attendance' && !loading && !error && (
                    <div className="agri-card flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
                        <div className="flex items-start gap-3">
                            <div className="rounded-full bg-secondary p-2">
                                <HardDrive className="size-4 text-primary" />
                            </div>
                            <div>
                                <p className="font-semibold text-foreground">
                                    Attendance photo storage
                                </p>
                                <p className="text-xs text-muted-foreground">
                                    {photoStats
                                        ? `${photoStats.file_count} files · ${photoStats.total_mb} MB in ${photoStats.directory}`
                                        : 'Loading storage usage…'}
                                    . Clearing photos frees disk space; punch
                                    times are kept.
                                </p>
                            </div>
                        </div>
                        <div className="flex flex-wrap gap-2">
                            <Button
                                type="button"
                                variant="outline"
                                size="sm"
                                disabled={purgingPhotos}
                                onClick={() => void handlePurgePhotos(false)}
                            >
                                {purgingPhotos ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <Trash2 className="size-4" />
                                )}
                                Clear older than 30 days
                            </Button>
                            <Button
                                type="button"
                                variant="destructive"
                                size="sm"
                                disabled={purgingPhotos}
                                onClick={() => void handlePurgePhotos(true)}
                            >
                                {purgingPhotos ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <Trash2 className="size-4" />
                                )}
                                Clear all photos
                            </Button>
                        </div>
                    </div>
                )}

                {loading ? (
                    <div className="agri-card flex items-center justify-center gap-2 py-20 text-muted-foreground">
                        <Loader2 className="size-5 animate-spin" />
                        Loading...
                    </div>
                ) : error ? (
                    <div className="agri-card flex flex-col items-center justify-center gap-3 py-20 text-center">
                        <AlertTriangle className="size-8 text-destructive" />
                        <p className="text-sm font-medium text-destructive">{error}</p>
                        <Button variant="outline" size="sm" onClick={load}>
                            Try again
                        </Button>
                    </div>
                ) : tab === 'attendance' && attendanceView === 'board' ? (
                    attendance.length === 0 ? (
                        <div className="agri-card flex flex-col items-center justify-center gap-3 py-20 text-center">
                            <UserCheck className="size-8 text-muted-foreground" />
                            <p className="text-sm font-medium">No staff found</p>
                            <p className="text-xs text-muted-foreground">
                                Add staff accounts, then clock them in from this page
                                or the tablet.
                            </p>
                        </div>
                    ) : (
                        <AttendanceManualBoard
                            attendance={attendance}
                            clockEnabled={isToday}
                            onClocked={load}
                        />
                    )
                ) : tab === 'attendance' && attendanceView === 'report' ? (
                    loading ? (
                        <div className="agri-card flex items-center justify-center gap-2 py-20 text-muted-foreground">
                            <Loader2 className="size-5 animate-spin" />
                            Loading report...
                        </div>
                    ) : error ? (
                        <div className="agri-card flex flex-col items-center justify-center gap-3 py-20 text-center">
                            <AlertTriangle className="size-8 text-destructive" />
                            <p className="text-sm font-medium text-destructive">
                                {error}
                            </p>
                            <Button variant="outline" size="sm" onClick={load}>
                                Try again
                            </Button>
                        </div>
                    ) : (
                        <div className="space-y-4">
                            {reportSchedule && (
                                <div className="agri-card p-4 text-sm text-muted-foreground">
                                    Schedule: start{' '}
                                    <strong>
                                        {formatClockTime(
                                            reportSchedule.start_time,
                                        )}
                                    </strong>
                                    , grace{' '}
                                    <strong>
                                        {reportSchedule.grace_minutes} min
                                    </strong>
                                    , late after{' '}
                                    <strong>
                                        {formatClockTime(
                                            reportSchedule.late_after_time,
                                        )}
                                    </strong>
                                    .
                                </div>
                            )}

                            <div className="agri-card overflow-hidden">
                                <div className="flex items-center gap-2 border-b border-border/60 bg-secondary/30 px-4 py-3">
                                    <BarChart3 className="size-4 text-primary" />
                                    <h3 className="font-semibold">
                                        Punctuality ranking
                                    </h3>
                                </div>
                                <div className="overflow-x-auto">
                                    <table className="w-full min-w-[48rem] text-sm">
                                        <thead>
                                            <tr className="border-b border-border/60 bg-secondary/20 text-left">
                                                <th className="px-4 py-3 font-semibold text-muted-foreground">
                                                    Rank
                                                </th>
                                                <th className="px-3 py-3 font-semibold text-muted-foreground">
                                                    Staff
                                                </th>
                                                <th className="px-3 py-3 text-center font-semibold text-muted-foreground">
                                                    Present
                                                </th>
                                                <th className="px-3 py-3 text-center font-semibold text-muted-foreground">
                                                    Half-day
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
                                            {reportRows.length === 0 ? (
                                                <tr>
                                                    <td
                                                        colSpan={6}
                                                        className="px-4 py-10 text-center text-muted-foreground"
                                                    >
                                                        No attendance records in
                                                        this range.
                                                    </td>
                                                </tr>
                                            ) : (
                                                reportRows.map((row) => (
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
                                                        <td className="px-3 py-3 text-center tabular-nums text-emerald-700">
                                                            {row.days_present}
                                                        </td>
                                                        <td className="px-3 py-3 text-center tabular-nums text-amber-700">
                                                            {row.days_half_day}
                                                        </td>
                                                        <td className="px-3 py-3 text-center tabular-nums text-destructive">
                                                            {row.days_late}
                                                        </td>
                                                        <td className="px-3 py-3 text-center tabular-nums text-muted-foreground">
                                                            {row.days_absent}
                                                        </td>
                                                    </tr>
                                                ))
                                            )}
                                        </tbody>
                                    </table>
                                </div>
                            </div>

                            <div className="agri-card overflow-hidden">
                                <div className="flex items-center gap-2 border-b border-border/60 bg-secondary/30 px-4 py-3">
                                    <Clock className="size-4 text-primary" />
                                    <h3 className="font-semibold">
                                        Clock in / out log
                                    </h3>
                                </div>
                                <div className="overflow-x-auto">
                                    <table className="w-full min-w-[48rem] text-sm">
                                        <thead>
                                            <tr className="border-b border-border/60 bg-secondary/20 text-left">
                                                <th className="px-4 py-3 font-semibold text-muted-foreground">
                                                    Date & time
                                                </th>
                                                <th className="px-3 py-3 font-semibold text-muted-foreground">
                                                    Staff
                                                </th>
                                                <th className="px-3 py-3 font-semibold text-muted-foreground">
                                                    Event
                                                </th>
                                                <th className="px-3 py-3 font-semibold text-muted-foreground">
                                                    Source
                                                </th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {eventRows.length === 0 ? (
                                                <tr>
                                                    <td
                                                        colSpan={4}
                                                        className="px-4 py-10 text-center text-muted-foreground"
                                                    >
                                                        No clock events in this
                                                        range.
                                                    </td>
                                                </tr>
                                            ) : (
                                                eventRows.map((row) => (
                                                    <tr
                                                        key={row.id}
                                                        className="border-b border-border/40 last:border-0"
                                                    >
                                                        <td className="px-4 py-3 whitespace-nowrap text-muted-foreground">
                                                            {new Date(
                                                                row.recorded_at,
                                                            ).toLocaleString()}
                                                        </td>
                                                        <td className="px-3 py-3 font-medium">
                                                            {row.full_name}
                                                        </td>
                                                        <td className="px-3 py-3">
                                                            <span
                                                                className={cn(
                                                                    'rounded-full px-2 py-0.5 text-xs font-semibold capitalize',
                                                                    row.event_type ===
                                                                        'clock_in'
                                                                        ? 'bg-primary/10 text-primary'
                                                                        : 'bg-teal-500/10 text-teal-700',
                                                                )}
                                                            >
                                                                {row.event_type.replace(
                                                                    '_',
                                                                    ' ',
                                                                )}
                                                            </span>
                                                        </td>
                                                        <td className="px-3 py-3 text-muted-foreground">
                                                            {row.device_info ||
                                                                '—'}
                                                        </td>
                                                    </tr>
                                                ))
                                            )}
                                        </tbody>
                                    </table>
                                </div>
                            </div>
                        </div>
                    )
                ) : tab === 'attendance' ? null : (
                    <div className="agri-card overflow-hidden">
                        <div className="overflow-x-auto">
                            <table className="w-full min-w-[48rem] text-sm">
                                <thead>
                                    <tr className="border-b border-border/60 bg-secondary/40 text-left">
                                        <th className="px-4 py-3 font-semibold text-muted-foreground">
                                            Name
                                        </th>
                                        <th className="px-3 py-3 font-semibold text-muted-foreground">
                                            Username
                                        </th>
                                        <th className="px-3 py-3 font-semibold text-muted-foreground">
                                            Role
                                        </th>
                                        <th className="px-3 py-3 font-semibold text-muted-foreground">
                                            Status
                                        </th>
                                        <th className="px-4 py-3 text-right font-semibold text-muted-foreground">
                                            Actions
                                        </th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {users.map((user) => (
                                        <tr
                                            key={user.id}
                                            className="border-b border-border/40 last:border-0"
                                        >
                                            <td className="px-4 py-3 font-medium">{user.full_name}</td>
                                            <td className="px-3 py-3 text-muted-foreground">
                                                {user.username}
                                            </td>
                                            <td className="px-3 py-3">
                                                {roleLabel(user.role)}
                                            </td>
                                            <td className="px-3 py-3">
                                                <span
                                                    className={cn(
                                                        'rounded-full px-2 py-0.5 text-xs font-semibold',
                                                        user.status === 1
                                                            ? 'bg-primary/10 text-primary'
                                                            : 'bg-destructive/10 text-destructive',
                                                    )}
                                                >
                                                    {user.status === 1 ? 'Active' : 'Inactive'}
                                                </span>
                                            </td>
                                            <td className="px-4 py-3 text-right">
                                                <Button
                                                    variant="outline"
                                                    size="sm"
                                                    onClick={() => toggleStaff(user)}
                                                >
                                                    {user.status === 1 ? 'Deactivate' : 'Activate'}
                                                </Button>
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </div>
                )}
            </div>

            <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Add staff member</DialogTitle>
                    </DialogHeader>
                    <div className="grid gap-3 py-2">
                        <div>
                            <Label>Full name</Label>
                            <Input
                                value={form.full_name}
                                onChange={(e) =>
                                    setForm((f) => ({ ...f, full_name: e.target.value }))
                                }
                            />
                        </div>
                        {form.role !== 'labor' && (
                            <>
                                <div>
                                    <Label>Username</Label>
                                    <Input
                                        value={form.username}
                                        onChange={(e) =>
                                            setForm((f) => ({
                                                ...f,
                                                username: e.target.value,
                                            }))
                                        }
                                    />
                                </div>
                                <div>
                                    <Label>Email</Label>
                                    <Input
                                        type="email"
                                        value={form.email}
                                        onChange={(e) =>
                                            setForm((f) => ({
                                                ...f,
                                                email: e.target.value,
                                            }))
                                        }
                                    />
                                </div>
                                <div>
                                    <Label>Password</Label>
                                    <Input
                                        type="password"
                                        value={form.password}
                                        onChange={(e) =>
                                            setForm((f) => ({
                                                ...f,
                                                password: e.target.value,
                                            }))
                                        }
                                    />
                                </div>
                            </>
                        )}
                        {form.role === 'labor' && (
                            <p className="rounded-lg border border-border/60 bg-secondary/10 px-3 py-2 text-sm text-muted-foreground">
                                Labor staff are added for attendance
                                clock-in only. They do not get a username or
                                password.
                            </p>
                        )}
                        <div>
                            <Label>Role</Label>
                            <Select
                                value={form.role}
                                onValueChange={(v) =>
                                    setForm((f) => ({ ...f, role: v }))
                                }
                            >
                                <SelectTrigger>
                                    <SelectValue />
                                </SelectTrigger>
                                <SelectContent>
                                    {ROLES.map((r) => (
                                        <SelectItem key={r.value} value={r.value}>
                                            {r.label}
                                        </SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                        </div>
                        <div className="rounded-xl border border-border/60 bg-secondary/20 p-3">
                            <p className="text-sm font-semibold text-foreground">
                                Attendance buttons (Staff list)
                            </p>
                            <p className="mt-1 text-xs text-muted-foreground">
                                After saving, open Attendance and tap these circles:
                            </p>
                            <div className="mt-3 flex items-center justify-evenly gap-2">
                                <div className="flex flex-col items-center gap-1">
                                    <span className="flex size-14 items-center justify-center rounded-full bg-emerald-600 text-sm font-extrabold text-white">
                                        IN
                                    </span>
                                    <span className="text-[11px] font-bold text-muted-foreground">
                                        Time In
                                    </span>
                                </div>
                                <div className="flex flex-col items-center gap-1">
                                    <span className="flex size-16 items-center justify-center rounded-full bg-sky-400 px-1 text-center text-[10px] font-extrabold leading-tight text-white">
                                        START
                                        <br />
                                        BREAK
                                    </span>
                                    <span className="text-[11px] font-bold text-muted-foreground">
                                        Break
                                    </span>
                                </div>
                                <div className="flex flex-col items-center gap-1">
                                    <span className="flex size-14 items-center justify-center rounded-full bg-orange-500 text-sm font-extrabold text-white">
                                        OUT
                                    </span>
                                    <span className="text-[11px] font-bold text-muted-foreground">
                                        Time Out
                                    </span>
                                </div>
                            </div>
                        </div>
                    </div>
                    <DialogFooter>
                        <Button variant="outline" onClick={() => setDialogOpen(false)}>
                            Cancel
                        </Button>
                        <Button onClick={createStaff} disabled={saving}>
                            {saving && <Loader2 className="size-4 animate-spin" />}
                            Save
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </>
    );
}

PosStaff.layout = {
    breadcrumbs: [
        { title: 'Dashboard', href: dashboard() },
        { title: 'Staff', href: '/pos/staff' },
    ],
};
