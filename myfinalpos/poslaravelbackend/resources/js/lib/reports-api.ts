import { laravelFetch } from '@/lib/laravel-fetch';

function rangeQuery(start: string, end: string, extra?: Record<string, string>) {
    const params = new URLSearchParams({ start, end, ...extra });
    return params.toString();
}

export type ReportSummary = {
    range: { start: string; end: string };
    order_count: number;
    gross_sales: number;
    net_sales: number;
    vat_collected: number;
    vat_gross?: number;
    tax_rate?: number;
    sales_reconcile?: number;
    total_discounts: number;
    refunded_amount: number;
    average_order_value: number;
    item_subtotal: number;
    net_merchandise: number;
    revenue: number;
    cogs: number;
    gross_profit: number;
    margin_percent: number;
    payment_methods: {
        payment_method: string;
        order_count: number;
        net_total: number;
    }[];
    daily_trend: {
        date: string;
        net_sales: number;
        order_count: number;
    }[];
};

export type ProfitItem = {
    product_id: number;
    name: string;
    category: string;
    quantity_sold: number;
    revenue: number;
    cogs: number;
    profit: number;
    margin_percent: number;
};

export type ProductMixCategory = {
    category: string;
    items: {
        name: string;
        quantity_sold: number;
        revenue: number;
        cogs: number;
        profit: number;
    }[];
    quantity_sold: number;
    revenue: number;
    cogs: number;
    profit: number;
    margin_percent: number;
};

export type CustomerRow = {
    customer_id: number;
    customer_name: string;
    note: string;
    order_type: string;
    order_count: number;
    total_spent: number;
    avg_transaction: number;
};

export type AuditRow = {
    id: number;
    action: string;
    module: string;
    entity_type: string;
    entity_id: number | null;
    title: string;
    message: string;
    user_name: string;
    created_at: string;
};

export async function fetchReportSummary(start: string, end: string) {
    return laravelFetch<ReportSummary>(
        `/pos/reports/summary?${rangeQuery(start, end)}`,
    );
}

export type SalesVisualSlice = {
    label: string;
    net_total: number;
    order_count: number;
    share_percent?: number;
};

export type SalesVisualsReport = {
    range: { start: string; end: string };
    cashiers: SalesVisualSlice[];
    payments: SalesVisualSlice[];
    customer_activity: SalesVisualSlice[];
    hourly: {
        days: string[];
        day_labels: string[];
        hours: number[];
        hour_labels: string[];
        cells: {
            date: string;
            hour: number;
            units: number;
            amount: number;
        }[];
    };
};

export async function fetchSalesVisuals(start: string, end: string) {
    return laravelFetch<SalesVisualsReport>(
        `/pos/reports/sales-visuals?${rangeQuery(start, end)}`,
    );
}

export async function fetchProfitCharts(start: string, end: string) {
    return laravelFetch<{
        range: { start: string; end: string };
        items: ProfitItem[];
        top_profit_item: ProfitItem | null;
    }>(`/pos/reports/charts?${rangeQuery(start, end)}`);
}

export async function fetchProductMix(start: string, end: string) {
    return laravelFetch<{
        range: { start: string; end: string };
        categories: ProductMixCategory[];
    }>(`/pos/reports/product-mix?${rangeQuery(start, end)}`);
}

export async function fetchCustomerReport(
    start: string,
    end: string,
    search?: string,
) {
    const extra = search?.trim() ? { search: search.trim() } : undefined;
    return laravelFetch<{
        range: { start: string; end: string };
        rows: CustomerRow[];
    }>(`/pos/reports/customers?${rangeQuery(start, end, extra)}`);
}

export async function fetchAuditTrail(
    start: string,
    end: string,
    search?: string,
) {
    const extra = search?.trim() ? { search: search.trim() } : undefined;
    return laravelFetch<{
        range: { start: string; end: string };
        rows: AuditRow[];
    }>(`/pos/reports/audit-trail?${rangeQuery(start, end, extra)}`);
}

export type AttendancePunctualityRow = {
    user_id: number;
    full_name: string;
    role: string;
    branch_name: string;
    rank: number;
    days_tracked: number;
    days_present: number;
    days_early: number;
    days_on_time: number;
    days_almost_late: number;
    days_late: number;
    days_absent: number;
    avg_minutes_from_start: number | null;
    punctuality_score?: number;
};

export type AttendanceSchedule = {
    start_time: string;
    grace_minutes: number;
    late_after_time: string;
};

export async function fetchAttendancePunctuality(start: string, end: string) {
    return laravelFetch<{
        range: { start: string; end: string };
        schedule: AttendanceSchedule;
        rows: AttendancePunctualityRow[];
    }>(`/pos/reports/attendance-punctuality?${rangeQuery(start, end)}`);
}
