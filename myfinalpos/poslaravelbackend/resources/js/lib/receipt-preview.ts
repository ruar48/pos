import type { ReceiptStore } from '@/lib/store-settings-api';

const THERMAL_WIDTH = 32;

function center(text: string): string {
    return text.trim();
}

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
    return date.toLocaleDateString('en-US', {
        month: '2-digit',
        day: '2-digit',
        year: 'numeric',
    });
}

function formatTime(date: Date): string {
    return date.toLocaleTimeString('en-US', {
        hour: 'numeric',
        minute: '2-digit',
    });
}

export function buildReceiptPreviewLines(
    store: ReceiptStore,
    currencySymbol: string,
    taxRate: number,
    now = new Date(),
): string[] {
    const lines: string[] = [];
    const add = (line?: string) => {
        if (line != null && line !== '') {
            lines.push(line);
        }
    };

    const isVatRegistered = taxRate > 0;
    const subtotal = 1;
    const vat = isVatRegistered ? subtotal * taxRate : 0;
    const total = subtotal + vat;

    add(center(store.logo_text.trim() || '[ Store ]'));
    add('');
    add(center(store.store_name));
    add(center(store.store_subtitle));
    add(center(store.address_line1));
    add(center(store.address_line2));
    add('');
    add(center('INVOICE'));
    add('');
    add(labelValue('INV NO', 'INV-000001'));
    add(labelValue('DATE', formatDate(now)));
    add(labelValue('TIME', formatTime(now)));
    add(labelValue('CASHIER', 'CASHIER'));
    add(labelValue('POS', store.pos_terminal_id));
    add('');
    add(labelValue('CUSTOMER', 'Walk In Farmer'));
    add('');
    add(labelValue('QTY', 'ITEM'));
    add(divider());
    add(center(`1 Sample Product  ${money(currencySymbol, 1)}`));
    add(divider());
    add(labelValue('ITEMS', '1'));
    add(labelValue('SUBTOTAL', money(currencySymbol, subtotal)));
    if (vat > 0) {
        add(labelValue('VAT', money(currencySymbol, vat)));
    }
    add(divider('='));
    add(labelValue('TOTAL', money(currencySymbol, total)));
    add(divider('='));
    add(labelValue('PAYMENT', 'CASH'));
    add(labelValue('CASH TENDERED', money(currencySymbol, 20)));
    add(labelValue('CHANGE', money(currencySymbol, 20 - total)));
    add('');
    add(center('PERMIT TO USE (PTU)'));
    add(labelValue('PTU NO', store.ptu_no));
    add(center('BIR AUTHORITY TO PRINT (ATP)'));
    add(labelValue('ATP NO', store.atp_no));
    add(labelValue('DATE ISSUED', store.atp_date_issued));
    add(labelValue('SERIES', store.series_range));
    add('');
    add(center('THANK YOU FOR SHOPPING!'));

    return lines;
}
