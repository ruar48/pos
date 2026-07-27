import { laravelFetch } from '@/lib/laravel-fetch';

export type CashDrawerSummary = {
    cash_in_drawer: number;
    bank_transfer_sales: number;
    gcash_sales: number;
    cheque_sales: number;
    starting_cash: number;
    cash_added: number;
    cash_sales: number;
    cash_expenses: number;
    non_cash_expenses: number;
};

export type CashAddition = {
    id: number;
    amount: number;
    remarks: string;
    user_name: string;
    created_at: string;
};

export type DrawerExpensePaymentType = 'cash' | 'gcash' | 'bank';

export type DrawerExpense = {
    id: number;
    reference_no: string;
    series_no: string | null;
    name: string;
    amount: number;
    payment_type: DrawerExpensePaymentType;
    payment_label: string;
    user_name: string;
    created_at: string;
};

export type CashDrawerData = {
    business_date: string;
    session_id: number;
    revision: string;
    summary: CashDrawerSummary;
    cash_additions: CashAddition[];
    expenses: DrawerExpense[];
    range: {
        start: string;
        end: string;
    };
};

export type CashDrawerMutation = {
    business_date: string;
    session_id: number;
    revision: string;
    summary: CashDrawerSummary;
    range: {
        start: string;
        end: string;
    };
    expense?: DrawerExpense;
    deleted_expense_id?: number;
    cash_addition?: CashAddition;
    deleted_cash_addition_id?: number;
};

export type CashDrawerUnchanged = {
    unchanged: true;
    revision: string;
};

export type CashDrawerPollResult = CashDrawerData | CashDrawerUnchanged;

export function isCashDrawerUnchanged(
    payload: CashDrawerPollResult,
): payload is CashDrawerUnchanged {
    return 'unchanged' in payload && payload.unchanged === true;
}

export type CashDrawerWatchResult = {
    changed: boolean;
    revision: string;
};

function buildSummaryQuery(date: string, revision?: string | null): string {
    const params = new URLSearchParams({ date });
    if (revision) {
        params.set('revision', revision);
    }
    return `?${params.toString()}`;
}

export async function fetchCashDrawerSummary(
    date: string,
    revision?: string | null,
) {
    return laravelFetch<{ data: CashDrawerPollResult }>(
        `/pos/cash-drawer/summary${buildSummaryQuery(date, revision)}`,
    );
}

/** Waits on the server until a POS sale or drawer edit triggers an update. */
export async function watchCashDrawer(
    date: string,
    revision?: string | null,
    signal?: AbortSignal,
) {
    return laravelFetch<{ data: CashDrawerWatchResult }>(
        `/pos/cash-drawer/watch${buildSummaryQuery(date, revision)}`,
        { signal },
    );
}

export async function verifyCashDrawerPin(cashDrawerPin: string) {
    return laravelFetch<{ data: { verified: boolean } }>(
        '/pos/cash-drawer/verify-pin',
        {
            method: 'POST',
            body: JSON.stringify({ cash_drawer_pin: cashDrawerPin }),
        },
    );
}

export async function updateStartingCash(
    date: string,
    startingCash: number,
    cashDrawerPin: string,
) {
    return laravelFetch<{ data: CashDrawerMutation }>(
        '/pos/cash-drawer/starting-cash',
        {
            method: 'PATCH',
            body: JSON.stringify({
                date,
                starting_cash: startingCash,
                cash_drawer_pin: cashDrawerPin,
            }),
        },
    );
}

export async function addCashAddition(
    date: string,
    amount: number,
    remarks: string,
    cashDrawerPin: string,
) {
    return laravelFetch<{ data: CashDrawerMutation }>(
        '/pos/cash-drawer/cash-additions',
        {
            method: 'POST',
            body: JSON.stringify({
                date,
                amount,
                remarks,
                cash_drawer_pin: cashDrawerPin,
            }),
        },
    );
}

export async function updateCashAddition(
    additionId: number,
    amount: number,
    remarks: string,
    cashDrawerPin: string,
) {
    return laravelFetch<{ data: CashDrawerMutation }>(
        `/pos/cash-drawer/cash-additions/${additionId}`,
        {
            method: 'PUT',
            body: JSON.stringify({
                amount,
                remarks,
                cash_drawer_pin: cashDrawerPin,
            }),
        },
    );
}

export async function deleteCashAddition(
    additionId: number,
    cashDrawerPin: string,
) {
    return laravelFetch<{ data: CashDrawerMutation }>(
        `/pos/cash-drawer/cash-additions/${additionId}`,
        {
            method: 'DELETE',
            body: JSON.stringify({ cash_drawer_pin: cashDrawerPin }),
        },
    );
}

export async function addDrawerExpense(
    date: string,
    name: string,
    amount: number,
    paymentType: DrawerExpensePaymentType,
    cashDrawerPin: string,
    seriesNo?: string,
) {
    return laravelFetch<{ data: CashDrawerMutation }>(
        '/pos/cash-drawer/expenses',
        {
            method: 'POST',
            body: JSON.stringify({
                date,
                name,
                amount,
                payment_type: paymentType,
                series_no: seriesNo?.trim() || null,
                cash_drawer_pin: cashDrawerPin,
            }),
        },
    );
}

export async function updateDrawerExpense(
    expenseId: number,
    name: string,
    amount: number,
    paymentType: DrawerExpensePaymentType,
    cashDrawerPin: string,
    seriesNo?: string | null,
) {
    return laravelFetch<{ data: CashDrawerMutation }>(
        `/pos/cash-drawer/expenses/${expenseId}`,
        {
            method: 'PUT',
            body: JSON.stringify({
                name,
                amount,
                payment_type: paymentType,
                series_no: seriesNo?.trim() || null,
                cash_drawer_pin: cashDrawerPin,
            }),
        },
    );
}

export async function deleteDrawerExpense(
    expenseId: number,
    cashDrawerPin: string,
) {
    return laravelFetch<{ data: CashDrawerMutation }>(
        `/pos/cash-drawer/expenses/${expenseId}`,
        {
            method: 'DELETE',
            body: JSON.stringify({ cash_drawer_pin: cashDrawerPin }),
        },
    );
}

export async function exportCashAdditions(date: string) {
    return laravelFetch<{ data: { rows: CashAddition[] } }>(
        `/pos/cash-drawer/cash-additions/export${buildSummaryQuery(date)}`,
    );
}

export async function exportDrawerExpenses(
    date: string,
    filter: 'all' | DrawerExpensePaymentType = 'all',
) {
    const params = new URLSearchParams({ date });
    if (filter !== 'all') {
        params.set('filter', filter);
    }
    return laravelFetch<{ data: { rows: DrawerExpense[] } }>(
        `/pos/cash-drawer/expenses/export?${params.toString()}`,
    );
}
