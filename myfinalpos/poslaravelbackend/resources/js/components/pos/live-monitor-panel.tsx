import { Link } from '@inertiajs/react';
import {
    ArrowLeft,
    BarChart3,
    ExternalLink,
    Monitor,
    Radio,
    Store,
    TrendingUp,
    WifiOff,
} from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { LiveTerminalCard } from '@/components/pos/live-terminal-card';
import { LiveMonitorSalesTab } from '@/components/pos/live-monitor-sales-tab';
import {
    fetchLiveWallSalesReport,
    formatSaleMoney,
    type LiveWallSalesReport,
} from '@/lib/pos-monitor-sales-api';
import {
    fetchPosMonitorLive,
    mergeMonitorLive,
    subscribePosMonitor,
    unsubscribePosMonitor,
    visibleMonitorTerminals,
    watchPosMonitor,
    type PosMonitorLive,
    type PosMonitorState,
} from '@/lib/pos-monitor-api';
import { useLiveMonitorLayout } from '@/hooks/use-live-monitor-layout';
import { LiveMonitorClock } from '@/components/pos/live-monitor-clock';
import {
    resolveCashierUsername,
} from '@/lib/monitor-status';
import { BRAND } from '@/lib/brand';
import { cn } from '@/lib/utils';

function ExpandedTerminalModal({
    state,
    onClose,
    density,
}: {
    state: PosMonitorState;
    onClose: () => void;
    density: ReturnType<typeof useLiveMonitorLayout>['density'];
}) {
    const items = state.items ?? [];
    const success = state.success;
    const isLarge = density === 'tv' || density === 'ultra';

    return (
        <div
            className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-0 sm:items-center sm:p-4"
            onClick={onClose}
        >
            <div
                className={cn(
                    'max-h-[92vh] w-full overflow-y-auto rounded-t-2xl bg-background shadow-2xl sm:rounded-2xl',
                    isLarge ? 'max-w-4xl p-8' : 'max-w-2xl p-5',
                )}
                onClick={(event) => event.stopPropagation()}
            >
                <div className="mb-4 flex items-start justify-between gap-3">
                    <div>
                        <h3
                            className={cn(
                                'font-bold',
                                isLarge ? 'text-3xl' : 'text-xl',
                            )}
                        >
                            {state.terminal_label}
                        </h3>
                        <p
                            className={cn(
                                'text-muted-foreground',
                                isLarge ? 'text-lg' : 'text-sm',
                            )}
                        >
                            {resolveCashierUsername(
                                {
                                    cashier_name: state.cashier_name,
                                    cashier_username: state.cashier_username,
                                },
                                state,
                            )}
                        </p>
                    </div>
                    <button
                        type="button"
                        className="rounded-lg px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-secondary"
                        onClick={onClose}
                    >
                        Close
                    </button>
                </div>

                {state.status === 'success' && success ? (
                    <div className="space-y-3">
                        <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3">
                            <p
                                className={cn(
                                    'font-bold text-emerald-900',
                                    isLarge && 'text-xl',
                                )}
                            >
                                {success.invoice_number} · {success.payment_method}
                            </p>
                            <p className="text-sm text-emerald-800">
                                Customer: {success.customer_name}
                            </p>
                        </div>
                        {(success.items ?? []).map((item, index) => (
                            <div
                                key={`${item.name}-${index}`}
                                className={cn(
                                    'flex justify-between gap-3 border-b border-border/50 py-2',
                                    isLarge ? 'text-lg' : 'text-sm',
                                )}
                            >
                                <span>
                                    {item.quantity}× {item.name}
                                </span>
                                <span className="font-semibold tabular-nums">
                                    ₱{item.total.toFixed(2)}
                                </span>
                            </div>
                        ))}
                    </div>
                ) : (
                    <div className="space-y-3">
                        {items.map((item, index) => (
                            <div
                                key={`${item.name}-${index}`}
                                className={cn(
                                    'flex justify-between gap-3 border-b border-border/50 py-2',
                                    isLarge ? 'text-lg' : 'text-sm',
                                )}
                            >
                                <span>
                                    {item.quantity}× {item.name}
                                </span>
                                <span className="font-semibold tabular-nums">
                                    ₱{item.total.toFixed(2)}
                                </span>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        </div>
    );
}

type LiveMonitorPanelProps = {
    wallMode?: boolean;
    showTvLink?: boolean;
};

type WallTab = 'live' | 'sales';

export function LiveMonitorPanel({
    wallMode = false,
    showTvLink = false,
}: LiveMonitorPanelProps) {
    const layout = useLiveMonitorLayout();
    const [wallTab, setWallTab] = useState<WallTab>('live');
    const [live, setLive] = useState<PosMonitorLive | null>(null);
    const [monitorError, setMonitorError] = useState<string | null>(null);
    const [expandedTerminalId, setExpandedTerminalId] = useState<string | null>(
        null,
    );
    const [salesReport, setSalesReport] = useState<LiveWallSalesReport | null>(
        null,
    );
    const liveRef = useRef<PosMonitorLive | null>(null);
    const revisionRef = useRef<string | null>(null);

    useEffect(() => {
        liveRef.current = live;
    }, [live]);

    useEffect(() => {
        let active = true;
        const watchAbortRef = { current: null as AbortController | null };

        const abortWatch = () => {
            watchAbortRef.current?.abort();
            watchAbortRef.current = null;
        };

        const applyResult = (result: PosMonitorLive) => {
            if (!active) return;
            revisionRef.current = result.revision;
            setLive(result);
        };

        const refreshLive = async () => {
            const payload = await fetchPosMonitorLive({
                revision: revisionRef.current,
            });
            if (!active) return;
            applyResult(mergeMonitorLive(liveRef.current, payload));
            setMonitorError(null);
        };

        const refreshSales = async () => {
            try {
                const payload = await fetchLiveWallSalesReport();
                if (active) {
                    setSalesReport(payload);
                }
            } catch {
                /* keep last sales snapshot */
            }
        };

        const sleep = (ms: number) =>
            new Promise<void>((resolve) => {
                window.setTimeout(resolve, ms);
            });

        const runWatchLoop = async () => {
            while (active) {
                if (document.hidden) {
                    await sleep(2000);
                    continue;
                }

                try {
                    abortWatch();
                    const controller = new AbortController();
                    watchAbortRef.current = controller;

                    const watchResult = await watchPosMonitor(
                        revisionRef.current,
                        controller.signal,
                    );
                    if (!active) {
                        return;
                    }

                    if (watchResult.changed) {
                        // Fetch before adopting the new revision — otherwise
                        // live?revision=<new> returns unchanged and the UI stalls.
                        await refreshLive();
                        void refreshSales();
                    }

                    revisionRef.current = watchResult.revision;
                } catch (error) {
                    if (!active) {
                        return;
                    }
                    if (
                        error instanceof DOMException &&
                        error.name === 'AbortError'
                    ) {
                        continue;
                    }
                    setMonitorError(
                        error instanceof Error
                            ? error.message
                            : 'Monitor unavailable',
                    );
                    await sleep(2000);
                }
            }
        };

        void (async () => {
            try {
                const payload = await subscribePosMonitor({
                    revision: revisionRef.current,
                });
                if (!active) return;
                applyResult(mergeMonitorLive(liveRef.current, payload));
                setMonitorError(null);
                await refreshSales();
            } catch (e) {
                if (active) {
                    setMonitorError(
                        e instanceof Error ? e.message : 'Monitor unavailable',
                    );
                }
            }
            void runWatchLoop();
        })();

        return () => {
            active = false;
            abortWatch();
            void unsubscribePosMonitor();
        };
    }, [wallMode, wallTab]);

    const terminals = visibleMonitorTerminals(live?.terminals ?? []);
    const terminalStates = live?.terminal_states ?? {};
    const onlineCount = live?.online_count ?? 0;
    const activeCount = live?.active_count ?? 0;
    const expandedState = expandedTerminalId
        ? terminalStates[expandedTerminalId]
        : null;

    const gridStyle = {
        gridTemplateColumns: `repeat(${layout.columns}, minmax(0, 1fr))`,
    } as const;

    return (
        <>
            <div
                className={cn(
                    'live-monitor-panel',
                    wallMode && 'live-monitor-panel--wall',
                    `live-monitor-panel--${layout.density}`,
                )}
            >
                <div
                    className={cn(
                        'flex flex-col gap-3 border-b border-border/60 bg-secondary/20 px-4 py-4 sm:px-5',
                        wallMode && 'sm:px-6 lg:px-8',
                    )}
                >
                    <div className="flex flex-wrap items-center gap-3">
                        {wallMode && (
                            <Link
                                href="/pos"
                                className="live-monitor-chip inline-flex shrink-0 items-center gap-1.5 rounded-full border border-border bg-background font-semibold text-foreground hover:bg-secondary/60"
                            >
                                <ArrowLeft className="live-monitor-chip-icon" />
                                Back to monitor
                            </Link>
                        )}
                        <div className="live-monitor-icon-box flex shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
                            <Monitor className="live-monitor-icon" />
                        </div>
                        <div className="min-w-0">
                            <h2 className="live-monitor-title font-semibold text-foreground">
                                {wallMode
                                    ? BRAND.liveWallTitle
                                    : 'All active registers'}
                            </h2>
                            <p className="live-monitor-subtitle text-muted-foreground">
                                {wallMode
                                    ? 'Event-driven feed — updates only when a register changes'
                                    : 'Event-driven feed — updates only when a register changes'}
                            </p>
                        </div>
                    </div>
                    <div className="flex flex-wrap items-center gap-2">
                        <LiveMonitorClock
                            density={layout.density}
                            wallMode={wallMode}
                            variant="chip"
                        />
                        {wallMode && (
                            <div className="inline-flex rounded-full border border-border bg-background p-1">
                                <button
                                    type="button"
                                    className={cn(
                                        'inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-semibold transition-colors',
                                        wallTab === 'live'
                                            ? 'bg-primary text-primary-foreground'
                                            : 'text-muted-foreground hover:bg-secondary/60',
                                    )}
                                    onClick={() => setWallTab('live')}
                                >
                                    <Monitor className="size-4" />
                                    Live
                                </button>
                                <button
                                    type="button"
                                    className={cn(
                                        'inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-semibold transition-colors',
                                        wallTab === 'sales'
                                            ? 'bg-primary text-primary-foreground'
                                            : 'text-muted-foreground hover:bg-secondary/60',
                                    )}
                                    onClick={() => setWallTab('sales')}
                                >
                                    <BarChart3 className="size-4" />
                                    Sales report
                                </button>
                            </div>
                        )}
                        {(!wallMode || wallTab === 'live') && (
                            <>
                                <span className="live-monitor-chip inline-flex items-center gap-1.5 rounded-full bg-emerald-100 font-semibold text-emerald-800">
                                    <Radio className="live-monitor-chip-icon animate-pulse" />
                                    {onlineCount} online
                                </span>
                                <span className="live-monitor-chip inline-flex items-center gap-1.5 rounded-full bg-sky-100 font-semibold text-sky-800">
                                    <Store className="live-monitor-chip-icon" />
                                    {activeCount} in sale
                                </span>
                                <span
                                    className={cn(
                                        'live-monitor-chip inline-flex items-center gap-1.5 rounded-full font-semibold',
                                        live?.watching
                                            ? 'bg-primary/10 text-primary'
                                            : 'bg-secondary text-muted-foreground',
                                    )}
                                >
                                    {live?.watching
                                        ? 'Watching live'
                                        : 'Connecting…'}
                                </span>
                            </>
                        )}
                        {showTvLink && !wallMode && (
                            <a
                                href="/pos/live-wall"
                                target="_blank"
                                rel="noreferrer"
                                className="live-monitor-chip inline-flex items-center gap-1.5 rounded-full border border-border bg-background font-semibold text-foreground hover:bg-secondary/60"
                            >
                                <ExternalLink className="live-monitor-chip-icon" />
                                TV display
                            </a>
                        )}
                        {!showTvLink && (!wallMode || wallTab === 'live') && (
                            <span className="live-monitor-chip inline-flex items-center gap-1.5 rounded-full bg-primary/10 font-bold text-primary">
                                <TrendingUp className="live-monitor-chip-icon" />
                                Today ₱
                                {formatSaleMoney(
                                    salesReport?.overall.net_sales ?? 0,
                                )}
                            </span>
                        )}
                    </div>
                </div>

                <div className="live-monitor-body p-4 sm:p-5 lg:p-6">
                    {wallMode && wallTab === 'sales' ? (
                        <LiveMonitorSalesTab density={layout.density} />
                    ) : (
                        <>
                    {!showTvLink && salesReport && (
                        <div className="mb-4 grid gap-3 sm:grid-cols-3">
                            <div className="rounded-2xl border border-primary/20 bg-gradient-to-br from-primary/10 via-background to-background p-4 sm:col-span-2">
                                <p className="text-xs font-semibold tracking-wide text-muted-foreground uppercase">
                                    Total sales today
                                </p>
                                <p
                                    className={cn(
                                        'mt-1 font-black tabular-nums text-primary',
                                        layout.density === 'tv' ||
                                            layout.density === 'ultra'
                                            ? 'text-4xl'
                                            : 'text-3xl',
                                    )}
                                >
                                    ₱
                                    {formatSaleMoney(
                                        salesReport.overall.net_sales,
                                    )}
                                </p>
                            </div>
                            <div className="rounded-2xl border border-border bg-background p-4 shadow-sm">
                                <p className="text-xs font-semibold tracking-wide text-muted-foreground uppercase">
                                    Orders today
                                </p>
                                <p className="mt-1 text-3xl font-black tabular-nums text-foreground">
                                    {salesReport.overall.order_count}
                                </p>
                                <p className="mt-1 text-xs text-muted-foreground">
                                    Avg ₱
                                    {formatSaleMoney(
                                        salesReport.overall.average_order_value,
                                    )}
                                </p>
                            </div>
                        </div>
                    )}
                    {monitorError && (
                        <p className="mb-4 rounded-lg border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800 sm:text-base">
                            {monitorError}
                        </p>
                    )}

                    {terminals.length === 0 ? (
                        <div className="live-monitor-empty flex flex-col items-center justify-center rounded-2xl border border-dashed border-border bg-secondary/10 px-4 py-12 text-center sm:px-6 sm:py-16">
                            <WifiOff className="live-monitor-empty-icon mb-3 text-muted-foreground/50" />
                            <p className="live-monitor-empty-title font-semibold text-foreground">
                                No active POS registers yet
                            </p>
                            <p className="live-monitor-empty-copy mt-2 max-w-lg text-muted-foreground">
                                {live?.watching
                                    ? 'Open POS Sales on a tablet. Registers should appear here within a few seconds.'
                                    : 'Connecting to live feed… Keep this page open while cashiers sell.'}
                            </p>
                        </div>
                    ) : (
                        <div
                            className="live-monitor-grid grid gap-3 sm:gap-4 lg:gap-5"
                            style={gridStyle}
                        >
                            {terminals.map((terminal) => (
                                <LiveTerminalCard
                                    key={terminal.terminal_id}
                                    terminal={terminal}
                                    terminalStates={terminalStates}
                                    density={layout.density}
                                    onSelect={() =>
                                        setExpandedTerminalId(
                                            terminal.terminal_id,
                                        )
                                    }
                                />
                            ))}
                        </div>
                    )}
                        </>
                    )}
                </div>
            </div>

            {expandedState && wallTab === 'live' && (
                <ExpandedTerminalModal
                    state={expandedState}
                    density={layout.density}
                    onClose={() => setExpandedTerminalId(null)}
                />
            )}
        </>
    );
}
