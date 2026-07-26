import { laravelFetch } from '@/lib/laravel-fetch';

export type DashboardGranularity = 'hourly' | 'daily' | 'monthly';

export type DashboardMetrics = {
    net_sales: number;
    total_discounts: number;
    order_count: number;
    cogs: number;
    items_sold: number;
    profit: number;
    refunded_amount: number;
    unpaid_orders: number;
    online_orders: number;
    gross_sales: number;
    average_order_value: number;
    margin_percent: number;
};

export type DashboardPaymentType = {
    label: string;
    type: 'cash' | 'bank' | 'other';
    order_count: number;
    amount: number;
};

export type DashboardSalesPoint = {
    key: string;
    label: string;
    net_sales: number;
    order_count: number;
};

export type DashboardData = {
    store_name: string;
    last_synced_at: string | null;
    range: { start: string; end: string };
    granularity: DashboardGranularity;
    metrics: DashboardMetrics;
    payment_types: DashboardPaymentType[];
    sales_series: DashboardSalesPoint[];
};

function rangeQuery(
    start: string,
    end: string,
    extra?: Record<string, string>,
) {
    const params = new URLSearchParams({ start, end, ...extra });
    return params.toString();
}

export async function fetchDashboardData(
    start: string,
    end: string,
    granularity: DashboardGranularity,
): Promise<DashboardData> {
    const body = await laravelFetch<{ data: DashboardData }>(
        `/dashboard/data?${rangeQuery(start, end, { granularity })}`,
    );

    if (!body.data) {
        throw new Error('Dashboard response was missing data.');
    }

    return body.data;
}
