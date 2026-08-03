import { laravelFetch } from '@/lib/laravel-fetch';
import {
    report as inventoryReportRoute,
    stock as inventoryStockRoute,
} from '@/routes/pos/inventory';

export type InventoryVarietyRow = {
    variety_id: number;
    name: string;
    sku?: string | null;
    image_url?: string | null;
    unit?: string | null;
    beginning: number;
    added: number;
    deducted: number;
    sold: number;
    ending: number;
    live_stock: number;
    reorder_level: number;
    cost_price: number;
    price: number;
    value_cost: number;
    value_retail: number;
    is_low_stock: boolean;
    is_out_of_stock: boolean;
};

export type InventoryRow = {
    product_id: number;
    name: string;
    sku?: string | null;
    unit?: string | null;
    category: string;
    image_url?: string | null;
    beginning: number;
    added: number;
    deducted: number;
    sold: number;
    ending: number;
    live_stock: number;
    reorder_level: number;
    has_varieties: boolean;
    variety_count: number;
    low_varieties_count?: number;
    out_varieties_count?: number;
    min_variety_stock?: number | null;
    max_variety_stock?: number | null;
    varieties?: InventoryVarietyRow[];
    cost_price: number;
    price: number;
    value_cost: number;
    value_retail: number;
    is_low_stock: boolean;
    is_out_of_stock: boolean;
};

export type InventoryCategoryTotal = {
    category: string;
    beginning: number;
    added: number;
    deducted: number;
    ending: number;
    sold: number;
    value_cost: number;
    value_retail: number;
    value_margin: number;
    items: number;
};

export type InventoryTotals = {
    beginning: number;
    added: number;
    deducted: number;
    ending: number;
    sold: number;
    value_cost: number;
    value_retail: number;
    value_margin: number;
    items: number;
    low_stock: number;
    out_of_stock: number;
};

export type InventoryFilteredTotals = {
    beginning: number;
    added: number;
    deducted: number;
    sold: number;
    ending: number;
    value_cost: number;
    value_retail: number;
};

export type InventoryReportMeta = {
    page: number;
    per_page: number;
    total: number;
    has_more: boolean;
    filtered_totals: InventoryFilteredTotals;
};

export type InventoryReport = {
    range: { start: string; end: string };
    valuation_as_of: string;
    rows: InventoryRow[];
    categories: InventoryCategoryTotal[];
    totals: InventoryTotals;
    generated_at: string;
    meta?: InventoryReportMeta;
};

type InventoryCacheEntry = {
    report: InventoryReport;
    savedAt: number;
};

const reportCache = new Map<string, InventoryCacheEntry>();
const reportInFlight = new Map<string, Promise<InventoryReport>>();

function cacheKey(start: string, end: string): string {
    return `${start}|${end}`;
}

export function getInventoryReportCache(
    start: string,
    end: string,
): InventoryReport | null {
    return reportCache.get(cacheKey(start, end))?.report ?? null;
}

export function setInventoryReportCache(
    start: string,
    end: string,
    report: InventoryReport,
): InventoryReport {
    reportCache.set(cacheKey(start, end), {
        report,
        savedAt: Date.now(),
    });
    return report;
}

export function clearInventoryReportCache(): void {
    reportCache.clear();
    reportInFlight.clear();
}

export async function fetchInventoryReport(start: string, end: string) {
    return laravelFetch<InventoryReport>(
        inventoryReportRoute.url({ query: { start, end } }),
    );
}

export async function fetchInventoryReportPage(options: {
    start: string;
    end: string;
    page: number;
    perPage?: number;
    search?: string;
    category?: string;
    status?: string;
}) {
    const query: Record<string, string> = {
        start: options.start,
        end: options.end,
        page: String(options.page),
        per_page: String(options.perPage ?? 100),
    };
    if (options.search) {
        query.search = options.search;
    }
    if (options.category) {
        query.category = options.category;
    }
    if (options.status) {
        query.status = options.status;
    }

    return laravelFetch<InventoryReport>(
        inventoryReportRoute.url({ query }),
    );
}

/** Load inventory report with in-memory cache for fast revisits. */
export async function loadInventoryReport(
    start: string,
    end: string,
    options?: { force?: boolean },
): Promise<InventoryReport> {
    const key = cacheKey(start, end);

    if (!options?.force) {
        const cached = reportCache.get(key);
        if (cached) {
            return cached.report;
        }
        const pending = reportInFlight.get(key);
        if (pending) {
            return pending;
        }
    }

    const request = fetchInventoryReport(start, end).then((report) =>
        setInventoryReportCache(start, end, report),
    );
    reportInFlight.set(key, request);

    try {
        return await request;
    } finally {
        reportInFlight.delete(key);
    }
}

export async function adjustInventoryStock(input: {
    product_id: number;
    variety_id?: number;
    stock?: number;
    delta?: number;
    actor_user_id?: number;
}) {
    clearInventoryReportCache();
    return laravelFetch(inventoryStockRoute.url(), {
        method: 'POST',
        body: JSON.stringify(input),
    });
}
