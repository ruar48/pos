import {
    CheckCircle2,
    CreditCard,
    Receipt,
    ShoppingCart,
    Store,
    User,
    WifiOff,
} from 'lucide-react';
import { useEffect, useState } from 'react';
import {
    type PosMonitorState,
    type PosMonitorTerminal,
} from '@/lib/pos-monitor-api';
import type { LiveMonitorDensity } from '@/hooks/use-live-monitor-layout';
import {
    formatMonitorRelativeTime,
    monitorStatusMeta,
    normalizeMonitorStatus,
    resolveCashierName,
    resolveCashierUsername,
} from '@/lib/monitor-status';
import { cn } from '@/lib/utils';

function formatMoney(value: number): string {
    return value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
}

function cardAccent(status: string, online: boolean): string {
    if (!online) {
        return 'from-slate-400 to-slate-500 border-slate-300';
    }
    switch (normalizeMonitorStatus(status)) {
        case 'success':
            return 'from-emerald-500 to-emerald-600 border-emerald-400 shadow-emerald-500/25';
        case 'payment':
            return 'from-amber-500 to-orange-500 border-amber-400 shadow-amber-500/25';
        case 'cart':
            return 'from-sky-500 to-blue-600 border-sky-400 shadow-sky-500/25';
        default:
            return 'from-primary/95 to-primary border-primary/30 shadow-primary/15';
    }
}

function resolveState(
    terminal: PosMonitorTerminal,
    terminalStates: Record<string, PosMonitorState>,
): PosMonitorState {
    const cached = terminalStates[terminal.terminal_id];
    if (cached) {
        return cached;
    }

    return {
        terminal_id: terminal.terminal_id,
        terminal_label: terminal.terminal_label,
        register_code: terminal.register_code,
        branch_id: 0,
        branch_name: terminal.branch_name,
        cashier_id: 0,
        cashier_name: terminal.cashier_name,
        cashier_username: terminal.cashier_username,
        customer_name: terminal.customer_name || 'Walk-in',
        order_type: 'Retail',
        status: terminal.status,
        is_payment_mode: terminal.status === 'payment',
        items: [],
        item_count: 0,
        subtotal: terminal.total,
        discount: 0,
        vat: 0,
        total: terminal.total,
        updated_at: terminal.updated_at,
    };
}

type LiveTerminalCardProps = {
    terminal: PosMonitorTerminal;
    terminalStates: Record<string, PosMonitorState>;
    density?: LiveMonitorDensity;
    expanded?: boolean;
    onSelect?: () => void;
};

export function LiveTerminalCard({
    terminal,
    terminalStates,
    density = 'desktop',
    expanded = false,
    onSelect,
}: LiveTerminalCardProps) {
    // The monitor feed only re-renders this card when a register's state
    // actually changes (see live-monitor-panel.tsx's watch loop) - without
    // this, "Live · Xs ago" / "Last seen ..." would freeze at whatever it
    // said the moment the register last went idle, no matter how much real
    // time passes afterward. Tick locally so those labels stay honest.
    const [, forceTick] = useState(0);
    useEffect(() => {
        const id = window.setInterval(() => forceTick((n) => n + 1), 5000);
        return () => window.clearInterval(id);
    }, []);

    const state = resolveState(terminal, terminalStates);
    const status = normalizeMonitorStatus(state.status);
    const meta = monitorStatusMeta(status);
    const items = state.items ?? [];
    const success = state.success;
    const isSuccess = status === 'success';
    const isBusy = status === 'cart' || status === 'payment';
    const previewItems = items.slice(0, expanded ? items.length : 4);
    const hiddenCount = Math.max(0, items.length - previewItems.length);
    const cashierName = resolveCashierName(terminal, state);
    const cashierUsername = resolveCashierUsername(terminal, state);
    const syncedAt = state.updated_at || terminal.updated_at;
    const isLarge = density === 'tv' || density === 'ultra';

    const body = (
        <article
            className={cn(
                'live-terminal-card group flex h-full min-h-[18rem] flex-col overflow-hidden rounded-2xl border bg-background shadow-sm transition-all sm:min-h-[20rem]',
                terminal.online
                    ? 'hover:-translate-y-0.5 hover:shadow-lg'
                    : 'opacity-85',
                onSelect && 'cursor-pointer',
                isLarge && 'min-h-[22rem] rounded-3xl',
            )}
        >
            <div
                className={cn(
                    'relative bg-gradient-to-br text-white shadow-md',
                    density === 'phone' ? 'px-3 py-3' : 'px-4 py-4',
                    isLarge && 'px-5 py-5',
                    cardAccent(status, terminal.online),
                )}
            >
                <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                        <div className="flex items-center gap-2">
                            <span
                                className={cn(
                                    'inline-flex rounded-full bg-white',
                                    isLarge ? 'size-3.5' : 'size-2.5',
                                    terminal.online
                                        ? isBusy && 'animate-pulse'
                                        : 'opacity-40',
                                )}
                            />
                            <p
                                className={cn(
                                    'truncate font-bold tracking-tight',
                                    density === 'phone' && 'text-base',
                                    density === 'tablet' && 'text-lg',
                                    density === 'desktop' && 'text-xl',
                                    isLarge && 'text-2xl',
                                    density === 'ultra' && 'text-3xl',
                                )}
                            >
                                {cashierName}
                            </p>
                        </div>
                        <p
                            className={cn(
                                'mt-1 truncate text-white/90',
                                density === 'phone' ? 'text-xs' : 'text-sm',
                                isLarge && 'text-base',
                            )}
                        >
                            {cashierUsername}
                        </p>
                    </div>
                    <span
                        className={cn(
                            'shrink-0 rounded-full bg-black/15 font-bold uppercase tracking-wider text-white',
                            density === 'phone'
                                ? 'px-2 py-0.5 text-[9px]'
                                : 'px-2.5 py-1 text-[10px]',
                            isLarge && 'px-3 py-1.5 text-xs',
                        )}
                    >
                        {terminal.online ? meta.badge : 'Offline'}
                    </span>
                </div>

                <div
                    className={cn(
                        'mt-3 flex flex-wrap gap-2 sm:mt-4',
                        density === 'phone' ? 'text-[11px]' : 'text-xs',
                        isLarge && 'text-sm',
                    )}
                >
                    <span className="inline-flex items-center gap-1 rounded-full bg-black/10 px-2.5 py-1">
                        <Receipt className="size-3.5" />
                        {meta.label}
                    </span>
                    <span className="inline-flex items-center gap-1 rounded-full bg-black/10 px-2.5 py-1">
                        <User className="size-3.5" />
                        {state.customer_name || 'Walk-in'}
                    </span>
                    {isBusy && items.length > 0 && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-black/10 px-2.5 py-1">
                            <ShoppingCart className="size-3.5" />
                            {items.length} item{items.length === 1 ? '' : 's'}
                        </span>
                    )}
                </div>
            </div>

            <div
                className={cn(
                    'flex flex-1 flex-col',
                    density === 'phone' ? 'p-3' : 'p-4',
                    isLarge && 'p-5',
                )}
            >
                {!terminal.online ? (
                    <div className="flex flex-1 flex-col items-center justify-center rounded-xl border border-dashed border-border bg-secondary/20 px-4 py-8 text-center">
                        <WifiOff className="mb-2 size-8 text-muted-foreground/50" />
                        <p className="text-sm font-semibold text-muted-foreground">
                            Register offline
                        </p>
                        <p className="mt-1 text-xs text-muted-foreground">
                            Last seen {formatMonitorRelativeTime(terminal.updated_at)}
                        </p>
                    </div>
                ) : isSuccess ? (
                    <div className="flex flex-1 flex-col gap-3">
                        <div className="flex items-start gap-3 rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-3">
                            <CheckCircle2 className="mt-0.5 size-8 shrink-0 text-emerald-600" />
                            <div className="min-w-0">
                                <p className="font-bold text-emerald-900">
                                    Order complete
                                </p>
                                <p className="truncate text-sm text-emerald-800">
                                    {success?.invoice_number ?? 'Receipt'} ·{' '}
                                    {success?.payment_method ?? 'Cash'}
                                </p>
                                <p className="mt-1 text-xs font-medium text-emerald-700">
                                    {meta.emptyHint}
                                </p>
                            </div>
                        </div>
                        {(success?.items ?? [])
                            .slice(0, expanded ? undefined : 3)
                            .map((item, index) => (
                                <div
                                    key={`${item.name}-${index}`}
                                    className="flex items-center justify-between gap-2 rounded-lg bg-emerald-50/60 px-3 py-2 text-sm"
                                >
                                    <span className="truncate font-medium text-emerald-950">
                                        {item.quantity}× {item.name}
                                    </span>
                                    <span className="shrink-0 tabular-nums font-semibold text-emerald-900">
                                        ₱{formatMoney(item.total)}
                                    </span>
                                </div>
                            ))}
                    </div>
                ) : isBusy ? (
                    <div className="flex flex-1 flex-col gap-2">
                        {state.is_payment_mode && (
                            <div className="mb-1 inline-flex w-fit items-center gap-1.5 rounded-full bg-amber-100 px-2.5 py-1 text-xs font-semibold text-amber-800">
                                <CreditCard className="size-3.5" />
                                Customer at payment screen
                            </div>
                        )}
                        {previewItems.length === 0 ? (
                            <div className="flex flex-1 items-center justify-center rounded-xl border border-dashed border-sky-200 bg-sky-50/70 px-4 py-6 text-center">
                                <div>
                                    <ShoppingCart className="mx-auto mb-2 size-8 text-sky-400" />
                                    <p className="text-sm font-semibold text-sky-900">
                                        {meta.emptyHint}
                                    </p>
                                </div>
                            </div>
                        ) : (
                            previewItems.map((item, index) => (
                                <div
                                    key={`${item.name}-${index}`}
                                    className="flex items-center justify-between gap-2 rounded-lg border border-sky-100 bg-sky-50/80 px-3 py-2 text-sm transition-colors"
                                >
                                    <span className="truncate font-medium text-sky-950">
                                        {item.quantity}× {item.name}
                                    </span>
                                    <span className="shrink-0 tabular-nums font-semibold text-sky-900">
                                        ₱{formatMoney(item.total)}
                                    </span>
                                </div>
                            ))
                        )}
                        {hiddenCount > 0 && (
                            <p className="text-xs font-semibold text-muted-foreground">
                                +{hiddenCount} more item
                                {hiddenCount === 1 ? '' : 's'} in cart
                            </p>
                        )}
                    </div>
                ) : (
                    <div className="flex flex-1 flex-col items-center justify-center rounded-xl border border-dashed border-border bg-secondary/15 px-4 py-8 text-center">
                        <Store className="mb-2 size-8 text-primary/35" />
                        <p className="text-sm font-semibold text-foreground">
                            Ready for next order
                        </p>
                        <p className="mt-1 text-xs text-muted-foreground">
                            {meta.emptyHint}
                        </p>
                    </div>
                )}

                <div className="mt-4 flex items-end justify-between gap-3 border-t border-border/60 pt-3">
                    <div>
                        <p
                            className={cn(
                                'font-semibold uppercase tracking-wide text-muted-foreground',
                                density === 'phone'
                                    ? 'text-[10px]'
                                    : 'text-[11px]',
                                isLarge && 'text-xs',
                            )}
                        >
                            {meta.footerTotal}
                        </p>
                        <p
                            className={cn(
                                'font-black tabular-nums text-primary',
                                density === 'phone' && 'text-xl',
                                density === 'tablet' && 'text-2xl',
                                density === 'desktop' && 'text-2xl',
                                density === 'tv' && 'text-4xl',
                                density === 'ultra' && 'text-5xl',
                            )}
                        >
                            ₱
                            {formatMoney(
                                isSuccess
                                    ? (success?.total ?? state.total)
                                    : state.total,
                            )}
                        </p>
                    </div>
                    <p className="text-right text-[11px] font-medium text-muted-foreground">
                        Live · {formatMonitorRelativeTime(syncedAt)}
                    </p>
                </div>
            </div>
        </article>
    );

    if (onSelect) {
        return (
            <button
                type="button"
                className="h-full w-full min-w-0 text-left"
                onClick={onSelect}
            >
                {body}
            </button>
        );
    }

    return body;
}
