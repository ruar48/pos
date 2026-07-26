import { formatServerTime, parseServerDateTime } from '@/lib/datetime';

export type MonitorStatus = 'idle' | 'cart' | 'payment' | 'success';

export type MonitorStatusMeta = {
    label: string;
    badge: string;
    footerTotal: string;
    emptyHint: string;
};

export const MONITOR_STATUS: Record<MonitorStatus, MonitorStatusMeta> = {
    idle: {
        label: 'Ready',
        badge: 'Waiting',
        footerTotal: 'Register total',
        emptyHint: 'Waiting for the next order',
    },
    cart: {
        label: 'Serving',
        badge: 'Adding items',
        footerTotal: 'Cart total',
        emptyHint: 'Cart open — items will appear here live',
    },
    payment: {
        label: 'Checkout',
        badge: 'Payment',
        footerTotal: 'Amount due',
        emptyHint: 'At payment screen',
    },
    success: {
        label: 'Complete',
        badge: 'Order done',
        footerTotal: 'Paid total',
        emptyHint: 'Ready for the next order',
    },
};

export function normalizeMonitorStatus(status: string): MonitorStatus {
    if (status === 'cart' || status === 'payment' || status === 'success') {
        return status;
    }
    return 'idle';
}

export function monitorStatusMeta(status: string): MonitorStatusMeta {
    return MONITOR_STATUS[normalizeMonitorStatus(status)];
}

export function formatMonitorRelativeTime(iso: string | undefined): string {
    if (!iso) {
        return '—';
    }
    const then = parseServerDateTime(iso)?.getTime();
    if (then === undefined || Number.isNaN(then)) {
        return '—';
    }
    const seconds = Math.max(0, Math.floor((Date.now() - then) / 1000));
    if (seconds < 5) {
        return 'Just now';
    }
    if (seconds < 60) {
        return `${seconds}s ago`;
    }
    return formatServerTime(iso);
}

export function resolveCashierName(
    terminal: { cashier_name: string; terminal_label: string },
    state?: { cashier_name?: string; terminal_label?: string } | null,
): string {
    return (
        state?.cashier_name?.trim() ||
        terminal.cashier_name?.trim() ||
        state?.terminal_label?.trim() ||
        terminal.terminal_label?.trim() ||
        'Cashier'
    );
}

export function resolveCashierUsername(
    terminal: { cashier_name: string; cashier_username?: string },
    state?: { cashier_username?: string; cashier_name?: string } | null,
): string {
    return (
        state?.cashier_username?.trim() ||
        terminal.cashier_username?.trim() ||
        state?.cashier_name?.trim() ||
        terminal.cashier_name?.trim() ||
        'Cashier'
    );
}
