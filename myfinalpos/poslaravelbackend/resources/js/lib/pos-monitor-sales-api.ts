import { formatServerTime } from '@/lib/datetime';
import { laravelFetch } from '@/lib/laravel-fetch';

export type LiveWallCashierSales = {
    cashier_id: number;
    cashier_name: string;
    order_count: number;
    gross_sales: number;
    net_sales: number;
    last_sale_at: string;
};

export type LiveWallRecentSale = {
    id: number;
    receipt_number: string;
    cashier_name: string;
    payment_method: string;
    gross_total: number;
    net_total: number;
    created_at: string;
};

export type LiveWallSalesReport = {
    range: { start: string; end: string };
    overall: {
        order_count: number;
        gross_sales: number;
        net_sales: number;
        average_order_value: number;
    };
    cashiers: LiveWallCashierSales[];
    recent_sales: LiveWallRecentSale[];
};

function formatTodayParam(): string {
    const now = new Date();
    const y = now.getFullYear();
    const m = String(now.getMonth() + 1).padStart(2, '0');
    const d = String(now.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
}

export async function fetchLiveWallSalesReport(
    date?: string,
): Promise<LiveWallSalesReport> {
    const day = date ?? formatTodayParam();
    const body = await laravelFetch<{ data: LiveWallSalesReport }>(
        `/pos/monitor/sales?start=${encodeURIComponent(day)}&end=${encodeURIComponent(day)}`,
    );
    return body.data;
}

export function formatSaleMoney(value: number): string {
    return value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
}

export function formatSaleTime(iso: string | undefined): string {
    return formatServerTime(iso);
}
