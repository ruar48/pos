import { useCallback, useRef, useState, type ReactNode } from 'react';
import { Camera, Loader2, LogIn, LogOut, RefreshCw, X } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import {
    Dialog,
    DialogContent,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { cn } from '@/lib/utils';
import {
    clockStaffAttendance,
    type AttendanceRow,
} from '@/lib/staff-api';

function punchButtonLabel(row: AttendanceRow): string {
    if (row.day_complete) return 'DONE';
    return row.is_clocked_in ? 'OUT' : 'IN';
}

function canPunch(row: AttendanceRow): boolean {
    return !row.day_complete;
}

function punchAction(row: AttendanceRow): 'clock_in' | 'clock_out' | null {
    if (row.day_complete) return null;
    return row.is_clocked_in ? 'clock_out' : 'clock_in';
}

function resolvePhotoUrl(url: string | null | undefined): string | null {
    if (!url) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return url.startsWith('/') ? url : `/${url}`;
}

function selfieInUrl(row: AttendanceRow): string | null {
    return resolvePhotoUrl(row.morning_in_photo_url);
}

function selfieOutUrl(row: AttendanceRow): string | null {
    return resolvePhotoUrl(row.day_out_photo_url);
}

function selfieInTime(row: AttendanceRow): string {
    return row.morning_in_display || '—';
}

function selfieOutTime(row: AttendanceRow): string {
    return row.day_out_display || '—';
}

function actionClass(label: string): string {
    switch (label) {
        case 'OUT':
            return 'bg-orange-500 hover:bg-orange-600 text-white';
        case 'DONE':
            return 'bg-muted text-muted-foreground';
        default:
            return 'bg-emerald-600 hover:bg-emerald-700 text-white';
    }
}

function actionCaption(label: string): string {
    switch (label) {
        case 'OUT':
            return 'Time Out';
        case 'DONE':
            return 'Done';
        default:
            return 'Time In';
    }
}

type Props = {
    attendance: AttendanceRow[];
    clockEnabled: boolean;
    onClocked: () => void | Promise<void>;
};

export function AttendanceManualBoard({
    attendance,
    clockEnabled,
    onClocked,
}: Props) {
    const [punchingUserId, setPunchingUserId] = useState<number | null>(null);
    const [target, setTarget] = useState<AttendanceRow | null>(null);
    const [preview, setPreview] = useState<string | null>(null);
    const [mime, setMime] = useState('image/jpeg');
    const [capturing, setCapturing] = useState(false);
    const videoRef = useRef<HTMLVideoElement | null>(null);
    const streamRef = useRef<MediaStream | null>(null);
    const fileInputRef = useRef<HTMLInputElement | null>(null);

    const stopCamera = useCallback(() => {
        streamRef.current?.getTracks().forEach((track) => track.stop());
        streamRef.current = null;
        if (videoRef.current) {
            videoRef.current.srcObject = null;
        }
    }, []);

    const closeDialog = useCallback(() => {
        stopCamera();
        setTarget(null);
        setPreview(null);
        setCapturing(false);
    }, [stopCamera]);

    const startCamera = useCallback(async () => {
        setCapturing(true);
        setPreview(null);
        try {
            const stream = await navigator.mediaDevices.getUserMedia({
                video: { facingMode: 'user' },
                audio: false,
            });
            streamRef.current = stream;
            if (videoRef.current) {
                videoRef.current.srcObject = stream;
                await videoRef.current.play();
            }
        } catch {
            toast.error('Camera unavailable — choose a photo instead.');
            fileInputRef.current?.click();
        } finally {
            setCapturing(false);
        }
    }, []);

    const openPunch = async (row: AttendanceRow) => {
        if (!clockEnabled) {
            toast.error('Switch to today’s date to punch attendance.');
            return;
        }
        if (!canPunch(row)) {
            toast.error(`${row.full_name} is done for today.`);
            return;
        }
        setTarget(row);
        setPreview(null);
        await startCamera();
    };

    const snapPhoto = () => {
        const video = videoRef.current;
        if (!video) return;
        const canvas = document.createElement('canvas');
        canvas.width = video.videoWidth || 640;
        canvas.height = video.videoHeight || 480;
        const ctx = canvas.getContext('2d');
        if (!ctx) return;
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        const dataUrl = canvas.toDataURL('image/jpeg', 0.82);
        setMime('image/jpeg');
        setPreview(dataUrl);
        stopCamera();
    };

    const onFilePicked = (file: File | null) => {
        if (!file) return;
        const reader = new FileReader();
        reader.onload = () => {
            const result =
                typeof reader.result === 'string' ? reader.result : null;
            if (!result) return;
            setMime(file.type || 'image/jpeg');
            setPreview(result);
            stopCamera();
        };
        reader.readAsDataURL(file);
    };

    const confirmPunch = async () => {
        if (!target || !preview) return;
        const action = punchAction(target);
        if (action !== 'clock_in' && action !== 'clock_out') return;

        const base64 = preview.includes(',')
            ? preview.slice(preview.indexOf(',') + 1)
            : preview;

        setPunchingUserId(target.user_id);
        try {
            await clockStaffAttendance({
                action,
                user_id: target.user_id,
                branch_id: target.branch_id ?? undefined,
                photo_base64: base64,
                photo_mime: mime,
            });
            toast.success(`${punchButtonLabel(target)} · ${target.full_name}`);
            closeDialog();
            await onClocked();
        } catch (err) {
            toast.error(
                err instanceof Error ? err.message : 'Attendance punch failed',
            );
        } finally {
            setPunchingUserId(null);
        }
    };

    return (
        <>
            <div className="agri-card overflow-hidden p-0">
                <div className="border-b border-border/60 px-4 py-3">
                    <h3 className="font-semibold text-foreground">Staff today</h3>
                    <p className="text-xs text-muted-foreground">
                        Tap IN / OUT, take a selfie — no face recognition.
                    </p>
                </div>
                <div className="divide-y divide-border/50">
                    {attendance.map((row) => (
                        <ManualAttendanceRow
                            key={row.user_id}
                            row={row}
                            busy={punchingUserId === row.user_id}
                            punchEnabled={clockEnabled}
                            onPunch={() => void openPunch(row)}
                        />
                    ))}
                </div>
            </div>

            <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                capture="user"
                className="hidden"
                onChange={(e) => onFilePicked(e.target.files?.[0] ?? null)}
            />

            <Dialog
                open={target !== null}
                onOpenChange={(open) => {
                    if (!open) closeDialog();
                }}
            >
                <DialogContent className="sm:max-w-md">
                    <DialogHeader>
                        <DialogTitle>
                            {target ? punchButtonLabel(target) : 'Attendance'}
                        </DialogTitle>
                    </DialogHeader>
                    <p className="text-sm text-muted-foreground">
                        {target?.full_name} — take a selfie to record this punch.
                    </p>
                    <div className="relative mx-auto aspect-square w-full max-w-[220px] overflow-hidden rounded-xl border bg-muted">
                        {preview ? (
                            <img
                                src={preview}
                                alt="Attendance selfie"
                                className="size-full object-cover"
                            />
                        ) : (
                            <video
                                ref={videoRef}
                                playsInline
                                muted
                                className="size-full scale-x-[-1] object-cover"
                            />
                        )}
                        {capturing && (
                            <div className="absolute inset-0 flex items-center justify-center bg-black/30">
                                <Loader2 className="size-8 animate-spin text-white" />
                            </div>
                        )}
                    </div>
                    <DialogFooter className="flex-col gap-2 sm:flex-col">
                        <div className="flex w-full gap-2">
                            <Button
                                type="button"
                                variant="outline"
                                className="flex-1"
                                disabled={punchingUserId !== null}
                                onClick={() => {
                                    if (preview) {
                                        void startCamera();
                                    } else {
                                        snapPhoto();
                                    }
                                }}
                            >
                                {preview ? (
                                    <>
                                        <RefreshCw className="size-4" />
                                        Retake
                                    </>
                                ) : (
                                    <>
                                        <Camera className="size-4" />
                                        Capture
                                    </>
                                )}
                            </Button>
                            <Button
                                type="button"
                                variant="outline"
                                className="flex-1"
                                disabled={punchingUserId !== null}
                                onClick={() => fileInputRef.current?.click()}
                            >
                                Choose photo
                            </Button>
                        </div>
                        <div className="flex w-full gap-2">
                            <Button
                                type="button"
                                variant="ghost"
                                className="flex-1"
                                onClick={closeDialog}
                                disabled={punchingUserId !== null}
                            >
                                <X className="size-4" />
                                Cancel
                            </Button>
                            <Button
                                type="button"
                                className="flex-1"
                                disabled={!preview || punchingUserId !== null}
                                onClick={() => void confirmPunch()}
                            >
                                {punchingUserId !== null ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : null}
                                Use photo
                            </Button>
                        </div>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </>
    );
}

function ManualAttendanceRow({
    row,
    busy,
    punchEnabled,
    onPunch,
}: {
    row: AttendanceRow;
    busy: boolean;
    punchEnabled: boolean;
    onPunch: () => void;
}) {
    const enabled = punchEnabled && canPunch(row) && !busy;
    const label = punchButtonLabel(row);
    const inUrl = selfieInUrl(row);
    const outUrl = selfieOutUrl(row);
    const inTime = selfieInTime(row);
    const outTime = selfieOutTime(row);

    return (
        <div className="flex flex-wrap items-center gap-3 px-4 py-3 sm:flex-nowrap">
            <div className="min-w-[10rem] flex-1">
                <p className="truncate text-sm font-extrabold uppercase tracking-wide text-foreground">
                    {row.full_name}
                </p>
                <p className="text-xs text-muted-foreground">
                    {row.total_hours_label
                        .replace(/hrs?/g, 'hour')
                        .replace(/mins?/g, 'minute')}
                </p>
            </div>

            <PhotoCircle src={inUrl} fallback={<LogIn className="size-4 opacity-40" />} />
            <PhotoCircle src={outUrl} fallback={<LogOut className="size-4 opacity-40" />} />

            <div className="flex shrink-0 flex-col items-center gap-1">
                <button
                    type="button"
                    disabled={!enabled}
                    onClick={onPunch}
                    className={cn(
                        'inline-flex size-16 items-center justify-center rounded-full text-center text-xs font-extrabold leading-tight shadow-sm transition disabled:cursor-not-allowed',
                        actionClass(label),
                    )}
                >
                    {busy ? <Loader2 className="size-5 animate-spin" /> : label}
                </button>
                <span className="text-[11px] font-bold text-muted-foreground">
                    {actionCaption(label)}
                </span>
            </div>

            <div className="grid min-w-[12rem] flex-1 grid-cols-2 gap-2">
                <SelfieMeta label="Selfie-In" time={inTime} tone="teal" />
                <SelfieMeta label="Selfie-Out" time={outTime} tone="orange" />
            </div>
        </div>
    );
}

function PhotoCircle({
    src,
    fallback,
}: {
    src: string | null;
    fallback: ReactNode;
}) {
    return (
        <div className="size-12 shrink-0 overflow-hidden rounded-full border-2 border-border bg-secondary">
            {src ? (
                <img src={src} alt="" className="size-full object-cover" />
            ) : (
                <div className="flex size-full items-center justify-center text-muted-foreground">
                    {fallback}
                </div>
            )}
        </div>
    );
}

function SelfieMeta({
    label,
    time,
    tone,
}: {
    label: string;
    time: string;
    tone: 'teal' | 'orange';
}) {
    const hasTime = time !== '—';
    return (
        <div>
            <div className="flex items-center gap-1.5 text-[11px] font-semibold text-muted-foreground">
                <span
                    className={cn(
                        'size-2 rounded-full',
                        hasTime
                            ? tone === 'teal'
                                ? 'bg-teal-500'
                                : 'bg-orange-500'
                            : 'bg-border',
                    )}
                />
                {label}
            </div>
            <p
                className={cn(
                    'mt-0.5 text-xs font-bold',
                    hasTime ? 'text-foreground' : 'text-muted-foreground',
                )}
            >
                {hasTime ? 'Today' : '—'}
            </p>
            {hasTime ? (
                <p className="text-xs font-semibold text-muted-foreground">{time}</p>
            ) : null}
        </div>
    );
}
