import { laravelFetch } from '@/lib/laravel-fetch';

export type TransactionView =
    | 'details'
    | 'transactions'
    | 'hourly'
    | 'daily'
    | 'monthly';

export type TransactionPagination = {
    page: number;
    per_page: number;
    total: number;
    total_pages: number;
};

export type TransactionPaymentLine = {
    payment_method: string;
    amount: number;
    reference?: string | null;
};

export type TransactionOrderRow = {
    id: number;
    receipt_number: string;
    date: string;
    time: string;
    created_at: string;
    cashier_name: string;
    customer_name: string;
    payment_method: string;
    payments?: TransactionPaymentLine[];
    total: number;
    gross_total?: number;
    subtotal?: number;
    vat?: number;
    vat_remaining?: number;
    discount: number;
    notes?: string | null;
    costs: number;
    profits: number;
    items_count: number;
    items_summary: string;
    status: string;
    refunded_amount: number;
    can_refund: boolean;
    items?: TransactionLineItem[];
};

export type TransactionLineItem = {
    order_item_id: number;
    product_id: number;
    product_name: string;
    variety_name: string | null;
    quantity: number;
    refunded_quantity: number;
    price: number;
    total: number;
};

export type TransactionPeriodRow = {
    period_key: string;
    label: string;
    total: number;
    gross_total: number;
    refunded_amount: number;
    refunded_transactions: number;
    status: string;
    transactions: number;
    items: number;
    discount: number;
    costs: number;
    expenses: number;
    profits: number;
    bank_transfer: number;
    best_seller: string;
};

export type TransactionReportData = {
    view: TransactionView;
    range: { start: string; end: string };
    pagination: TransactionPagination;
    rows: TransactionOrderRow[] | TransactionPeriodRow[];
};

function buildQuery(params: Record<string, string | number | undefined>) {
    const search = new URLSearchParams();
    for (const [key, value] of Object.entries(params)) {
        if (value !== undefined && value !== '') {
            search.set(key, String(value));
        }
    }
    return search.toString();
}

export async function fetchTransactionReport(options: {
    view: TransactionView;
    start: string;
    end: string;
    page?: number;
    perPage?: number;
    search?: string;
    unit?: string;
}): Promise<TransactionReportData> {
    const query = buildQuery({
        view: options.view,
        start: options.start,
        end: options.end,
        page: options.page ?? 1,
        per_page: options.perPage ?? 25,
        search: options.search,
        unit: options.unit,
    });

    const body = await laravelFetch<{ data?: TransactionReportData }>(
        `/pos/transactions/data?${query}`,
    );

    if (body.success === false || !body.data) {
        throw new Error(body.message ?? 'Failed to load transaction report');
    }

    return body.data;
}

export async function fetchTransactionUnits(options: {
    start: string;
    end: string;
    search?: string;
}): Promise<string[]> {
    const query = buildQuery({
        start: options.start,
        end: options.end,
        search: options.search,
    });

    const body = await laravelFetch<{ data?: string[] }>(
        `/pos/transactions/units?${query}`,
    );

    if (body.success === false || !body.data) {
        throw new Error(body.message ?? 'Failed to load unit list');
    }

    return body.data;
}

export type RefundItemInput = {
    order_item_id: number;
    quantity: number;
};

export async function processTransactionRefund(payload: {
    order_id: number;
    reason: string;
    refund_type: 'all' | 'items';
    items: RefundItemInput[];
    actor_user_id?: number;
}): Promise<{ success: boolean; message?: string }> {
    const body = await laravelFetch<{ message?: string }>(
        '/pos_app/process_refund.php',
        {
            method: 'POST',
            body: JSON.stringify({
                order_id: payload.order_id,
                reason: payload.reason,
                refund_type: payload.refund_type,
                items: payload.items,
                actor_user_id: payload.actor_user_id,
                action: 'refund',
            }),
        },
    );

    return {
        success: body.success === true,
        message: body.message,
    };
}
