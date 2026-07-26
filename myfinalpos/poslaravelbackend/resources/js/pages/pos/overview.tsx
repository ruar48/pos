import { Head } from '@inertiajs/react';
import {
    Activity,
    CheckCircle2,
    Loader2,
    Wifi,
    XCircle,
} from 'lucide-react';
import { useEffect, useState } from 'react';
import { LiveMonitorPanel } from '@/components/pos/live-monitor-panel';
import { PageHeader } from '@/components/page-header';
import { fetchAppHealth } from '@/lib/overview-api';
import {
    fetchLiveWallSalesReport,
    formatSaleMoney,
    type LiveWallSalesReport,
} from '@/lib/pos-monitor-sales-api';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';

type HealthState =
    | { status: 'loading' }
    | { status: 'ok'; database: string; connected: boolean }
    | { status: 'error'; message: string };

function StatusBadge({
    ok,
    label,
}: {
    ok: boolean;
    label: string;
}) {
    return (
        <span
            className={
                ok
                    ? 'inline-flex items-center gap-1.5 rounded-full bg-primary/10 px-3 py-1 text-xs font-semibold text-primary'
                    : 'inline-flex items-center gap-1.5 rounded-full bg-destructive/10 px-3 py-1 text-xs font-semibold text-destructive'
            }
        >
            {ok ? (
                <CheckCircle2 className="size-3.5" />
            ) : (
                <XCircle className="size-3.5" />
            )}
            {label}
        </span>
    );
}

export default function PosOverview() {
    const [health, setHealth] = useState<HealthState>({ status: 'loading' });
    const [salesReport, setSalesReport] = useState<LiveWallSalesReport | null>(
        null,
    );

    useEffect(() => {
        let cancelled = false;

        fetchAppHealth()
            .then((result) => {
                if (cancelled) return;
                setHealth({
                    status: 'ok',
                    database: result.database ?? 'unknown',
                    connected: result.database_connected ?? result.success,
                });
            })
            .catch((error: Error) => {
                if (cancelled) return;
                setHealth({ status: 'error', message: error.message });
            });

        return () => {
            cancelled = true;
        };
    }, []);

    useEffect(() => {
        let active = true;

        const refreshSales = async () => {
            try {
                const payload = await fetchLiveWallSalesReport();
                if (active) setSalesReport(payload);
            } catch {
                /* keep last snapshot */
            }
        };

        void refreshSales();

        return () => {
            active = false;
        };
    }, []);

    const isHealthy = health.status === 'ok' && health.connected;
    const isLoading = health.status === 'loading';

    return (
        <>
            <Head title="Live POS Monitor" />
            <div className="agri-page-container space-y-4 sm:space-y-5">
                <PageHeader
                    badge="Live Wall"
                    title="Live POS Monitor"
                    description="Works on phone, tablet, PC, and TV — every active register updates live while this page stays open."
                />

                <div className="agri-card flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-6">
                    <div className="flex items-center gap-4">
                        <div
                            className={cn(
                                'flex size-11 shrink-0 items-center justify-center rounded-xl',
                                isLoading
                                    ? 'bg-primary/10 text-primary'
                                    : isHealthy
                                      ? 'bg-primary/10 text-primary'
                                      : 'bg-destructive/10 text-destructive',
                            )}
                        >
                            {isLoading ? (
                                <Loader2 className="size-5 animate-spin" />
                            ) : (
                                <Activity className="size-5" />
                            )}
                        </div>
                        <div>
                            <p className="agri-card-title">System Health</p>
                            <p className="mt-0.5 text-sm text-muted-foreground">
                                {isLoading
                                    ? 'Checking API connection...'
                                    : isHealthy
                                      ? 'All systems operational'
                                      : 'Connection issue detected'}
                            </p>
                        </div>
                    </div>
                    {!isLoading && (
                        <StatusBadge
                            ok={isHealthy}
                            label={isHealthy ? 'Connected' : 'Disconnected'}
                        />
                    )}
                </div>

                {salesReport && (
                    <div className="grid gap-4 sm:grid-cols-3">
                        <div className="agri-card sm:col-span-2 bg-gradient-to-br from-primary/10 via-background to-background p-5">
                            <p className="agri-stat-label">Total sales today</p>
                            <p className="mt-1 text-3xl font-black tabular-nums text-primary sm:text-4xl">
                                ₱{formatSaleMoney(salesReport.overall.net_sales)}
                            </p>
                        </div>
                        <div className="agri-card p-5">
                            <p className="agri-stat-label">Orders today</p>
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

                <div className="agri-card overflow-hidden p-0">
                    <LiveMonitorPanel showTvLink />
                </div>

                <div className="agri-card hidden border-dashed p-5 lg:block">
                    <div className="flex items-start gap-3">
                        <Wifi className="mt-0.5 size-4 shrink-0 text-primary" />
                        <p className="text-sm leading-relaxed text-muted-foreground">
                            <span className="font-medium text-foreground">
                                Display tip:
                            </span>{' '}
                            use <strong>TV display</strong> for a full-screen wall
                            on a smart TV or projector. On phones, tap a register
                            card to expand the full cart.
                        </p>
                    </div>
                </div>
            </div>
        </>
    );
}

PosOverview.layout = {
    breadcrumbs: [
        { title: 'Dashboard', href: dashboard() },
        { title: 'Live POS Monitor', href: '/pos' },
    ],
};
