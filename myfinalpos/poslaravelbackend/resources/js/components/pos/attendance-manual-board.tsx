import { useCallback, useRef, useState } from 'react';
import { Camera, Loader2, RefreshCw, X } from 'lucide-react';
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
    if (row.next_action === 'clock_in') return 'TIME IN';
    if (row.next_action === 'clock_out') {
        if ((row.punch_count ?? 0) === 1) return 'START BREAK';
        if ((row.punch_count ?? 0) === 3) return 'OUT';
        return 'TIME OUT';
    }
    return 'WAIT';
}

function canPunch(row: AttendanceRow): boolean {
    if (row.day_complete) return false;
    return row.next_action === 'clock_in' || row.next_action === 'clock_out';
}

function resolvePhotoUrl(url: string | null | undefined): string | null {
    if (!url) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return url.startsWith('/') ? url : `/${url}`;
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
            toast.error(
                row.day_complete
                    ? `${row.full_name} is done for today.`
                    : `No punch available right now for ${row.full_name}.`,
            );
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
            const result = typeof reader.result === 'string' ? reader.result : null;
            if (!result) return;
            setMime(file.type || 'image/jpeg');
            setPreview(result);
            stopCamera();
        };
        reader.readAsDataURL(file);
    };

    const confirmPunch = async () => {
        if (!target || !preview) return;
        const action = target.next_action;
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
            <div className="agri-card p-4">
                <div className="mb-4">
                    <h3 className="font-semibold text-foreground">Staff today</h3>
                    <p className="text-xs text-muted-foreground">
                        Tap TIME IN / OUT, then take a selfie. No face recognition.
                    </p>
                </div>
                <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-2 2xl:grid-cols-3">
                    {attendance.map((row) => (
                        <ManualAttendanceCard
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
                    <div className="relative overflow-hidden rounded-xl border bg-muted aspect-[3/4]">
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
                                className="size-full object-cover scale-x-[-1]"
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

function ManualAttendanceCard({
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

    return (
        <div className="rounded-xl border border-border/60 bg-card p-3 shadow-sm">
            <div className="mb-3 flex items-start justify-between gap-3">
                <div className="min-w-0">
                    <p className="truncate font-semibold text-foreground">
                        {row.full_name}
                    </p>
                    <p className="text-xs capitalize text-muted-foreground">
                        {row.role.replace(/_/g, ' ')} · {row.branch_name}
                    </p>
                </div>
                <div
                    className={cn(
                        'flex size-9 shrink-0 items-center justify-center rounded-full text-xs font-bold',
                        row.is_clocked_in
                            ? 'bg-primary/10 text-primary'
                            : 'bg-secondary text-muted-foreground',
                    )}
                >
                    {row.full_name
                        .split(' ')
                        .filter(Boolean)
                        .slice(0, 2)
                        .map((p) => p[0]?.toUpperCase() ?? '')
                        .join('')}
                </div>
            </div>

            <div className="grid grid-cols-4 gap-2 border-y border-border/50 py-3">
                <PunchCell
                    label="In AM"
                    time={row.morning_in_display}
                    photoUrl={row.morning_in_photo_url}
                />
                <PunchCell
                    label="Out lunch"
                    time={row.lunch_out_display}
                    photoUrl={row.lunch_out_photo_url}
                />
                <PunchCell
                    label="In PM"
                    time={row.afternoon_in_display}
                    photoUrl={row.afternoon_in_photo_url}
                />
                <PunchCell
                    label="Out EOD"
                    time={row.day_out_display}
                    photoUrl={row.day_out_photo_url}
                />
            </div>

            <div className="mt-3 flex flex-wrap gap-2 text-xs">
                <span className="rounded-full bg-secondary px-2 py-0.5 font-semibold text-muted-foreground">
                    {row.total_hours_label}
                </span>
                {row.next_action_note ? (
                    <span className="rounded-full bg-primary/10 px-2 py-0.5 font-semibold text-primary">
                        {row.next_action_note}
                    </span>
                ) : null}
            </div>

            <Button
                type="button"
                className="mt-3 w-full font-extrabold tracking-wide"
                disabled={!enabled}
                onClick={onPunch}
            >
                {busy ? <Loader2 className="size-4 animate-spin" /> : null}
                {label}
            </Button>
        </div>
    );
}

function PunchCell({
    label,
    time,
    photoUrl,
}: {
    label: string;
    time?: string | null;
    photoUrl?: string | null;
}) {
    const src = resolvePhotoUrl(photoUrl);
    return (
        <div className="text-center">
            <p className="text-[10px] text-muted-foreground">{label}</p>
            <div className="mx-auto mt-1 size-11 overflow-hidden rounded-lg bg-secondary">
                {src ? (
                    <img src={src} alt="" className="size-full object-cover" />
                ) : (
                    <div className="flex size-full items-center justify-center text-muted-foreground">
                        <Camera className="size-4 opacity-40" />
                    </div>
                )}
            </div>
            <p
                className={cn(
                    'mt-1 text-[11px] font-semibold',
                    time ? 'text-foreground' : 'text-muted-foreground',
                )}
            >
                {time || '—'}
            </p>
        </div>
    );
}
