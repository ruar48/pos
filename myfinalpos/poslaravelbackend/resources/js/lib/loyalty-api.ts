import { laravelFetch } from '@/lib/laravel-fetch';

export type LoyaltyTierSummary = {
    tier: string;
    members: number;
    points: number;
};

export type LoyaltyOverview = {
    members: number;
    total_points: number;
    active_cards: number;
    tiers: LoyaltyTierSummary[];
};

export type LoyaltySettings = {
    loyalty_enabled: boolean;
    loyalty_points_per_unit: number;
    loyalty_spend_unit: number;
    loyalty_redeem_points_per_peso: number;
};

export type LoyaltyCard = {
    customer_id: number;
    customer_name: string;
    card_number: string;
    nfc_uid?: string | null;
    points: number;
    tier: string;
    status: string;
    created_at: string | null;
    updated_at: string | null;
};

export type PointsCustomer = {
    customer_id: number;
    customer_name: string;
    table_name: string;
    order_type: string;
    created_at: string | null;
    card_number: string | null;
    nfc_uid?: string | null;
    points: number;
    tier: string | null;
    card_status: string | null;
    card_updated_at: string | null;
    order_count: number;
    total_spent: number;
    avg_transaction: number;
    has_loyalty_card: boolean;
};

export async function fetchLoyaltyOverview() {
    return laravelFetch<{
        overview: LoyaltyOverview;
        settings: LoyaltySettings;
    }>('/pos/loyalty/overview');
}

export async function fetchLoyaltyCards() {
    return laravelFetch<{ data: LoyaltyCard[] }>('/pos/loyalty/cards');
}

export async function fetchPointsCustomers(query?: string) {
    const params = query?.trim() ? `?q=${encodeURIComponent(query.trim())}` : '';
    return laravelFetch<{ data: PointsCustomer[] }>(`/pos/customers/list${params}`);
}

export type SaveCustomerResponse = {
    id: number;
    message: string;
    data: {
        id: number;
        customer_name: string;
        table_name: string;
        order_type: string;
    };
};

export async function savePointsCustomer(input: {
    customer_name: string;
    table_name?: string;
    order_type?: string;
    create_loyalty_card?: boolean;
}) {
    return laravelFetch<SaveCustomerResponse>('/pos/customers', {
        method: 'POST',
        body: JSON.stringify(input),
    });
}

export async function linkLoyaltyCardNfc(customerId: number, nfcUid: string) {
    return laravelFetch<{ message: string; data: LoyaltyCard }>(
        '/pos/customers/link-nfc',
        {
            method: 'POST',
            body: JSON.stringify({
                customer_id: customerId,
                nfc_uid: nfcUid,
            }),
        },
    );
}

export async function issueLoyaltyCard(customerId: number) {
    return laravelFetch('/pos/customers/issue-card', {
        method: 'POST',
        body: JSON.stringify({ customer_id: customerId }),
    });
}

export async function saveLoyaltySettings(input: LoyaltySettings) {
    return laravelFetch<{ message: string; settings: LoyaltySettings }>(
        '/pos/loyalty/settings',
        {
            method: 'POST',
            body: JSON.stringify(input),
        },
    );
}
