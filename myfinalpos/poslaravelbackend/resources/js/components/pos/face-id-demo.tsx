import {
    Camera,
    CheckCircle2,
    Loader2,
    ScanFace,
    ShieldCheck,
    UserRound,
    XCircle,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import {
    captureEnrollmentDescriptors,
    captureVerifyDescriptors,
    computeEnrollmentQuality,
    descriptorsAreSamePerson,
    ENROLLMENT_CAPTURE_STEPS,
    type EnrollmentGuideUpdate,
    ensureFaceModels,
    MIN_VERIFY_CONFIDENCE,
    probeFaceInVideo,
} from '@/lib/face-id-engine';
import type { FaceVerifyResult } from '@/lib/face-profile-api';
import {
    deleteFaceProfile,
    enrollFaceProfile,
    fetchFaceProfiles,
    verifyFaceProfile,
    type FaceProfile,
} from '@/lib/face-profile-api';
import type { StaffUser } from '@/lib/staff-api';
import { cn } from '@/lib/utils';

type ScanPhase = 'idle' | 'scanning' | 'success' | 'failed';
type ScanMode = 'enroll' | 'verify';
type ScanFailReason =
    | 'no_face'
    | 'no_match'
    | 'duplicate'
    | 'wrong_person'
    | 'capture_mismatch';

type LiveBanner = {
    title: string;
    detail: string;
};

function initials(name: string): string {
    return name
        .split(' ')
        .filter(Boolean)
        .slice(0, 2)
        .map((p) => p[0]?.toUpperCase() ?? '')
        .join('');
}

export function FaceIdDemo({ users }: { users: StaffUser[] }) {
    const videoRef = useRef<HTMLVideoElement>(null);
    const streamRef = useRef<MediaStream | null>(null);
    const phaseRef = useRef<ScanPhase>('idle');
    const runScanRef = useRef<() => Promise<void>>(async () => {});

    const [cameraOn, setCameraOn] = useState(false);
    const [cameraError, setCameraError] = useState<string | null>(null);
    const [modelsReady, setModelsReady] = useState(false);
    const [modelsError, setModelsError] = useState<string | null>(null);
    const [mode, setMode] = useState<ScanMode>('enroll');
    const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
    const [phase, setPhase] = useState<ScanPhase>('idle');
    const [failReason, setFailReason] = useState<ScanFailReason | null>(null);
    const [matchName, setMatchName] = useState<string | null>(null);
    const [matchConfidence, setMatchConfidence] = useState<number | null>(null);
    const [profiles, setProfiles] = useState<FaceProfile[]>([]);
    const [loadingProfiles, setLoadingProfiles] = useState(true);
    const [faceInFrame, setFaceInFrame] = useState(false);
    const [scanProgress, setScanProgress] = useState<string | null>(null);
    const [enrollmentStep, setEnrollmentStep] = useState(0);
    const [enrollmentGuide, setEnrollmentGuide] =
        useState<EnrollmentGuideUpdate | null>(null);
    const [failBanner, setFailBanner] = useState<LiveBanner | null>(null);

    const activeUsers = useMemo(
        () => users.filter((u) => u.status === 1),
        [users],
    );

    const enrollmentMap = useMemo(() => {
        const map = new Map<number, FaceProfile>();
        for (const profile of profiles) {
            map.set(profile.user_id, profile);
        }
        return map;
    }, [profiles]);

    const enrolledCount = useMemo(
        () =>
            activeUsers.filter((u) => enrollmentMap.has(u.id)).length,
        [activeUsers, enrollmentMap],
    );

    const selectedUser = useMemo(
        () => activeUsers.find((u) => u.id === selectedUserId) ?? null,
        [activeUsers, selectedUserId],
    );

    const loadProfiles = useCallback(async () => {
        setLoadingProfiles(true);
        try {
            const data = await fetchFaceProfiles();
            setProfiles(data);
        } catch (e) {
            toast.error(
                e instanceof Error ? e.message : 'Could not load face profiles',
            );
        } finally {
            setLoadingProfiles(false);
        }
    }, []);

    const stopCamera = useCallback(() => {
        streamRef.current?.getTracks().forEach((track) => track.stop());
        streamRef.current = null;
        if (videoRef.current) {
            videoRef.current.srcObject = null;
        }
        setCameraOn(false);
    }, []);

    const attachStreamToVideo = useCallback(async (stream: MediaStream) => {
        const video = videoRef.current;
        if (!video) {
            return false;
        }

        video.srcObject = stream;
        await video.play();
        return true;
    }, []);

    const startCamera = useCallback(async () => {
        setCameraError(null);

        if (!navigator.mediaDevices?.getUserMedia) {
            setCameraError(
                'Camera is not available in this browser. Use Chrome/Edge on localhost or HTTPS.',
            );
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
            setCameraOn(true);

            const attached = await attachStreamToVideo(stream);
            if (!attached) {
                setCameraError('Camera started but preview is not ready. Tap Enable camera.');
            }
        } catch (error) {
            const message =
                error instanceof Error ? error.message : 'Camera access failed';
            setCameraError(
                message.includes('Permission')
                    ? 'Camera permission denied. Allow camera access for this site and try again.'
                    : 'Camera access denied or unavailable. Allow camera permission and try again.',
            );
            setCameraOn(false);
        }
    }, [attachStreamToVideo]);

    useEffect(() => {
        void loadProfiles();
    }, [loadProfiles]);

    useEffect(() => {
        ensureFaceModels()
            .then(() => setModelsReady(true))
            .catch(() => {
                setModelsError(
                    'Could not load face recognition models. Check your internet connection.',
                );
            });
    }, []);

    useEffect(() => {
        startCamera();
        return () => stopCamera();
    }, [startCamera, stopCamera]);

    useEffect(() => {
        const stream = streamRef.current;
        const video = videoRef.current;
        if (!cameraOn || !stream || !video || video.srcObject) {
            return;
        }

        void attachStreamToVideo(stream).catch(() => {
            setCameraError('Could not start camera preview. Tap Enable camera.');
        });
    }, [attachStreamToVideo, cameraOn]);

    useEffect(() => {
        if (!cameraOn || !modelsReady || phase === 'scanning') {
            setFaceInFrame(false);
            return;
        }

        let cancelled = false;
        const tick = async () => {
            const video = videoRef.current;
            if (!video || cancelled) {
                return;
            }

            try {
                const detected = await probeFaceInVideo(video);
                if (!cancelled) {
                    setFaceInFrame(detected);
                }
            } catch {
                if (!cancelled) {
                    setFaceInFrame(false);
                }
            }
        };

        void tick();
        const interval = window.setInterval(() => {
            void tick();
        }, 700);

        return () => {
            cancelled = true;
            window.clearInterval(interval);
        };
    }, [cameraOn, modelsReady, phase]);

    useEffect(() => {
        if (mode === 'verify') {
            return;
        }

        if (activeUsers.length === 0) {
            setSelectedUserId(null);
            return;
        }
        if (
            selectedUserId === null ||
            !activeUsers.some((u) => u.id === selectedUserId)
        ) {
            setSelectedUserId(activeUsers[0].id);
        }
    }, [activeUsers, mode, selectedUserId]);

    const resetScan = () => {
        setPhase('idle');
        phaseRef.current = 'idle';
        setFailReason(null);
        setFailBanner(null);
        setMatchName(null);
        setMatchConfidence(null);
        setScanProgress(null);
        setEnrollmentStep(0);
        setEnrollmentGuide(null);
    };

    const setFailure = useCallback(
        (reason: ScanFailReason, banner: LiveBanner) => {
            setFailReason(reason);
            setFailBanner(banner);
            setPhase('failed');
            phaseRef.current = 'failed';
            setScanProgress(null);
            setEnrollmentStep(0);
            toast.error(`${banner.title} — ${banner.detail}`);
        },
        [],
    );

    const selectedIsEnrolled = selectedUser
        ? enrollmentMap.has(selectedUser.id)
        : false;

    const scanAction: 'register' | 'verify' | 'update' =
        mode === 'verify'
            ? 'verify'
            : !selectedUser
              ? 'register'
              : !selectedIsEnrolled
                ? 'register'
                : 'update';

    const runScan = useCallback(async () => {
        if (!modelsReady) {
            toast.error(modelsError ?? 'Face models are still loading');
            return;
        }

        if (mode === 'enroll' && !selectedUser) {
            toast.error('Select a staff member to enroll');
            return;
        }

        if (mode === 'verify' && enrolledCount === 0) {
            toast.error('No enrolled faces yet — register staff first');
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
        setFailReason(null);
        setMatchName(null);
        setMatchConfidence(null);
        setScanProgress('Preparing camera...');

        const action =
            mode === 'verify'
                ? 'verify'
                : !selectedUser || !enrollmentMap.has(selectedUser.id)
                  ? 'register'
                  : 'update';

        try {
            if (action === 'register' || action === 'update') {
                if (!selectedUser) {
                    toast.error('Select a staff member to enroll');
                    return;
                }

                const captures = await captureEnrollmentDescriptors(
                    videoRef.current,
                    (update) => {
                        setEnrollmentStep(update.step);
                        setEnrollmentGuide(update);
                        setScanProgress(update.title);
                    },
                );
                setScanProgress(null);
                setEnrollmentStep(0);
                setEnrollmentGuide(null);

                if (!captures) {
                    setFailure('no_face', {
                        title: 'Face not detected',
                        detail:
                            'Follow all 3 steps: far, medium, close. Wait for “Hold steady” on each step.',
                    });
                    return;
                }

                if (!descriptorsAreSamePerson(captures)) {
                    setFailure('capture_mismatch', {
                        title: 'Captures did not match',
                        detail:
                            'All 3 steps must be the same person at different distances. Please try again.',
                    });
                    return;
                }

                const enrollQuality = computeEnrollmentQuality(captures);

                for (const probe of captures) {
                    const existing = await verifyFaceProfile(probe);
                    if (
                        existing.matched &&
                        existing.user_id &&
                        existing.user_id !== selectedUser.id
                    ) {
                        setFailure('duplicate', {
                            title: 'Face already registered',
                            detail: `This face belongs to ${existing.full_name}. Remove it from ${existing.full_name} first, or verify as that person.`,
                        });
                        return;
                    }
                }

                const saved = await enrollFaceProfile({
                    user_id: selectedUser.id,
                    descriptors: captures,
                    confidence: enrollQuality,
                });
                setProfiles((prev) => {
                    const next = prev.filter(
                        (p) => p.user_id !== saved.user_id,
                    );
                    return [...next, saved];
                });
                setMatchName(saved.full_name);
                setMatchConfidence(enrollQuality);
                setPhase('success');
                phaseRef.current = 'success';
                toast.success(
                    action === 'update'
                        ? `Face updated for ${saved.full_name} · enroll quality ${enrollQuality}%`
                        : `Face registered for ${saved.full_name} · enroll quality ${enrollQuality}%`,
                );
                return;
            } else {
                const probes = await captureVerifyDescriptors(
                    videoRef.current,
                    (message) => {
                        setScanProgress(message);
                    },
                );
                setScanProgress(null);

                if (probes.length === 0) {
                    setFailure('no_face', {
                        title: 'Face not detected',
                        detail:
                            'Look straight at the camera and hold steady while we verify.',
                    });
                    return;
                }

                let bestResult: FaceVerifyResult | null = null;

                for (const probe of probes) {
                    const attempt = await verifyFaceProfile(probe);
                    if (!attempt.matched) {
                        continue;
                    }

                    if (
                        (attempt.confidence ?? 0) >= MIN_VERIFY_CONFIDENCE
                    ) {
                        bestResult = attempt;
                        break;
                    }

                    if (
                        !bestResult ||
                        (attempt.confidence ?? 0) >
                            (bestResult.confidence ?? 0)
                    ) {
                        bestResult = attempt;
                    }
                }

                if (!bestResult?.matched) {
                    setFailure('no_match', {
                        title: 'Verification failed',
                        detail:
                            'No enrolled face matched. Register first or try again with better lighting.',
                    });
                    return;
                }

                if ((bestResult.confidence ?? 0) < MIN_VERIFY_CONFIDENCE) {
                    setFailure('no_match', {
                        title: 'Match too weak',
                        detail: `Only ${bestResult.confidence}% confidence. Re-enroll using far, medium, and close captures.`,
                    });
                    return;
                }

                const verifiedLabel = bestResult.role
                    ? `${bestResult.full_name} (${bestResult.role})`
                    : (bestResult.full_name ?? 'Staff member');

                setMatchName(verifiedLabel);
                setMatchConfidence(bestResult.confidence ?? null);
                setPhase('success');
                phaseRef.current = 'success';
                toast.success(`Verified: ${verifiedLabel}`);
                return;
            }

        } catch (e) {
            setScanProgress(null);
            setEnrollmentStep(0);
            setEnrollmentGuide(null);
            const message =
                e instanceof Error ? e.message : 'Face scan failed';
            if (message.toLowerCase().includes('already enrolled')) {
                setFailure('duplicate', {
                    title: 'Face already registered',
                    detail: message,
                });
                return;
            }
            setFailure(action === 'verify' ? 'no_match' : 'no_face', {
                title: action === 'verify' ? 'Verification failed' : 'Scan failed',
                detail: message,
            });
        }
    }, [
        cameraOn,
        enrolledCount,
        enrollmentMap,
        mode,
        modelsError,
        modelsReady,
        selectedUser,
        setFailure,
    ]);

    runScanRef.current = runScan;

    useEffect(() => {
        if (
            mode !== 'verify' ||
            enrolledCount === 0 ||
            !cameraOn ||
            !modelsReady
        ) {
            return;
        }

        let stableTicks = 0;
        let cancelled = false;

        const interval = window.setInterval(() => {
            void (async () => {
                if (cancelled || phaseRef.current !== 'idle') {
                    stableTicks = 0;
                    return;
                }

                const video = videoRef.current;
                if (!video) {
                    return;
                }

                try {
                    const detected = await probeFaceInVideo(video);
                    if (cancelled || phaseRef.current !== 'idle') {
                        return;
                    }

                    if (detected) {
                        stableTicks += 1;
                        if (stableTicks >= 3) {
                            stableTicks = 0;
                            await runScanRef.current();
                        }
                    } else {
                        stableTicks = 0;
                    }
                } catch {
                    stableTicks = 0;
                }
            })();
        }, 550);

        return () => {
            cancelled = true;
            window.clearInterval(interval);
        };
    }, [cameraOn, enrolledCount, modelsReady, mode]);

    const removeEnrollment = async (userId: number) => {
        try {
            await deleteFaceProfile(userId);
            setProfiles((prev) => prev.filter((p) => p.user_id !== userId));
            toast.success('Face profile removed');
        } catch (e) {
            toast.error(
                e instanceof Error ? e.message : 'Could not remove profile',
            );
        }
    };

    return (
        <div className="space-y-4">
            <div className="agri-card flex flex-col gap-3 border-primary/20 bg-primary/5 p-4 sm:flex-row sm:items-center sm:justify-between">
                <div className="flex items-start gap-3">
                    <div className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary/15 text-primary">
                        <ScanFace className="size-5" />
                    </div>
                    <div>
                        <p className="font-semibold text-foreground">
                            Face ID enrollment
                        </p>
                        <p className="text-sm text-muted-foreground">
                            One real person = one staff account.{' '}
                            <span className="font-medium text-foreground">
                                Enroll quality
                            </span>{' '}
                            measures how consistent your 3 registration scans
                            were.{' '}
                            <span className="font-medium text-foreground">
                                Live match %
                            </span>{' '}
                            is scored each time you verify (40%+ passes; 50%+
                            is typical).
                        </p>
                    </div>
                </div>
                <span
                    className={cn(
                        'inline-flex shrink-0 items-center rounded-full px-3 py-1 text-xs font-semibold',
                        modelsReady
                            ? 'bg-emerald-500/15 text-emerald-700'
                            : 'bg-amber-500/15 text-amber-700',
                    )}
                >
                    {modelsReady ? 'Ready' : 'Loading models...'}
                </span>
            </div>

            <div className="grid gap-4 xl:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
                <div className="agri-card overflow-hidden p-5">
                    <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
                        <div>
                            <h3 className="font-semibold text-foreground">
                                Live scanner
                            </h3>
                            <p className="text-xs text-muted-foreground">
                                {mode === 'verify'
                                    ? enrolledCount > 0
                                        ? 'Face the camera — we identify who you are automatically'
                                        : 'Enroll at least one staff member before verifying'
                                    : selectedUser
                                      ? selectedIsEnrolled
                                          ? `Update ${selectedUser.full_name}'s face template`
                                          : `Register ${selectedUser.full_name}'s face`
                                      : 'Select staff below, then scan their face'}
                            </p>
                        </div>
                        <div className="flex rounded-full bg-secondary p-1">
                            {(['enroll', 'verify'] as ScanMode[]).map(
                                (key) => (
                                    <button
                                        key={key}
                                        type="button"
                                        onClick={() => {
                                            setMode(key);
                                            resetScan();
                                        }}
                                        className={cn(
                                            'rounded-full px-3 py-1 text-xs font-semibold capitalize transition-colors',
                                            mode === key
                                                ? 'bg-primary text-primary-foreground shadow-sm'
                                                : 'text-muted-foreground hover:text-foreground',
                                        )}
                                    >
                                        {key}
                                    </button>
                                ),
                            )}
                        </div>
                    </div>

                    <div className="relative mx-auto aspect-[4/3] max-w-lg overflow-hidden rounded-2xl border border-border/60 bg-secondary/30">
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
                            <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 bg-secondary/30 text-muted-foreground">
                                <UserRound className="size-16 opacity-40" />
                                <p className="max-w-xs text-center text-sm">
                                    {cameraError ?? 'Starting camera...'}
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
                                    <div className="absolute inset-x-4 top-0 h-0.5 animate-[face-scan_1.6s_ease-in-out_infinite] rounded-full bg-primary/80 shadow-[0_0_12px_rgba(var(--primary),0.6)]" />
                                )}
                            </div>
                        </div>

                        {phase === 'success' && matchName && (
                            <div className="absolute inset-x-4 bottom-4 rounded-xl bg-emerald-600/90 px-4 py-3 text-white shadow-lg backdrop-blur-sm">
                                <div className="flex items-center gap-2">
                                    <CheckCircle2 className="size-5 shrink-0" />
                                    <div>
                                        <p className="text-sm font-semibold">
                                            {matchName}
                                        </p>
                                        <p className="text-xs text-emerald-100">
                                            {scanAction === 'verify'
                                                ? 'Identity verified'
                                                : scanAction === 'update'
                                                  ? 'Face updated'
                                                  : 'Face registered'}
                                            {matchConfidence != null &&
                                                (scanAction === 'verify'
                                                    ? ` · live match ${matchConfidence}%`
                                                    : ` · enroll quality ${matchConfidence}%`)}
                                        </p>
                                    </div>
                                </div>
                            </div>
                        )}

                        {phase === 'scanning' && (
                            <div className="absolute inset-x-4 top-4 rounded-xl bg-black/75 px-4 py-3 text-center text-white shadow-lg backdrop-blur-sm">
                                {enrollmentGuide?.countdown != null &&
                                enrollmentGuide.phase === 'countdown' ? (
                                    <p className="text-4xl font-bold tabular-nums">
                                        {enrollmentGuide.countdown}
                                    </p>
                                ) : null}
                                <p className="text-sm font-semibold">
                                    {enrollmentGuide?.title ?? scanProgress ?? 'Scanning…'}
                                </p>
                                <p className="mt-1 text-xs text-white/85">
                                    {enrollmentGuide?.message ??
                                        (scanProgress &&
                                        enrollmentGuide?.title !== scanProgress
                                            ? scanProgress
                                            : 'Follow the on-screen steps')}
                                </p>
                            </div>
                        )}

                        {phase === 'scanning' &&
                            (scanAction === 'register' ||
                                scanAction === 'update') && (
                                <div className="absolute inset-x-4 bottom-4 flex justify-center gap-2">
                                    {ENROLLMENT_CAPTURE_STEPS.map((step, index) => (
                                        <span
                                            key={step.key}
                                            className={cn(
                                                'rounded-full px-2.5 py-1 text-[11px] font-semibold',
                                                enrollmentStep > index + 1
                                                    ? 'bg-emerald-500 text-white'
                                                    : enrollmentStep === index + 1
                                                      ? 'bg-primary text-primary-foreground'
                                                      : 'bg-black/50 text-white/80',
                                            )}
                                        >
                                            {step.label}
                                        </span>
                                    ))}
                                </div>
                            )}

                        {phase === 'failed' && failBanner && (
                            <div className="absolute inset-x-4 bottom-4 rounded-xl bg-destructive/90 px-4 py-3 text-white shadow-lg">
                                <div className="flex items-center gap-2">
                                    <XCircle className="size-5 shrink-0" />
                                    <div>
                                        <p className="text-sm font-semibold">
                                            {failBanner.title}
                                        </p>
                                        <p className="text-xs text-red-100">
                                            {failBanner.detail}
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
                                faceInFrame
                                    ? 'text-emerald-700'
                                    : 'text-muted-foreground',
                            )}
                        >
                            {scanAction === 'verify'
                                ? enrolledCount === 0
                                    ? 'Enroll staff faces first, then switch to Verify'
                                    : faceInFrame
                                      ? 'Face detected — hold still for auto-verify, or tap Verify face'
                                      : 'Face the camera to verify — no staff selection needed'
                                : 'Registration guides you: far → hold steady → medium → hold steady → close. Tap Register face to start.'}
                        </p>
                    )}

                    {mode === 'enroll' && (
                        <div className="mt-4">
                            <p className="mb-2 text-xs font-semibold tracking-wide text-muted-foreground uppercase">
                                Enroll for
                            </p>
                            <div className="flex flex-wrap gap-2">
                                {activeUsers.map((user) => (
                                    <button
                                        key={user.id}
                                        type="button"
                                        onClick={() => {
                                            setSelectedUserId(user.id);
                                            resetScan();
                                        }}
                                        className={cn(
                                            'inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-sm font-medium transition-colors',
                                            selectedUserId === user.id
                                                ? 'border-primary bg-primary/10 text-primary'
                                                : 'border-border/60 bg-card hover:bg-secondary/50',
                                        )}
                                    >
                                        <span className="flex size-6 items-center justify-center rounded-full bg-secondary text-[10px] font-bold">
                                            {initials(user.full_name)}
                                        </span>
                                        {user.full_name}
                                        {enrollmentMap.has(user.id) && (
                                            <ShieldCheck className="size-3.5 text-primary" />
                                        )}
                                    </button>
                                ))}
                            </div>
                            {selectedUser && (
                                <p className="mt-2 text-xs text-muted-foreground">
                                    {selectedIsEnrolled
                                        ? `${selectedUser.full_name} is enrolled — enroll mode will update their face.`
                                        : `${selectedUser.full_name} is not enrolled — register with 3 captures (far, medium, close). One face per staff account.`}
                                </p>
                            )}
                        </div>
                    )}

                    <div className="mt-5 flex flex-wrap gap-2">
                        <Button
                            onClick={() => void runScan()}
                            disabled={
                                phase === 'scanning' ||
                                !modelsReady ||
                                (mode === 'enroll' && !selectedUser) ||
                                (mode === 'verify' && enrolledCount === 0)
                            }
                        >
                            {phase === 'scanning' ? (
                                <>
                                    <Loader2 className="size-4 animate-spin" />
                                    Scanning...
                                </>
                            ) : scanAction === 'verify' ? (
                                <>
                                    <ShieldCheck className="size-4" />
                                    Verify face
                                </>
                            ) : scanAction === 'update' ? (
                                <>
                                    <ScanFace className="size-4" />
                                    Update face
                                </>
                            ) : (
                                <>
                                    <ScanFace className="size-4" />
                                    Register face
                                </>
                            )}
                        </Button>
                        {phase !== 'idle' && phase !== 'scanning' && (
                            <Button variant="outline" onClick={resetScan}>
                                Scan again
                            </Button>
                        )}
                    </div>
                </div>

                <div className="space-y-4">
                    <div className="grid gap-4 sm:grid-cols-2">
                        <div className="agri-stat-card">
                            <p className="agri-stat-label">Enrolled</p>
                            <p className="agri-stat-value">{enrolledCount}</p>
                            <p className="mt-1 text-xs text-muted-foreground">
                                of {activeUsers.length} active staff
                            </p>
                        </div>
                        <div className="agri-stat-card">
                            <p className="agri-stat-label">Pending</p>
                            <p className="agri-stat-value">
                                {Math.max(
                                    activeUsers.length - enrolledCount,
                                    0,
                                )}
                            </p>
                            <p className="mt-1 text-xs text-muted-foreground">
                                Need face enrollment
                            </p>
                        </div>
                    </div>

                    <div className="agri-card overflow-hidden">
                        <div className="border-b border-border/60 bg-secondary/30 px-4 py-3">
                            <h3 className="font-semibold text-foreground">
                                Face profiles
                            </h3>
                            <p className="text-xs text-muted-foreground">
                                Server-stored templates for attendance
                                verification
                            </p>
                        </div>
                        <div className="max-h-[28rem] overflow-y-auto">
                            {loadingProfiles ? (
                                <div className="flex items-center justify-center gap-2 py-10 text-sm text-muted-foreground">
                                    <Loader2 className="size-4 animate-spin" />
                                    Loading profiles...
                                </div>
                            ) : activeUsers.length === 0 ? (
                                <p className="px-4 py-10 text-center text-sm text-muted-foreground">
                                    No active staff. Add staff first.
                                </p>
                            ) : (
                                <ul className="divide-y divide-border/40">
                                    {activeUsers.map((user) => {
                                        const enrolled = enrollmentMap.get(
                                            user.id,
                                        );
                                        return (
                                            <li
                                                key={user.id}
                                                className="flex items-center gap-3 px-4 py-3"
                                            >
                                                <div
                                                    className={cn(
                                                        'flex size-10 shrink-0 items-center justify-center rounded-full text-sm font-bold',
                                                        enrolled
                                                            ? 'bg-primary/15 text-primary'
                                                            : 'bg-secondary text-muted-foreground',
                                                    )}
                                                >
                                                    {initials(user.full_name)}
                                                </div>
                                                <div className="min-w-0 flex-1">
                                                    <p className="truncate font-medium text-foreground">
                                                        {user.full_name}
                                                    </p>
                                                    <p className="text-xs capitalize text-muted-foreground">
                                                        {user.role.replace(
                                                            /_/g,
                                                            ' ',
                                                        )}
                                                        {enrolled
                                                            ? ` · enroll quality ${enrolled.confidence}%`
                                                            : ' · Not enrolled'}
                                                    </p>
                                                </div>
                                                {enrolled ? (
                                                    <div className="flex shrink-0 items-center gap-2">
                                                        <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] font-semibold text-primary">
                                                            Enrolled
                                                        </span>
                                                        <Button
                                                            variant="ghost"
                                                            size="sm"
                                                            className="h-8 text-xs text-muted-foreground"
                                                            onClick={() =>
                                                                void removeEnrollment(
                                                                    user.id,
                                                                )
                                                            }
                                                        >
                                                            Remove
                                                        </Button>
                                                    </div>
                                                ) : (
                                                    <Button
                                                        variant="outline"
                                                        size="sm"
                                                        className="h-8 shrink-0"
                                                        onClick={() => {
                                                            setSelectedUserId(
                                                                user.id,
                                                            );
                                                            resetScan();
                                                        }}
                                                    >
                                                        Enroll
                                                    </Button>
                                                )}
                                            </li>
                                        );
                                    })}
                                </ul>
                            )}
                        </div>
                    </div>
                </div>
            </div>

            <style>{`
                @keyframes face-scan {
                    0%, 100% { top: 12%; opacity: 0.4; }
                    50% { top: 82%; opacity: 1; }
                }
            `}</style>
        </div>
    );
}
