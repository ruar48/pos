import { BarChart3, Receipt, TrendingUp, User } from 'lucide-react';
import { useEffect, useState } from 'react';
import {
    fetchLiveWallSalesReport,
    formatSaleMoney,
    formatSaleTime,
    type LiveWallSalesReport,
} from '@/lib/pos-monitor-sales-api';
import type { LiveMonitorDensity } from '@/hooks/use-live-monitor-layout';
import { cn } from '@/lib/utils';

type LiveMonitorSalesTabProps = {
    density?: LiveMonitorDensity;
};

export function LiveMonitorSalesTab({
    density = 'desktop',
}: LiveMonitorSalesTabProps) {
    const [report, setReport] = useState<LiveWallSalesReport | null>(null);
    const [error, setError] = useState<string | null>(null);
    const isLarge = density === 'tv' || density === 'ultra';

    useEffect(() => {
        let active = true;

        const refresh = async () => {
            try {
                const payload = await fetchLiveWallSalesReport();
                if (!active) return;
                setReport(payload);
                setError(null);
            } catch (e) {
                if (!active) return;
                setError(
                    e instanceof Error ? e.message : 'Sales report unavailable',
                );
            }
        };

        void refresh();

        return () => {
            active = false;
        };
    }, []);

    const overall = report?.overall;
    const cashiers = report?.cashiers ?? [];
    const recent = report?.recent_sales ?? [];

    return (
        <div className="live-monitor-sales space-y-4 sm:space-y-5">
            {error && (
                <p className="rounded-lg border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800">
                    {error}
                </p>
            )}

            <div
                className={cn(
                    'grid gap-3',
                    isLarge
                        ? 'grid-cols-2 lg:grid-cols-4'
                        : 'grid-cols-2 lg:grid-cols-4',
                )}
            >
                <SummaryCard
                    icon={Receipt}
                    label="Orders today"
                    value={String(overall?.order_count ?? 0)}
                    large={isLarge}
                />
                <SummaryCard
                    icon={TrendingUp}
                    label="Net sales"
                    value={`₱${formatSaleMoney(overall?.net_sales ?? 0)}`}
                    large={isLarge}
                    accent
                />
                <SummaryCard
                    icon={BarChart3}
                    label="Gross sales"
                    value={`₱${formatSaleMoney(overall?.gross_sales ?? 0)}`}
                    large={isLarge}
                />
                <SummaryCard
                    icon={User}
                    label="Avg. order"
                    value={`₱${formatSaleMoney(overall?.average_order_value ?? 0)}`}
                    large={isLarge}
                />
            </div>

            <div
                className={cn(
                    'grid gap-4',
                    isLarge ? 'lg:grid-cols-5' : 'lg:grid-cols-5',
                )}
            >
                <section className="rounded-2xl border border-border bg-background p-4 shadow-sm lg:col-span-2">
                    <div className="mb-4 flex items-center justify-between gap-2">
                        <h3
                            className={cn(
                                'font-semibold text-foreground',
                                isLarge ? 'text-xl' : 'text-base',
                            )}
                        >
                            Per cashier
                        </h3>
                        <span className="text-xs font-medium text-muted-foreground">
                            Today
                        </span>
                    </div>

                    {cashiers.length === 0 ? (
                        <p className="py-8 text-center text-sm text-muted-foreground">
                            No sales recorded yet today.
                        </p>
                    ) : (
                        <div className="space-y-2">
                            {cashiers.map((cashier) => (
                                <div
                                    key={`${cashier.cashier_id}-${cashier.cashier_name}`}
                                    className="rounded-xl border border-border/70 bg-secondary/15 px-3 py-3"
                                >
                                    <div className="flex items-start justify-between gap-3">
                                        <div className="min-w-0">
                                            <p
                                                className={cn(
                                                    'truncate font-bold text-foreground',
                                                    isLarge && 'text-lg',
                                                )}
                                            >
                                                {cashier.cashier_name}
                                            </p>
                                            <p className="text-xs text-muted-foreground">
                                                {cashier.order_count} sale
                                                {cashier.order_count === 1
                                                    ? ''
                                                    : 's'}
                                                {cashier.last_sale_at
                                                    ? ` · last ${formatSaleTime(cashier.last_sale_at)}`
                                                    : ''}
                                            </p>
                                        </div>
                                        <div className="text-right">
                                            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                                                Net
                                            </p>
                                            <p
                                                className={cn(
                                                    'font-black tabular-nums text-primary',
                                                    isLarge
                                                        ? 'text-2xl'
                                                        : 'text-lg',
                                                )}
                                            >
                                                ₱
                                                {formatSaleMoney(
                                                    cashier.net_sales,
                                                )}
                                            </p>
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </section>

                <section className="rounded-2xl border border-border bg-background p-4 shadow-sm lg:col-span-3">
                    <div className="mb-4 flex items-center justify-between gap-2">
                        <h3
                            className={cn(
                                'font-semibold text-foreground',
                                isLarge ? 'text-xl' : 'text-base',
                            )}
                        >
                            Recent sales
                        </h3>
                        <span className="text-xs font-medium text-muted-foreground">
                            Auto refresh 15s
                        </span>
                    </div>

                    {recent.length === 0 ? (
                        <p className="py-8 text-center text-sm text-muted-foreground">
                            Completed sales will appear here.
                        </p>
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full min-w-[32rem] text-left text-sm">
                                <thead>
                                    <tr className="border-b border-border text-xs uppercase tracking-wide text-muted-foreground">
                                        <th className="px-2 py-2 font-semibold">
                                            Time
                                        </th>
                                        <th className="px-2 py-2 font-semibold">
                                            Cashier
                                        </th>
                                        <th className="px-2 py-2 font-semibold">
                                            Receipt
                                        </th>
                                        <th className="px-2 py-2 font-semibold">
                                            Pay
                                        </th>
                                        <th className="px-2 py-2 text-right font-semibold">
                                            Total
                                        </th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {recent.map((sale) => (
                                        <tr
                                            key={sale.id}
                                            className="border-b border-border/50 last:border-0"
                                        >
                                            <td className="px-2 py-2 tabular-nums text-muted-foreground">
                                                {formatSaleTime(
                                                    sale.created_at,
                                                )}
                                            </td>
                                            <td className="px-2 py-2 font-medium">
                                                {sale.cashier_name}
                                            </td>
                                            <td className="px-2 py-2">
                                                {sale.receipt_number}
                                            </td>
                                            <td className="px-2 py-2">
                                                {sale.payment_method}
                                            </td>
                                            <td className="px-2 py-2 text-right font-bold tabular-nums text-primary">
                                                ₱
                                                {formatSaleMoney(sale.net_total)}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </section>
            </div>
        </div>
    );
}

function SummaryCard({
    icon: Icon,
    label,
    value,
    large = false,
    accent = false,
}: {
    icon: typeof Receipt;
    label: string;
    value: string;
    large?: boolean;
    accent?: boolean;
}) {
    return (
        <div className="rounded-2xl border border-border bg-background p-4 shadow-sm">
            <div className="mb-2 flex items-center gap-2 text-muted-foreground">
                <Icon className="size-4" />
                <span className="text-xs font-semibold uppercase tracking-wide">
                    {label}
                </span>
            </div>
            <p
                className={cn(
                    'font-black tabular-nums',
                    accent ? 'text-primary' : 'text-foreground',
                    large ? 'text-3xl' : 'text-xl',
                )}
            >
                {value}
            </p>
        </div>
    );
}
