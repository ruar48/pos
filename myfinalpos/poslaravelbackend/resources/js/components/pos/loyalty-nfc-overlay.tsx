import {
    AlertTriangle,
    CheckCircle2,
    Loader2,
    Nfc,
    SmartphoneNfc,
    X,
} from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { linkLoyaltyCardNfc } from '@/lib/loyalty-api';
import { cn } from '@/lib/utils';

type ScanPhase =
    | 'preparing'
    | 'scanning'
    | 'linking'
    | 'success'
    | 'error'
    | 'manual';

type NdefReadingEvent = Event & {
    serialNumber?: string;
    message?: unknown;
};

type NdefReaderLike = {
    scan: (options?: { signal?: AbortSignal }) => Promise<void>;
    addEventListener: (
        type: 'reading' | 'readingerror',
        listener: (event: NdefReadingEvent) => void,
    ) => void;
    removeEventListener: (
        type: 'reading' | 'readingerror',
        listener: (event: NdefReadingEvent) => void,
    ) => void;
};

function normalizeUid(value: string): string {
    return value.replace(/[^0-9A-Fa-f]/g, '').toUpperCase();
}

function nfcSupported(): boolean {
    return typeof window !== 'undefined' && 'NDEFReader' in window;
}

function scanErrorMessage(error: unknown): string {
    if (error instanceof DOMException) {
        if (error.name === 'NotAllowedError') {
            return 'NFC permission was denied. Allow NFC access in your browser settings, then try again.';
        }
        if (error.name === 'NotSupportedError') {
            return 'NFC is not supported on this device or browser.';
        }
        if (error.name === 'AbortError') {
            return 'NFC scan was cancelled.';
        }
        return error.message || 'NFC scan failed.';
    }

    if (error instanceof Error) {
        return error.message;
    }

    return 'NFC scan failed. Try again or enter the card UID manually.';
}

export function LoyaltyNfcOverlay({
    open,
    customerId,
    customerName,
    currentRfidUid,
    onLinked,
    onCancel,
}: {
    open: boolean;
    customerId: number;
    customerName: string;
    currentRfidUid?: string | null;
    onLinked: () => void;
    onCancel: () => void;
}) {
    const [phase, setPhase] = useState<ScanPhase>('preparing');
    const [error, setError] = useState<string | null>(null);
    const [manualUid, setManualUid] = useState('');
    const [linkedUid, setLinkedUid] = useState<string | null>(null);

    const abortRef = useRef<AbortController | null>(null);
    const linkingRef = useRef(false);
    const processedUidRef = useRef<string | null>(null);
    const onLinkedRef = useRef(onLinked);
    const readerRef = useRef<NdefReaderLike | null>(null);
    const onReadingRef = useRef<((event: NdefReadingEvent) => void) | null>(null);
    const onReadingErrorRef = useRef<(() => void) | null>(null);
    const startScanRef = useRef<() => Promise<void>>(async () => {});
    const resetRef = useRef<() => void>(() => {});

    onLinkedRef.current = onLinked;

    const stopScan = useCallback(() => {
        const reader = readerRef.current;
        const onReading = onReadingRef.current;
        const onReadingError = onReadingErrorRef.current;

        if (reader && onReading) {
            reader.removeEventListener('reading', onReading);
        }
        if (reader && onReadingError) {
            reader.removeEventListener('readingerror', onReadingError);
        }

        readerRef.current = null;
        onReadingRef.current = null;
        onReadingErrorRef.current = null;

        abortRef.current?.abort();
        abortRef.current = null;
    }, []);

    const reset = useCallback(() => {
        stopScan();
        setPhase('preparing');
        setError(null);
        setManualUid('');
        setLinkedUid(null);
        linkingRef.current = false;
        processedUidRef.current = null;
    }, [stopScan]);

    const linkUid = useCallback(
        async (rawUid: string) => {
            const uid = normalizeUid(rawUid);
            if (uid.length < 4) {
                setError('Invalid RFID UID. The code must be at least 4 characters. Scan the card again or type the UID from the reader display.');
                setPhase('error');
                return;
            }

            if (linkingRef.current || processedUidRef.current === uid) {
                return;
            }

            linkingRef.current = true;
            processedUidRef.current = uid;
            stopScan();
            setPhase('linking');
            setError(null);

            try {
                const res = await linkLoyaltyCardNfc(customerId, uid);
                setLinkedUid(res.data?.nfc_uid ?? uid);
                setPhase('success');
                onLinkedRef.current();
            } catch (err) {
                linkingRef.current = false;
                setError(
                    err instanceof Error
                        ? err.message
                        : 'Failed to link RFID card. Please try again.',
                );
                setPhase('error');
            }
        },
        [customerId, stopScan],
    );

    const startScan = useCallback(async () => {
        stopScan();
        linkingRef.current = false;
        processedUidRef.current = null;

        const controller = new AbortController();
        abortRef.current = controller;

        if (!nfcSupported()) {
            setError(
                'Web NFC is not available here. Use Chrome on an NFC-capable Android tablet, or enter the card UID manually below.',
            );
            setPhase('manual');
            return;
        }

        setPhase('scanning');
        setError(null);

        const onReading = (event: NdefReadingEvent) => {
            if (controller.signal.aborted || linkingRef.current) {
                return;
            }

            const serial = event.serialNumber ?? '';
            if (!serial.trim()) {
                stopScan();
                setError('Card detected but no UID was returned. Try again.');
                setPhase('error');
                return;
            }

            void linkUid(serial);
        };

        const onReadingError = () => {
            if (controller.signal.aborted || linkingRef.current) {
                return;
            }
            stopScan();
            setError('Could not read the NFC card. Hold it closer and try again.');
            setPhase('error');
        };

        onReadingRef.current = onReading;
        onReadingErrorRef.current = onReadingError;

        try {
            const Reader = (window as Window & { NDEFReader: new () => NdefReaderLike })
                .NDEFReader;
            const reader = new Reader();
            readerRef.current = reader;
            reader.addEventListener('reading', onReading);
            reader.addEventListener('readingerror', onReadingError);
            await reader.scan({ signal: controller.signal });
        } catch (err) {
            if (controller.signal.aborted) {
                return;
            }
            stopScan();
            setError(scanErrorMessage(err));
            setPhase('manual');
        }
    }, [linkUid, stopScan]);

    startScanRef.current = startScan;
    resetRef.current = reset;

    useEffect(() => {
        if (!open) {
            resetRef.current();
            return;
        }

        resetRef.current();
        setPhase('manual');
        setError(null);

        return () => {
            stopScan();
        };
    }, [open, customerId, stopScan]);

    if (!open) {
        return null;
    }

    const isUpdate = Boolean(currentRfidUid?.trim());
    const steps = [
        'Plug the OTG RFID reader into the tablet or PC USB port.',
        'Click the scan box below so the cursor is blinking.',
        isUpdate
            ? `Scan the new loyalty card to replace the old card for ${customerName}.`
            : `Hold the loyalty card on the reader to link it to ${customerName}.`,
        'When the UID appears in the box, press Enter on the reader or click Link RFID card.',
    ];

    return (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-background/95 p-4 backdrop-blur-sm">
            <div className="relative w-full max-w-lg rounded-3xl border border-border/60 bg-card p-6 shadow-2xl sm:p-8">
                <button
                    type="button"
                    onClick={onCancel}
                    className="absolute top-4 right-4 rounded-full p-2 text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
                    aria-label="Close RFID linking"
                >
                    <X className="size-5" />
                </button>

                <div className="flex flex-col items-center text-center">
                    <div
                        className={cn(
                            'mb-5 flex size-24 items-center justify-center rounded-full',
                            phase === 'success'
                                ? 'bg-primary/15 text-primary'
                                : phase === 'error'
                                  ? 'bg-destructive/10 text-destructive'
                                  : 'bg-primary/10 text-primary',
                        )}
                    >
                        {phase === 'success' ? (
                            <CheckCircle2 className="size-12" />
                        ) : phase === 'linking' || phase === 'preparing' ? (
                            <Loader2 className="size-12 animate-spin" />
                        ) : phase === 'error' ? (
                            <AlertTriangle className="size-12" />
                        ) : (
                            <Nfc
                                className={cn(
                                    'size-12',
                                    phase === 'scanning' && 'animate-pulse',
                                )}
                            />
                        )}
                    </div>

                    <h2 className="text-xl font-bold text-foreground">
                        {phase === 'success'
                            ? 'RFID card saved'
                            : isUpdate
                              ? `Update RFID card for ${customerName}`
                              : `Link RFID card to ${customerName}`}
                    </h2>
                    <p className="mt-2 max-w-md text-sm text-muted-foreground">
                        {phase === 'success'
                            ? `${customerName} can now use this RFID card at checkout.`
                            : isUpdate
                              ? `This replaces the current card UID for ${customerName}.`
                              : `Register one physical RFID card for ${customerName}.`}
                    </p>

                    {phase !== 'success' ? (
                        <ol className="mt-4 w-full space-y-2 text-left text-sm text-muted-foreground">
                            {steps.map((step, index) => (
                                <li key={step} className="flex gap-2">
                                    <span className="mt-0.5 inline-flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-bold text-primary">
                                        {index + 1}
                                    </span>
                                    <span>{step}</span>
                                </li>
                            ))}
                        </ol>
                    ) : null}

                    {isUpdate && currentRfidUid && phase !== 'success' ? (
                        <p className="mt-3 w-full rounded-xl bg-secondary/40 px-3 py-2 text-left font-mono text-xs text-muted-foreground">
                            Current card UID: {currentRfidUid}
                        </p>
                    ) : null}

                    {phase === 'scanning' ? (
                        <p className="mt-4 inline-flex items-center gap-2 rounded-full bg-primary/10 px-4 py-2 text-sm font-semibold text-primary">
                            <SmartphoneNfc className="size-4" />
                            Waiting for NFC tag…
                        </p>
                    ) : null}

                    {phase === 'linking' ? (
                        <p className="mt-4 text-sm font-medium text-muted-foreground">
                            Saving RFID UID for {customerName}…
                        </p>
                    ) : null}

                    {linkedUid ? (
                        <p className="mt-3 font-mono text-xs text-muted-foreground">
                            UID: {linkedUid}
                        </p>
                    ) : null}

                    {error ? (
                        <div className="mt-4 w-full rounded-2xl border border-destructive/30 bg-destructive/5 px-4 py-3 text-left text-sm text-destructive">
                            {error}
                        </div>
                    ) : null}

                    {(phase === 'manual' || phase === 'error') && phase !== 'success' ? (
                        <div className="mt-5 w-full space-y-3 text-left">
                            <Label htmlFor="manual-rfid-uid">
                                Step 2–3: Scan box — the card UID must appear here
                            </Label>
                            <Input
                                id="manual-rfid-uid"
                                autoFocus
                                value={manualUid}
                                onChange={(e) => {
                                    const value = e.target.value.toUpperCase();
                                    if (value.includes('\n') || value.includes('\r')) {
                                        void linkUid(value);
                                        setManualUid('');
                                        return;
                                    }
                                    setManualUid(value);
                                }}
                                onKeyDown={(event) => {
                                    if (event.key === 'Enter') {
                                        event.preventDefault();
                                        void linkUid(manualUid);
                                    }
                                }}
                                placeholder="Tap here first, then scan the card on the reader"
                                className="font-mono uppercase"
                            />
                            <p className="text-xs text-muted-foreground">
                                The reader types the UID like a keyboard. If nothing
                                shows up, click this box again and rescan the card.
                            </p>
                            <Button
                                className="w-full"
                                disabled={normalizeUid(manualUid).length < 4}
                                onClick={() => void linkUid(manualUid)}
                            >
                                Link RFID card
                            </Button>
                        </div>
                    ) : null}

                    <div className="mt-6 flex w-full flex-wrap justify-center gap-2">
                        {phase === 'error' ? (
                            <Button onClick={() => void startScan()}>
                                <Nfc className="size-4" />
                                Scan again
                            </Button>
                        ) : null}
                        {phase === 'success' ? (
                            <Button onClick={onCancel}>Done</Button>
                        ) : (
                            <Button variant="outline" onClick={onCancel}>
                                {phase === 'linking'
                                    ? 'Cancel'
                                    : 'Cancel — link RFID later'}
                            </Button>
                        )}
                    </div>

                    {phase !== 'success' ? (
                        <p className="mt-4 text-xs text-muted-foreground">
                            Tip: Link the card here first. At checkout, scan the same
                            card to select {customerName} automatically.
                        </p>
                    ) : null}
                </div>
            </div>
        </div>
    );
}
