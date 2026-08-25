import type { CashAddition, DrawerExpense } from '@/lib/cash-drawer-api';
import type { ReceiptStore } from '@/lib/store-settings-api';
import { parseServerDateTime } from '@/lib/datetime';

const THERMAL_WIDTH = 24;

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

function wrap(text: string, width = THERMAL_WIDTH): string[] {
    const source = text.trim();
    if (source === '') {
        return [];
    }

    const lines: string[] = [];
    let current = '';

    const flush = () => {
        if (current !== '') {
            lines.push(current);
            current = '';
        }
    };

    for (const word of source.split(/\s+/)) {
        let rest = word;

        // A single token wider than the paper still has to break somewhere.
        while (rest.length > width) {
            flush();
            lines.push(rest.slice(0, width));
            rest = rest.slice(width);
        }

        if (current === '') {
            current = rest;
        } else if (current.length + 1 + rest.length <= width) {
            current = `${current} ${rest}`;
        } else {
            flush();
            current = rest;
        }
    }

    flush();

    return lines;
}

function labelValueLines(label: string, value: string): string[] {
    if (label.length + 1 + value.length <= THERMAL_WIDTH) {
        return [labelValue(label, value)];
    }
    return [label, ...wrap(value)];
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
    if (expense.series_no) {
        labelValueLines('SERIES', expense.series_no).forEach(add);
    }
    add(labelValue('DATE', formatDate(when)));
    add(labelValue('TIME', formatTime(when)));
    labelValueLines('CASHIER', expense.user_name).forEach(add);
    add('');
    add('EXPENSE');
    add(divider());
    wrap(expense.name).forEach(add);
    add(divider());
    labelValueLines('PAYMENT', expense.payment_label).forEach(add);
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
    labelValueLines('CASHIER', addition.user_name).forEach(add);
    add('');
    add('CASH ADDED');
    add(divider());
    const remarkLines = wrap(addition.remarks);
    if (remarkLines.length === 0) {
        add('No remarks');
    } else {
        remarkLines.forEach(add);
    }
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
    add('');
    add(divider());

    for (const expense of expenses) {
        const when = parseServerDateTime(expense.created_at) ?? new Date();

        if (expense.series_no) {
            labelValueLines('SERIES', expense.series_no).forEach(add);
        }
        wrap(expense.name).forEach(add);
        wrap(`${expense.payment_label} · ${formatDate(when)}`).forEach(add);
        add(formatTime(when));
        labelValueLines('BY', expense.user_name).forEach(add);
        add(labelValue('AMOUNT', money(symbol, expense.amount)));
        add(divider());
    }

    add(labelValue('TOTAL', money(symbol, total)));
    add(divider('='));
    add('');
    add('END OF EXPENSE REPORT');

    return lines;
}
