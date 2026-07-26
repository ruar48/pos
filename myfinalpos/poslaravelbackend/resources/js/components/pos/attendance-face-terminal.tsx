import {
    Camera,
    CheckCircle2,
    Clock,
    Loader2,
    ScanFace,
    UserRound,
    XCircle,
} from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import {
    captureVerifyDescriptors,
    ensureFaceModels,
    MIN_VERIFY_CONFIDENCE,
    probeFaceInVideo,
} from '@/lib/face-id-engine';
import { verifyFaceProfile } from '@/lib/face-profile-api';
import {
    clockStaffAttendance,
    type AttendanceRow,
    type AttendanceSchedule,
} from '@/lib/staff-api';
import { cn } from '@/lib/utils';

function formatClockTime(value: string): string {
    const [hourRaw, minute] = value.split(':');
    const hour = Number(hourRaw);
    if (Number.isNaN(hour)) return value;
    const suffix = hour >= 12 ? 'PM' : 'AM';
    const display = hour % 12 === 0 ? 12 : hour % 12;
    return `${display}:${minute} ${suffix}`;
}

function punchLabel(
    row: AttendanceRow,
    action: 'clock_in' | 'clock_out',
): string {
    const count = row.punch_count ?? 0;
    if (action === 'clock_in') {
        if (count === 0) return 'Morning clock in';
        if (count === 2) return 'Afternoon clock in';
        return 'Clock in';
    }
    if (count === 1) return 'Lunch clock out';
    if (count === 3) return 'End of day clock out';
    return 'Clock out';
}

type TerminalPhase = 'idle' | 'scanning' | 'success' | 'failed';

type ScanResult = {
    title: string;
    detail: string;
};

type LiveClockParts = {
    time: string;
    weekday: string;
    date: string;
    month: string;
    year: string;
};

function useLiveClock(): LiveClockParts {
    const format = useCallback((): LiveClockParts => {
        const now = new Date();
        return {
            time: now.toLocaleTimeString(undefined, {
                hour: 'numeric',
                minute: '2-digit',
                second: '2-digit',
            }),
            weekday: now.toLocaleDateString(undefined, { weekday: 'long' }),
            date: now.toLocaleDateString(undefined, { day: 'numeric' }),
            month: now.toLocaleDateString(undefined, { month: 'long' }),
            year: now.toLocaleDateString(undefined, { year: 'numeric' }),
        };
    }, []);

    const [clock, setClock] = useState<LiveClockParts>(format);

    useEffect(() => {
        const tick = () => setClock(format());
        tick();
        const interval = window.setInterval(tick, 1000);
        return () => window.clearInterval(interval);
    }, [format]);

    return clock;
}

function AttendanceLiveClock() {
    const clock = useLiveClock();

    return (
        <div className="mb-4 rounded-2xl border border-border/60 bg-gradient-to-br from-primary/5 via-card to-secondary/40 p-4 text-center">
            <div className="mb-2 flex items-center justify-center gap-1.5 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                <Clock className="size-3" />
                Attendance clock
            </div>
            <p className="text-3xl font-bold tabular-nums tracking-tight text-foreground">
                {clock.time}
            </p>
            <p className="mt-1 text-sm font-medium text-foreground">
                {clock.weekday}
            </p>
            <div className="mt-2 flex flex-wrap items-center justify-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                <span>
                    Date{' '}
                    <strong className="text-foreground">{clock.date}</strong>
                </span>
                <span className="hidden sm:inline text-border">|</span>
                <span>
                    Month{' '}
                    <strong className="text-foreground">{clock.month}</strong>
                </span>
                <span className="hidden sm:inline text-border">|</span>
                <span>
                    Year{' '}
                    <strong className="text-foreground">{clock.year}</strong>
                </span>
            </div>
        </div>
    );
}

export function AttendanceFaceTerminal({
    attendance,
    schedule,
    onClocked,
    clockEnabled = true,
}: {
    attendance: AttendanceRow[];
    schedule: AttendanceSchedule | null;
    onClocked: () => Promise<void> | void;
    /** When false (e.g. viewing a past date), camera stays on but clocking is disabled. */
    clockEnabled?: boolean;
}) {
    const videoRef = useRef<HTMLVideoElement>(null);
    const streamRef = useRef<MediaStream | null>(null);
    const phaseRef = useRef<TerminalPhase>('idle');

    const [cameraOn, setCameraOn] = useState(false);
    const [cameraError, setCameraError] = useState<string | null>(null);
    const [modelsReady, setModelsReady] = useState(false);
    const [modelsError, setModelsError] = useState<string | null>(null);
    const [phase, setPhase] = useState<TerminalPhase>('idle');
    const [faceInFrame, setFaceInFrame] = useState(false);
    const [scanProgress, setScanProgress] = useState<string | null>(null);
    const [result, setResult] = useState<ScanResult | null>(null);

    const attendanceByUser = useRef(new Map<number, AttendanceRow>());
    useEffect(() => {
        attendanceByUser.current = new Map(
            attendance.map((row) => [row.user_id, row]),
        );
    }, [attendance]);

    const resetPhase = useCallback(() => {
        setPhase('idle');
        phaseRef.current = 'idle';
        setScanProgress(null);
        setResult(null);
    }, []);

    const stopCamera = useCallback(() => {
        streamRef.current?.getTracks().forEach((track) => track.stop());
        streamRef.current = null;
        if (videoRef.current) {
            videoRef.current.srcObject = null;
        }
        setCameraOn(false);
    }, []);

    const startCamera = useCallback(async () => {
        setCameraError(null);

        if (!navigator.mediaDevices?.getUserMedia) {
            setCameraError('Camera is not available in this browser.');
            setCameraOn(false);
            return;
        }

        try {
            const stream = await navigator.mediaDevices.getUserMedia({
                video: {
                    facingMode: 'user',
                    width: { ideal: 640 },
                    height: { ideal: 480 },
                },
                audio: false,
            });
            streamRef.current = stream;
            const video = videoRef.current;
            if (video) {
                video.srcObject = stream;
                await video.play();
            }
            setCameraOn(true);
        } catch (error) {
            const message =
                error instanceof Error ? error.message : 'Camera access failed';
            setCameraError(
                message.includes('Permission')
                    ? 'Allow camera access for this site, then try again.'
                    : 'Camera unavailable. Check permissions and try again.',
            );
            setCameraOn(false);
        }
    }, []);

    useEffect(() => {
        ensureFaceModels()
            .then(() => setModelsReady(true))
            .catch(() => {
                setModelsError(
                    'Could not load face models. Check your internet connection.',
                );
            });
    }, []);

    useEffect(() => {
        void startCamera();
        return () => stopCamera();
    }, [startCamera, stopCamera]);

    useEffect(() => {
        if (!cameraOn || !modelsReady || phase === 'scanning') {
            setFaceInFrame(false);
            return;
        }

        let cancelled = false;
        const tick = async () => {
            const video = videoRef.current;
            if (!video || cancelled) return;
            try {
                const detected = await probeFaceInVideo(video);
                if (!cancelled) setFaceInFrame(detected);
            } catch {
                if (!cancelled) setFaceInFrame(false);
            }
        };

        void tick();
        const interval = window.setInterval(() => void tick(), 700);
        return () => {
            cancelled = true;
            window.clearInterval(interval);
        };
    }, [cameraOn, modelsReady, phase]);

    const runScan = useCallback(async () => {
        if (!clockEnabled) {
            setResult({
                title: 'Viewing past date',
                detail: 'Switch to today’s date to clock staff in or out.',
            });
            setPhase('failed');
            phaseRef.current = 'failed';
            return;
        }

        if (!modelsReady) {
            toast.error(modelsError ?? 'Face models are still loading');
            return;
        }

        if (!cameraOn || !videoRef.current) {
            toast.error('Enable the camera first');
            return;
        }

        if (phaseRef.current === 'scanning') {
            return;
        }

        setPhase('scanning');
        phaseRef.current = 'scanning';
        setResult(null);
        setScanProgress('Verifying face…');

        try {
            const probes = await captureVerifyDescriptors(
                videoRef.current,
                (message) => setScanProgress(message),
            );
            setScanProgress(null);

            if (probes.length === 0) {
                setResult({
                    title: 'Face not detected',
                    detail: 'Center your face in the oval and hold steady.',
                });
                setPhase('failed');
                phaseRef.current = 'failed';
                return;
            }

            let bestMatch: Awaited<ReturnType<typeof verifyFaceProfile>> | null =
                null;

            for (const probe of probes) {
                const attempt = await verifyFaceProfile(probe);
                if (!attempt.matched) continue;

                if (
                    (attempt.confidence ?? 0) >= MIN_VERIFY_CONFIDENCE
                ) {
                    bestMatch = attempt;
                    break;
                }

                if (
                    !bestMatch ||
                    (attempt.confidence ?? 0) > (bestMatch.confidence ?? 0)
                ) {
                    bestMatch = attempt;
                }
            }

            if (
                !bestMatch?.matched ||
                !bestMatch.user_id ||
                (bestMatch.confidence ?? 0) < MIN_VERIFY_CONFIDENCE
            ) {
                setResult({
                    title: 'No match',
                    detail:
                        'Face not recognized. Enroll this staff member under Face ID first.',
                });
                setPhase('failed');
                phaseRef.current = 'failed';
                return;
            }

            const row = attendanceByUser.current.get(bestMatch.user_id);
            if (!row) {
                setResult({
                    title: 'Staff not found',
                    detail: 'Matched user is not on today’s attendance board.',
                });
                setPhase('failed');
                phaseRef.current = 'failed';
                return;
            }

            if (row.day_complete) {
                const absentToday = row.daily_status === 'absent';
                setResult({
                    title: absentToday ? 'Absent' : 'Day complete',
                    detail: absentToday
                        ? `${bestMatch.full_name} is absent for today.`
                        : `${bestMatch.full_name} is done for today. Come back tomorrow.`,
                });
                setPhase('failed');
                phaseRef.current = 'failed';
                return;
            }

            const action = row.next_action;
            if (!action) {
                const absentToday =
                    row.daily_status === 'absent' ||
                    row.morning_session_status === 'absent' ||
                    row.afternoon_session_status === 'absent';
                setResult({
                    title: absentToday ? 'Absent' : 'Not yet',
                    detail: absentToday
                        ? `${bestMatch.full_name} is absent for today.`
                        : (row.next_action_note ??
                          `${bestMatch.full_name} cannot punch again until the next scheduled time.`),
                });
                setPhase('failed');
                phaseRef.current = 'failed';
                return;
            }

            const clocked = await clockStaffAttendance({
                action,
                user_id: row.user_id,
                branch_id: row.branch_id ?? 1,
                face_verified: true,
            });

            const punctuality = clocked.data?.status?.punctuality_status;
            const lateNote =
                action === 'clock_in' && clocked.data?.status?.is_morning_absent
                    ? ' · Morning absent'
                    : action === 'clock_in' && clocked.data?.status?.is_late
                      ? ` · Late (${clocked.data.status.minutes_late}m)`
                      : action === 'clock_in' && punctuality
                        ? ` · ${punctuality.replace(/_/g, ' ')}`
                        : '';

            const title = `${punchLabel(row, action)}: ${bestMatch.full_name}`;

            setResult({
                title,
                detail: `${bestMatch.confidence}% match${lateNote}`,
            });
            setPhase('success');
            phaseRef.current = 'success';
            toast.success(title);

            await onClocked();

            window.setTimeout(() => {
                resetPhase();
            }, 3200);
        } catch (error) {
            const message =
                error instanceof Error ? error.message : 'Face scan failed';
            setResult({
                title: 'Clock failed',
                detail: message,
            });
            setPhase('failed');
            phaseRef.current = 'failed';
            toast.error(message);
        } finally {
            setScanProgress(null);
        }
    }, [cameraOn, clockEnabled, modelsError, modelsReady, onClocked, resetPhase]);

    return (
        <div className="agri-card overflow-hidden p-4 xl:sticky xl:top-4">
            <AttendanceLiveClock />

            <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                <div>
                    <h3 className="font-semibold text-foreground">
                        Live scanner
                    </h3>
                    <p className="text-xs text-muted-foreground">
                        Face the camera, then tap Scan now to clock in or out.
                    </p>
                </div>
                <span
                    className={cn(
                        'inline-flex shrink-0 items-center rounded-full px-2.5 py-0.5 text-[10px] font-semibold',
                        modelsReady
                            ? 'bg-emerald-500/15 text-emerald-700'
                            : 'bg-amber-500/15 text-amber-700',
                    )}
                >
                    {modelsReady ? 'Ready to scan' : 'Loading models…'}
                </span>
            </div>

            {!clockEnabled && (
                <p className="mb-3 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-[11px] text-amber-800">
                    Viewing a past date — scanner is live, but clock in/out only
                    works for today.
                </p>
            )}

            {schedule && (
                <p className="mb-3 rounded-lg bg-secondary/60 px-3 py-2 text-[11px] text-muted-foreground">
                    Morning {formatClockTime(schedule.morning_accept_start)}–
                    {formatClockTime(schedule.morning_cutoff)} (official{' '}
                    {formatClockTime(schedule.morning_official_start)}, on time
                    until {formatClockTime(schedule.morning_grace_end)}, late{' '}
                    {formatClockTime(schedule.morning_late_start)}+). Break out{' '}
                    {formatClockTime(schedule.break_out_start)}–
                    {formatClockTime(schedule.break_out_end)}. Afternoon{' '}
                    {formatClockTime(schedule.afternoon_accept_start)}–
                    {formatClockTime(schedule.afternoon_cutoff)} (on time until{' '}
                    {formatClockTime(schedule.afternoon_on_time_end)}). Time-out
                    from {formatClockTime(schedule.timeout_start)}.
                </p>
            )}

            <div className="relative mx-auto aspect-[4/3] w-full overflow-hidden rounded-2xl border border-border/60 bg-secondary/30">
                <video
                    ref={videoRef}
                    className={cn(
                        'size-full -scale-x-100 object-cover',
                        !cameraOn && 'opacity-0',
                    )}
                    playsInline
                    muted
                />

                {!cameraOn && (
                    <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-secondary/30 p-4 text-center text-muted-foreground">
                        <UserRound className="size-12 opacity-40" />
                        <p className="max-w-[14rem] text-xs">
                            {cameraError ?? 'Starting camera…'}
                        </p>
                        <Button
                            variant="outline"
                            size="sm"
                            onClick={() => void startCamera()}
                        >
                            <Camera className="size-4" />
                            Enable camera
                        </Button>
                    </div>
                )}

                <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
                    <div
                        className={cn(
                            'relative h-[78%] w-[44%] rounded-[50%] border-2 transition-colors',
                            phase === 'scanning'
                                ? 'border-primary shadow-[0_0_24px_rgba(var(--primary),0.35)]'
                                : phase === 'success'
                                  ? 'border-emerald-500'
                                  : phase === 'failed'
                                    ? 'border-destructive'
                                    : faceInFrame
                                      ? 'border-emerald-400 shadow-[0_0_18px_rgba(52,211,153,0.45)]'
                                      : 'border-white/70',
                        )}
                    >
                        {phase === 'scanning' && (
                            <div className="absolute inset-x-3 top-0 h-0.5 animate-[face-scan_1.6s_ease-in-out_infinite] rounded-full bg-primary/80 shadow-[0_0_12px_rgba(var(--primary),0.6)]" />
                        )}
                    </div>
                </div>

                {phase === 'scanning' && (
                    <div className="absolute inset-x-3 top-3 rounded-xl bg-black/75 px-3 py-2 text-center text-white shadow-lg backdrop-blur-sm">
                        <p className="text-xs font-semibold">
                            {scanProgress ?? 'Scanning…'}
                        </p>
                    </div>
                )}

                {phase === 'success' && result && (
                    <div className="absolute inset-x-3 bottom-3 rounded-xl bg-emerald-600/90 px-3 py-2 text-white shadow-lg backdrop-blur-sm">
                        <div className="flex items-center gap-2">
                            <CheckCircle2 className="size-4 shrink-0" />
                            <div>
                                <p className="text-xs font-semibold">
                                    {result.title}
                                </p>
                                <p className="text-[10px] text-emerald-100">
                                    {result.detail}
                                </p>
                            </div>
                        </div>
                    </div>
                )}

                {phase === 'failed' && result && (
                    <div className="absolute inset-x-3 bottom-3 rounded-xl bg-destructive/90 px-3 py-2 text-white shadow-lg">
                        <div className="flex items-center gap-2">
                            <XCircle className="size-4 shrink-0" />
                            <div>
                                <p className="text-xs font-semibold">
                                    {result.title}
                                </p>
                                <p className="text-[10px] text-red-100">
                                    {result.detail}
                                </p>
                            </div>
                        </div>
                    </div>
                )}
            </div>

            {cameraOn && phase === 'idle' && (
                <p
                    className={cn(
                        'mt-3 text-center text-xs font-medium',
                        faceInFrame ? 'text-emerald-700' : 'text-muted-foreground',
                    )}
                >
                    {faceInFrame
                        ? 'Face detected — tap Scan now when ready'
                        : 'Face the camera inside the oval'}
                </p>
            )}

            <div className="mt-3 flex gap-2">
                <Button
                    className="flex-1"
                    size="sm"
                    disabled={
                        phase === 'scanning' ||
                        !modelsReady ||
                        !cameraOn ||
                        !clockEnabled
                    }
                    onClick={() => void runScan()}
                >
                    {phase === 'scanning' ? (
                        <>
                            <Loader2 className="size-4 animate-spin" />
                            Scanning…
                        </>
                    ) : (
                        <>
                            <ScanFace className="size-4" />
                            Scan now
                        </>
                    )}
                </Button>
                {phase !== 'idle' && phase !== 'scanning' && (
                    <Button variant="outline" size="sm" onClick={resetPhase}>
                        Reset
                    </Button>
                )}
            </div>
        </div>
    );
}
