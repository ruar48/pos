import type { CashAddition, DrawerExpense } from '@/lib/cash-drawer-api';
import type { ReceiptStore } from '@/lib/store-settings-api';
import { parseServerDateTime } from '@/lib/datetime';

const THERMAL_WIDTH = 32;

function divider(char = '-'): string {
    return char.repeat(THERMAL_WIDTH);
}

function labelValue(label: string, value: string): string {
    const gap = THERMAL_WIDTH - label.length - value.length;
    if (gap >= 1) {
        return `${label}${' '.repeat(gap)}${value}`;
    }
    return `${label} ${value}`.slice(0, THERMAL_WIDTH);
}

function money(symbol: string, amount: number): string {
    return `${symbol}${amount.toFixed(2)}`;
}

function formatDate(date: Date): string {
    return date.toLocaleDateString('en-PH', {
        month: '2-digit',
        day: '2-digit',
        year: 'numeric',
        timeZone: 'Asia/Manila',
    });
}

function formatTime(date: Date): string {
    return date.toLocaleTimeString('en-PH', {
        hour: 'numeric',
        minute: '2-digit',
        timeZone: 'Asia/Manila',
    });
}

export function resolveCurrencySymbol(symbol: string): string {
    if (symbol === 'PHP' || symbol.trim() === '') {
        return '₱';
    }
    return symbol;
}

export function buildExpenseReceiptLines(
    expense: DrawerExpense,
    store: ReceiptStore,
    currencySymbol: string,
): string[] {
    const lines: string[] = [];
    const add = (line?: string) => {
        if (line != null && line !== '') {
            lines.push(line);
        }
    };

    const when = parseServerDateTime(expense.created_at) ?? new Date();
    const symbol = resolveCurrencySymbol(currencySymbol);

    add(store.logo_text.trim() || undefined);
    add(store.store_name);
    add(store.store_subtitle);
    add(store.address_line1);
    add(store.address_line2);
    add('');
    add('EXPENSE RECEIPT');
    add('');
    add(labelValue('REF NO', expense.reference_no));
    if (expense.series_no) {
        add(labelValue('SERIES', expense.series_no.slice(0, THERMAL_WIDTH - 7)));
    }
    add(labelValue('DATE', formatDate(when)));
    add(labelValue('TIME', formatTime(when)));
    add(labelValue('CASHIER', expense.user_name.slice(0, THERMAL_WIDTH - 8)));
    add(labelValue('POS', store.pos_terminal_id));
    add('');
    add('EXPENSE');
    add(divider());
    add(expense.name.slice(0, THERMAL_WIDTH));
    add(divider());
    add(labelValue('PAYMENT', expense.payment_label));
    add(labelValue('AMOUNT', money(symbol, expense.amount)));
    add(divider('='));
    add('');
    add('EXPENSE RECORDED');

    return lines;
}

export function buildCashAdditionReceiptLines(
    addition: CashAddition,
    store: ReceiptStore,
    currencySymbol: string,
    businessDate: string,
): string[] {
    const lines: string[] = [];
    const add = (line?: string) => {
        if (line != null && line !== '') {
            lines.push(line);
        }
    };

    const when = parseServerDateTime(addition.created_at) ?? new Date();
    const symbol = resolveCurrencySymbol(currencySymbol);

    add(store.logo_text.trim() || undefined);
    add(store.store_name);
    add(store.store_subtitle);
    add(store.address_line1);
    add(store.address_line2);
    add('');
    add('CASH ADDITION RECEIPT');
    add('');
    add(labelValue('BUS. DATE', businessDate));
    add(labelValue('DATE', formatDate(when)));
    add(labelValue('TIME', formatTime(when)));
    add(labelValue('CASHIER', addition.user_name.slice(0, THERMAL_WIDTH - 8)));
    add(labelValue('POS', store.pos_terminal_id));
    add('');
    add('CASH ADDED');
    add(divider());
    add(addition.remarks.slice(0, THERMAL_WIDTH) || 'No remarks');
    add(divider());
    add(labelValue('AMOUNT', money(symbol, addition.amount)));
    add(divider('='));
    add('');
    add('CASH ADDITION RECORDED');

    return lines;
}

export function buildAllExpensesReceiptLines(
    expenses: DrawerExpense[],
    store: ReceiptStore,
    currencySymbol: string,
    options: { businessDate: string; filterLabel: string },
): string[] {
    const lines: string[] = [];
    const add = (line?: string) => {
        if (line != null && line !== '') {
            lines.push(line);
        }
    };

    const symbol = resolveCurrencySymbol(currencySymbol);
    const total = expenses.reduce((sum, expense) => sum + expense.amount, 0);

    add(store.logo_text.trim() || undefined);
    add(store.store_name);
    add(store.store_subtitle);
    add(store.address_line1);
    add(store.address_line2);
    add('');
    add('EXPENSE SUMMARY');
    add('');
    add(labelValue('DATE', options.businessDate));
    add(labelValue('FILTER', options.filterLabel));
    add(labelValue('COUNT', String(expenses.length)));
    add(labelValue('POS', store.pos_terminal_id));
    add('');
    add(divider());

    for (const expense of expenses) {
        const when = parseServerDateTime(expense.created_at) ?? new Date();

        add(labelValue('REF NO', expense.reference_no));
        if (expense.series_no) {
            add(labelValue('SERIES', expense.series_no.slice(0, THERMAL_WIDTH - 7)));
        }
        add(expense.name.slice(0, THERMAL_WIDTH));
        add(
            `${expense.payment_label} · ${formatDate(when)} ${formatTime(when)}`
                .slice(0, THERMAL_WIDTH),
        );
        add(labelValue('BY', expense.user_name.slice(0, THERMAL_WIDTH - 3)));
        add(labelValue('AMOUNT', money(symbol, expense.amount)));
        add(divider());
    }

    add(labelValue('TOTAL', money(symbol, total)));
    add(divider('='));
    add('');
    add('END OF EXPENSE REPORT');

    return lines;
}
