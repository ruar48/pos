import { laravelFetch } from '@/lib/laravel-fetch';

export type PosMonitorItem = {
    name: string;
    quantity: number;
    price: number;
    total: number;
};

export type PosMonitorSuccess = {
    invoice_number: string;
    payment_method: string;
    total: number;
    customer_name: string;
    items: PosMonitorItem[];
    completed_at: string;
};

export type PosMonitorState = {
    terminal_id: string;
    terminal_label: string;
    register_code?: string;
    branch_id: number;
    branch_name: string;
    cashier_id: number;
    cashier_name: string;
    cashier_username?: string;
    customer_name: string;
    order_type: string;
    status: 'idle' | 'cart' | 'payment' | 'success';
    is_payment_mode: boolean;
    items: PosMonitorItem[];
    item_count: number;
    subtotal: number;
    discount: number;
    vat: number;
    total: number;
    success?: PosMonitorSuccess | null;
    updated_at: string;
};

export type PosMonitorTerminal = {
    terminal_id: string;
    terminal_label: string;
    register_code?: string;
    cashier_name: string;
    cashier_username?: string;
    branch_name: string;
    status: 'idle' | 'cart' | 'payment' | 'success';
    customer_name: string;
    total: number;
    online: boolean;
    updated_at: string;
};

export type PosMonitorLive = {
    revision: string;
    unchanged: false;
    watching: boolean;
    selected_terminal_id: string | null;
    terminals: PosMonitorTerminal[];
    terminal_states: Record<string, PosMonitorState>;
    online_count: number;
    active_count: number;
    register_online: boolean;
    state: PosMonitorState | null;
};

export type PosMonitorLiveUnchanged = {
    revision: string;
    unchanged: true;
    watching: boolean;
    online_count: number;
    active_count: number;
    terminals?: PosMonitorTerminal[];
    terminal_states?: Record<string, PosMonitorState>;
};

export type PosMonitorLiveResult = PosMonitorLive | PosMonitorLiveUnchanged;

function normalizeLivePayload(
    data: Partial<PosMonitorLive> | Partial<PosMonitorLiveUnchanged> | undefined,
): PosMonitorLiveResult {
    if (data?.unchanged === true) {
        return {
            unchanged: true,
            revision: String(data.revision ?? '0'),
            watching: data.watching === true,
            online_count: Number(data.online_count ?? 0),
            active_count: Number(data.active_count ?? 0),
            terminals: Array.isArray(data.terminals) ? data.terminals : [],
            terminal_states:
                data.terminal_states && typeof data.terminal_states === 'object'
                    ? data.terminal_states
                    : {},
        };
    }

    return {
        unchanged: false,
        revision: String(data?.revision ?? '0'),
        watching: data?.watching === true,
        selected_terminal_id: data?.selected_terminal_id ?? null,
        terminals: Array.isArray(data?.terminals) ? data!.terminals : [],
        terminal_states:
            data?.terminal_states && typeof data.terminal_states === 'object'
                ? data.terminal_states
                : {},
        online_count: Number(data?.online_count ?? 0),
        active_count: Number(data?.active_count ?? 0),
        register_online: data?.register_online === true,
        state: data?.state ?? null,
    };
}

export type PosMonitorWatchResult = {
    changed: boolean;
    revision: string;
};

export function mergeMonitorLive(
    previous: PosMonitorLive | null,
    result: PosMonitorLiveResult,
): PosMonitorLive {
    if (result.unchanged) {
        if (previous) {
            const unchanged = result as PosMonitorLiveUnchanged;
            const terminals = Array.isArray(unchanged.terminals)
                ? unchanged.terminals.filter((terminal) => terminal.online)
                : previous.terminals.filter((terminal) => terminal.online);
            const visibleIds = new Set(
                terminals.map((terminal) => terminal.terminal_id),
            );
            const rawStates =
                unchanged.terminal_states &&
                typeof unchanged.terminal_states === 'object'
                    ? unchanged.terminal_states
                    : previous.terminal_states;
            const terminal_states = Object.fromEntries(
                Object.entries(rawStates).filter(([terminalId]) =>
                    visibleIds.has(terminalId),
                ),
            );

            return {
                ...previous,
                revision: result.revision,
                watching: result.watching,
                online_count: result.online_count,
                active_count: result.active_count,
                terminals,
                terminal_states,
            };
        }

        return {
            unchanged: false,
            revision: result.revision,
            watching: result.watching,
            selected_terminal_id: null,
            terminals: Array.isArray((result as PosMonitorLiveUnchanged).terminals)
                ? (result as PosMonitorLiveUnchanged).terminals!
                : [],
            terminal_states:
                (result as PosMonitorLiveUnchanged).terminal_states ?? {},
            online_count: result.online_count,
            active_count: result.active_count,
            register_online: false,
            state: null,
        };
    }

    return {
        ...result,
        terminals: result.terminals.filter((terminal) => terminal.online),
        terminal_states: Object.fromEntries(
            Object.entries(result.terminal_states).filter(([terminalId]) =>
                result.terminals.some(
                    (terminal) =>
                        terminal.online &&
                        terminal.terminal_id === terminalId,
                ),
            ),
        ),
    };
}

export function visibleMonitorTerminals(
    terminals: PosMonitorTerminal[],
): PosMonitorTerminal[] {
    return terminals.filter((terminal) => terminal.online);
}

export async function watchPosMonitor(
    revision?: string | null,
    signal?: AbortSignal,
): Promise<PosMonitorWatchResult> {
    const params = new URLSearchParams();
    if (revision) {
        params.set('revision', revision);
    }
    const query = params.toString();
    const body = await laravelFetch<{ data: PosMonitorWatchResult }>(
        `/pos/monitor/watch${query ? `?${query}` : ''}`,
        { signal },
    );

    return body.data;
}

export async function subscribePosMonitor(options?: {
    terminalId?: string | null;
    revision?: string | null;
}): Promise<PosMonitorLiveResult> {
    const body = await laravelFetch<{ data: PosMonitorLiveResult }>(
        '/pos/monitor/subscribe',
        {
            method: 'POST',
            body: JSON.stringify({
                ...(options?.terminalId
                    ? { terminal_id: options.terminalId }
                    : {}),
                ...(options?.revision ? { revision: options.revision } : {}),
            }),
        },
    );
    return normalizeLivePayload(body.data);
}

export async function unsubscribePosMonitor(): Promise<void> {
    await laravelFetch('/pos/monitor/unsubscribe', { method: 'POST' });
}

export async function fetchPosMonitorLive(options?: {
    terminalId?: string | null;
    revision?: string | null;
}): Promise<PosMonitorLiveResult> {
    const params = new URLSearchParams();
    if (options?.terminalId) {
        params.set('terminal_id', options.terminalId);
    }
    if (options?.revision) {
        params.set('revision', options.revision);
    }
    const query = params.toString();
    const body = await laravelFetch<{ data: PosMonitorLiveResult }>(
        `/pos/monitor/live${query ? `?${query}` : ''}`,
    );
    return normalizeLivePayload(body.data);
}
